#' @title Thematic classification of news articles
#' @description Three interchangeable back-ends:
#'   \code{"lda"} (Latent Dirichlet Allocation),
#'   \code{"kmeans"} (TF-IDF + k-means clustering), and
#'   \code{"yandex_llm"} (Yandex API call per article).

#' Classify articles into topics
#'
#' @param df        Data frame produced by \code{\link{fetch_news_dataframe}}.
#'   Must contain a \code{content_text} column.
#' @param n_topics  Number of topics (ignored for
#'   \code{"yandex_llm"} methods).
#' @param method    One of \code{"lda"}, \code{"kmeans"}, \code{"yandex_llm"}.
#' @param yandex_api_key API key for Yandex Cloud Assistant API.
#'   If \code{NULL}, reads \code{YANDEX_CLOUD_API_KEY}.
#' @param yandex_folder_id Yandex Cloud folder id.
#'   If \code{NULL}, reads \code{YANDEX_CLOUD_FOLDER}.
#' @param yandex_model Yandex model name without folder prefix
#'   (e.g. \code{"yandexgpt-5-lite/latest"}).
#' @param yandex_base_url Base URL for Yandex Responses API.
#' @param yandex_max_retries Maximum retry attempts for transient
#'   Yandex API failures (HTTP 429/5xx).
#' @param yandex_retry_base_sec Base delay in seconds for exponential backoff.
#' @param use_yandex_cache If \code{TRUE}, caches Yandex responses for repeated
#'   texts within the same R session.
#' @param use_persistent_yandex_cache If \code{TRUE}, persists Yandex cache on
#'   disk between runs.
#' @param yandex_cache_path Path to an RDS file used for persistent Yandex
#'   cache (default from \code{YANDEX_CACHE_PATH}).
#' @param compute_quality If \code{TRUE}, computes quality metrics and stores
#'   them in \code{attr(result, "topic_quality")}.
#' @param language  Stopword language passed to \code{tidytext::get_stopwords()}.
#'   Use \code{c("ru", "en")} for bilingual corpora (default).
#' @param allowed_topics Character vector of allowed closed-set labels for
#'   \code{method = "yandex_llm"}.
#' @param unknown_label Fallback label used when Yandex returns an unsupported
#'   value.
#' @return The original data frame with additional columns:
#'   \code{topic} (integer), \code{topic_label} (character),
#'   \code{topic_prob} (numeric, LDA only).
#' @export
DEFAULT_SECURITY_TOPICS <- c(
  "Malware",
  "Ransomware",
  "Phishing",
  "Vulnerability",
  "Zero-Day",
  "Data Breach",
  "APT",
  "DDoS",
  "Supply Chain",
  "Cloud Security",
  "Identity and Access",
  "Fraud",
  "Threat Intelligence",
  "Incident Response",
  "Regulation and Compliance",
  "Other"
)

classify_news <- function(df,
                          n_topics      = 10L,
                          method        = c("lda", "kmeans", "yandex_llm"),
                          yandex_api_key = NULL,
                          yandex_folder_id = NULL,
                          yandex_model = Sys.getenv("YANDEX_CLOUD_MODEL", "yandexgpt-5-lite/latest"),
                          yandex_base_url = Sys.getenv("YANDEX_CLOUD_BASE_URL", "https://ai.api.cloud.yandex.net/v1"),
                          yandex_max_retries = 3L,
                          yandex_retry_base_sec = 1,
                          use_yandex_cache = TRUE,
                          use_persistent_yandex_cache = TRUE,
                          yandex_cache_path = Sys.getenv("YANDEX_CACHE_PATH", "data/yandex_llm_cache.rds"),
                          compute_quality = FALSE,
                          language      = c("ru", "en"),
                          allowed_topics = DEFAULT_SECURITY_TOPICS,
                          unknown_label = "Other") {

  method <- match.arg(method)
  allowed_topics <- .validate_allowed_topics(allowed_topics, unknown_label)

  if (!"content_text" %in% names(df)) {
    cli::cli_abort("{.arg df} must contain a {.field content_text} column.")
  }

  cli::cli_inform("Classifying {nrow(df)} articles using method={.val {method}}…")

  result <- switch(method,
    lda    = .classify_lda(df, n_topics, language),
    kmeans = .classify_kmeans(df, n_topics, language),
    yandex_llm = .classify_yandex_llm(
      df,
      api_key = yandex_api_key,
      folder_id = yandex_folder_id,
      model = yandex_model,
      base_url = yandex_base_url,
      max_retries = yandex_max_retries,
      retry_base_sec = yandex_retry_base_sec,
      use_cache = use_yandex_cache,
      use_persistent_cache = use_persistent_yandex_cache,
      cache_path = yandex_cache_path,
      allowed_topics = allowed_topics,
      unknown_label = unknown_label
    )
  )

  if (isTRUE(compute_quality)) {
    attr(result, "topic_quality") <- evaluate_topic_quality(result)
  }

  cli::cli_inform("Classification complete.")
  result
}

# ── LDA ───────────────────────────────────────────────────────────────────────

.classify_lda <- function(df, n_topics, language) {

  stopwords_df <- dplyr::bind_rows(
    lapply(language, tidytext::get_stopwords)
  )

  tokens <- df |>
    dplyr::mutate(doc_id = as.character(article_id)) |>
    dplyr::select(doc_id, content_text) |>
    tidytext::unnest_tokens(word, content_text) |>
    dplyr::filter(nchar(word) > 3L) |>
    dplyr::anti_join(stopwords_df, by = "word") |>
    dplyr::count(doc_id, word, sort = TRUE)

  if (nrow(tokens) == 0L) {
    cli::cli_warn("No tokens after pre-processing. Returning unclassified data.")
    df$topic       <- NA_integer_
    df$topic_label <- NA_character_
    df$topic_prob  <- NA_real_
    return(df)
  }

  dtm <- tidytext::cast_dtm(tokens, doc_id, word, n)

  k   <- min(as.integer(n_topics), nrow(dtm) - 1L)
  lda <- topicmodels::LDA(dtm, k = k,
                          control = list(seed = 42L, verbose = 0L))

  # Per-document dominant topic
  gamma_df <- tidytext::tidy(lda, matrix = "gamma") |>
    dplyr::group_by(document) |>
    dplyr::slice_max(gamma, n = 1L, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::rename(doc_id = document, topic = topic, topic_prob = gamma)

  # Top 5 terms per topic as label
  labels_df <- tidytext::tidy(lda, matrix = "beta") |>
    dplyr::group_by(topic) |>
    dplyr::slice_max(beta, n = 5L, with_ties = FALSE) |>
    dplyr::summarise(
      topic_label = paste0("Тема ", topic[1], ": ", paste(term, collapse = ", ")),
      .groups = "drop"
    )

  gamma_df <- dplyr::left_join(gamma_df, labels_df, by = "topic")

  df$doc_id <- as.character(df$article_id)
  df <- dplyr::left_join(df, gamma_df, by = "doc_id")
  df$doc_id <- NULL
  df
}

# ── K-Means ───────────────────────────────────────────────────────────────────

.classify_kmeans <- function(df, n_topics, language) {

  stopwords_df <- dplyr::bind_rows(
    lapply(language, tidytext::get_stopwords)
  )

  tfidf <- df |>
    dplyr::mutate(doc_id = as.character(article_id)) |>
    dplyr::select(doc_id, content_text) |>
    tidytext::unnest_tokens(word, content_text) |>
    dplyr::filter(nchar(word) > 3L) |>
    dplyr::anti_join(stopwords_df, by = "word") |>
    dplyr::count(doc_id, word) |>
    tidytext::bind_tf_idf(word, doc_id, n)

  if (nrow(tfidf) == 0L) {
    df$topic       <- NA_integer_
    df$topic_label <- NA_character_
    return(df)
  }

  wide <- tidyr::pivot_wider(
    tfidf[, c("doc_id", "word", "tf_idf")],
    names_from  = word,
    values_from = tf_idf,
    values_fill = 0
  )

  ids <- wide$doc_id
  mat <- as.matrix(wide[, -1L])

  k  <- min(as.integer(n_topics), nrow(mat) - 1L)
  km <- kmeans(mat, centers = k, nstart = 10L, iter.max = 100L)

  cluster_df <- data.frame(
    doc_id      = as.character(ids),
    topic       = km$cluster,
    topic_label = paste0("Тема ", km$cluster),
    stringsAsFactors = FALSE
  )

  df$doc_id <- as.character(df$article_id)
  df <- dplyr::left_join(df, cluster_df, by = "doc_id")
  df$doc_id <- NULL
  df
}

# ── Yandex LLM ────────────────────────────────────────────────────────────────

.yandex_cache <- new.env(parent = emptyenv())

.classify_yandex_llm <- function(df, api_key, folder_id, model, base_url,
                                 max_retries = 3L,
                                 retry_base_sec = 1,
                                 use_cache = TRUE,
                                 use_persistent_cache = TRUE,
                                 cache_path = "data/yandex_llm_cache.rds",
                                 allowed_topics = DEFAULT_SECURITY_TOPICS,
                                 unknown_label = "Other") {
  allowed_topics <- .validate_allowed_topics(allowed_topics, unknown_label)
  api_key <- api_key %||% Sys.getenv("YANDEX_CLOUD_API_KEY", "")
  folder_id <- folder_id %||% Sys.getenv("YANDEX_CLOUD_FOLDER", "")

  if (!nzchar(api_key)) {
    cli::cli_abort("Provide {.arg yandex_api_key} or set YANDEX_CLOUD_API_KEY for method='yandex_llm'.")
  }
  if (!nzchar(folder_id)) {
    cli::cli_abort("Provide {.arg yandex_folder_id} or set YANDEX_CLOUD_FOLDER for method='yandex_llm'.")
  }

  endpoint <- paste0(sub("/+$", "", base_url), "/responses")
  model_uri <- sprintf("gpt://%s/%s", folder_id, model)
  cache_path <- cache_path %||% ""
  allowed_topics_text <- paste(allowed_topics, collapse = ", ")
  if (isTRUE(use_persistent_cache)) {
    .load_persistent_yandex_cache(cache_path)
  }

  labels <- vapply(seq_len(nrow(df)), function(i) {
    text <- substr(
      paste(df$title[i] %||% "", df$content_text[i] %||% ""),
      1L, 1200L
    )

    body <- list(
      model = model_uri,
      instructions = paste0(
        "Classify the cybersecurity news into exactly one category from this list: ",
        allowed_topics_text, ". ",
        "Return exactly one label from the list, one line only, without explanations or extra text. ",
        "Do not invent new categories."
      ),
      input = text,
      temperature = 0,
      max_output_tokens = 60L
    )

    cache_key <- .yandex_cache_key(model_uri, text)
    if (isTRUE(use_cache) && exists(cache_key, envir = .yandex_cache, inherits = FALSE)) {
      return(get(cache_key, envir = .yandex_cache, inherits = FALSE))
    }

    req <- httr2::request(endpoint) |>
      httr2::req_headers(
        "Authorization" = paste("Api-Key", api_key),
        "OpenAI-Project" = folder_id,
        "Content-Type" = "application/json"
      ) |>
      httr2::req_body_json(body, auto_unbox = TRUE) |>
      httr2::req_error(is_error = \(r) FALSE)

    label <- unknown_label
    attempts <- max(1L, as.integer(max_retries))
    for (attempt in seq_len(attempts)) {
      resp <- tryCatch(httr2::req_perform(req), error = function(e) NULL)
      if (is.null(resp)) {
        if (attempt < attempts) {
          Sys.sleep(retry_base_sec * (2 ^ (attempt - 1L)))
          next
        }
        break
      }

      status <- httr2::resp_status(resp)
      should_retry <- status == 429L || status >= 500L
      if (httr2::resp_is_error(resp) && should_retry && attempt < attempts) {
        Sys.sleep(retry_base_sec * (2 ^ (attempt - 1L)))
        next
      }
      if (httr2::resp_is_error(resp)) break

      parsed <- httr2::resp_body_json(resp, simplifyVector = FALSE)
      txt <- .extract_response_output_text(parsed)
      label <- .normalize_topic_label(
        txt %||% unknown_label,
        allowed_topics = allowed_topics,
        unknown_label = unknown_label
      )
      break
    }

    if (isTRUE(use_cache)) {
      assign(cache_key, label, envir = .yandex_cache)
    }
    label
  }, character(1L))

  df$topic_label <- labels
  df$topic       <- as.integer(factor(labels, levels = allowed_topics))
  if (isTRUE(use_persistent_cache)) {
    .save_persistent_yandex_cache(cache_path)
  }
  df
}

.validate_allowed_topics <- function(allowed_topics, unknown_label = "Other") {
  labels <- unique(trimws(as.character(allowed_topics)))
  labels <- labels[nzchar(labels)]
  if (!length(labels)) {
    cli::cli_abort("{.arg allowed_topics} must contain at least one non-empty label.")
  }
  if (!unknown_label %in% labels) {
    cli::cli_abort("{.arg allowed_topics} must include {.val {unknown_label}}.")
  }
  labels
}

.normalize_topic_label <- function(label, allowed_topics, unknown_label = "Other") {
  raw <- trimws(as.character(label %||% ""))
  if (!nzchar(raw)) return(unknown_label)
  raw <- strsplit(raw, "\n", fixed = TRUE)[[1L]][1L]
  raw <- trimws(gsub("^[[:punct:][:space:]]+|[[:punct:][:space:]]+$", "", raw))
  if (!nzchar(raw)) return(unknown_label)

  exact_idx <- match(raw, allowed_topics)
  if (!is.na(exact_idx)) return(allowed_topics[[exact_idx]])

  lower_allowed <- tolower(allowed_topics)
  lower_raw <- tolower(raw)
  case_idx <- match(lower_raw, lower_allowed)
  if (!is.na(case_idx)) return(allowed_topics[[case_idx]])

  unknown_label
}

.yandex_cache_key <- function(model_uri, text) {
  txt <- text %||% ""
  head_part <- substring(txt, 1L, min(200L, nchar(txt)))
  tail_part <- substring(txt, max(1L, nchar(txt) - 199L), nchar(txt))
  paste(model_uri, nchar(txt), head_part, tail_part, sep = "||")
}

.load_persistent_yandex_cache <- function(cache_path) {
  if (!nzchar(cache_path) || !file.exists(cache_path)) return(invisible(FALSE))
  obj <- tryCatch(readRDS(cache_path), error = function(e) NULL)
  if (!is.list(obj) || !length(obj)) return(invisible(FALSE))
  for (nm in names(obj)) {
    assign(nm, as.character(obj[[nm]]), envir = .yandex_cache)
  }
  invisible(TRUE)
}

.save_persistent_yandex_cache <- function(cache_path) {
  if (!nzchar(cache_path)) return(invisible(FALSE))
  dir.create(dirname(cache_path), recursive = TRUE, showWarnings = FALSE)
  vals <- as.list(.yandex_cache, all.names = TRUE)
  tryCatch(saveRDS(vals, cache_path), error = function(e) invisible(FALSE))
  invisible(TRUE)
}

.extract_response_output_text <- function(parsed) {
  txt <- parsed$output_text %||% NULL
  if (!is.null(txt) && nzchar(txt)) return(txt)

  output <- parsed$output %||% list()
  if (!length(output)) return(NULL)

  parts <- unlist(lapply(output, function(item) {
    content <- item$content %||% list()
    if (!length(content)) return(NULL)
    unlist(lapply(content, function(p) p$text %||% NULL), use.names = FALSE)
  }), use.names = FALSE)

  if (!length(parts)) return(NULL)
  paste(parts[nzchar(parts)], collapse = " ")
}

#' Evaluate quality of topic labels
#'
#' Computes lightweight post-classification quality metrics that can be used
#' for regression checks and model comparison.
#'
#' @param df Classified data frame returned by \code{classify_news()}.
#' @param text_col Column name with normalized article text.
#' @param label_col Column name with assigned topic labels.
#' @param min_token_len Minimum token length for quality tokenization.
#' @return A named list with summary metrics and per-topic counts.
#' @export
evaluate_topic_quality <- function(df,
                                   text_col = "content_text",
                                   label_col = "topic_label",
                                   min_token_len = 4L) {
  if (!is.data.frame(df) || nrow(df) == 0L) {
    cli::cli_abort("{.arg df} must be a non-empty data frame.")
  }
  if (!text_col %in% names(df)) {
    cli::cli_abort("Column {.field {text_col}} not found in {.arg df}.")
  }
  if (!label_col %in% names(df)) {
    cli::cli_abort("Column {.field {label_col}} not found in {.arg df}.")
  }

  labels <- trimws(as.character(df[[label_col]]))
  labels[is.na(labels)] <- ""
  n_docs <- nrow(df)
  n_labeled <- sum(nzchar(labels))
  topic_counts <- sort(table(labels[nzchar(labels)]), decreasing = TRUE)
  n_topics <- length(topic_counts)

  coverage <- n_labeled / n_docs
  p <- if (n_labeled > 0L) as.numeric(topic_counts) / n_labeled else numeric()
  entropy <- if (length(p)) -sum(p * log(p)) else 0
  normalized_entropy <- if (n_topics > 1L) entropy / log(n_topics) else 0
  dominant_topic_share <- if (length(p)) max(p) else 0

  distinctiveness <- .topic_distinctiveness_score(
    df = df,
    text_col = text_col,
    label_col = label_col,
    min_token_len = min_token_len
  )

  list(
    n_documents = n_docs,
    n_labeled = n_labeled,
    label_coverage = coverage,
    n_topics = n_topics,
    dominant_topic_share = dominant_topic_share,
    topic_balance_entropy = normalized_entropy,
    topic_distinctiveness = distinctiveness$score,
    per_topic = data.frame(
      topic_label = names(topic_counts),
      n_articles = as.integer(topic_counts),
      share = if (n_labeled > 0L) as.numeric(topic_counts) / n_labeled else 0,
      stringsAsFactors = FALSE
    )
  )
}

.topic_distinctiveness_score <- function(df, text_col, label_col, min_token_len = 4L) {
  work <- df[, c(text_col, label_col), drop = FALSE]
  names(work) <- c("content_text", "topic_label")
  work <- work[!is.na(work$topic_label) & nzchar(trimws(work$topic_label)), , drop = FALSE]
  if (nrow(work) == 0L) return(list(score = 0))

  tokens <- work |>
    dplyr::mutate(doc_id = seq_len(dplyr::n())) |>
    tidytext::unnest_tokens(word, content_text) |>
    dplyr::filter(nchar(word) >= as.integer(min_token_len)) |>
    dplyr::count(topic_label, word, sort = TRUE)

  if (nrow(tokens) == 0L) return(list(score = 0))

  top_terms <- tokens |>
    dplyr::group_by(topic_label) |>
    dplyr::slice_max(n, n = 10L, with_ties = FALSE) |>
    dplyr::summarise(terms = list(unique(word)), .groups = "drop")

  if (nrow(top_terms) < 2L) return(list(score = 1))

  comb <- utils::combn(seq_len(nrow(top_terms)), 2L)
  overlaps <- apply(comb, 2L, function(idx) {
    a <- top_terms$terms[[idx[1L]]]
    b <- top_terms$terms[[idx[2L]]]
    inter <- length(intersect(a, b))
    union <- length(unique(c(a, b)))
    if (union == 0L) return(0)
    inter / union
  })

  list(score = 1 - mean(overlaps))
}
