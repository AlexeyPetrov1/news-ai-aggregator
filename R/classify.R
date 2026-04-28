#' @title Thematic classification of news articles
#' @description Three interchangeable back-ends:
#'   \code{"lda"} (Latent Dirichlet Allocation),
#'   \code{"kmeans"} (TF-IDF + k-means clustering), and
#'   \code{"llm"} / \code{"yandex_llm"} (LLM API call per article).

#' Classify articles into topics
#'
#' @param df        Data frame produced by \code{\link{fetch_news_dataframe}}.
#'   Must contain a \code{content_text} column.
#' @param n_topics  Number of topics (ignored for \code{"llm"} and
#'   \code{"yandex_llm"} methods).
#' @param method    One of \code{"lda"}, \code{"kmeans"}, \code{"llm"},
#'   \code{"yandex_llm"}.
#' @param llm_api_key  API key (required for \code{method = "llm"}).
#' @param llm_base_url Base URL of the LLM API
#'   (default: Anthropic \code{https://api.anthropic.com}).
#' @param yandex_api_key API key for Yandex Cloud Assistant API.
#'   If \code{NULL}, reads \code{YANDEX_CLOUD_API_KEY}.
#' @param yandex_folder_id Yandex Cloud folder id.
#'   If \code{NULL}, reads \code{YANDEX_CLOUD_FOLDER}.
#' @param yandex_model Yandex model name without folder prefix
#'   (e.g. \code{"yandexgpt-lite/rc"}).
#' @param yandex_base_url Base URL for Yandex Assistant API.
#' @param yandex_max_retries Maximum retry attempts for transient
#'   Yandex API failures (HTTP 429/5xx).
#' @param yandex_retry_base_sec Base delay in seconds for exponential backoff.
#' @param use_yandex_cache If \code{TRUE}, caches Yandex responses for repeated
#'   texts within the same R session.
#' @param compute_quality If \code{TRUE}, computes quality metrics and stores
#'   them in \code{attr(result, "topic_quality")}.
#' @param language  Stopword language passed to \code{tidytext::get_stopwords()}.
#'   Use \code{c("ru", "en")} for bilingual corpora (default).
#' @return The original data frame with additional columns:
#'   \code{topic} (integer), \code{topic_label} (character),
#'   \code{topic_prob} (numeric, LDA only).
#' @export
classify_news <- function(df,
                          n_topics      = 10L,
                          method        = c("lda", "kmeans", "llm", "yandex_llm"),
                          llm_api_key   = NULL,
                          llm_base_url  = "https://api.anthropic.com",
                          yandex_api_key = NULL,
                          yandex_folder_id = NULL,
                          yandex_model = Sys.getenv("YANDEX_CLOUD_MODEL", "yandexgpt-lite/rc"),
                          yandex_base_url = Sys.getenv("YANDEX_CLOUD_BASE_URL", "https://rest-assistant.api.cloud.yandex.net/v1"),
                          yandex_max_retries = 3L,
                          yandex_retry_base_sec = 1,
                          use_yandex_cache = TRUE,
                          compute_quality = FALSE,
                          language      = c("ru", "en")) {

  method <- match.arg(method)

  if (!"content_text" %in% names(df)) {
    cli::cli_abort("{.arg df} must contain a {.field content_text} column.")
  }

  cli::cli_inform("Classifying {nrow(df)} articles using method={.val {method}}…")

  result <- switch(method,
    lda    = .classify_lda(df, n_topics, language),
    kmeans = .classify_kmeans(df, n_topics, language),
    llm    = .classify_llm(df, llm_api_key, llm_base_url),
    yandex_llm = .classify_yandex_llm(
      df,
      api_key = yandex_api_key,
      folder_id = yandex_folder_id,
      model = yandex_model,
      base_url = yandex_base_url,
      max_retries = yandex_max_retries,
      retry_base_sec = yandex_retry_base_sec,
      use_cache = use_yandex_cache
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
    dplyr::summarise(topic_label = paste(term, collapse = ", "),
                     .groups = "drop")

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
    topic_label = paste0("Кластер ", km$cluster),
    stringsAsFactors = FALSE
  )

  df$doc_id <- as.character(df$article_id)
  df <- dplyr::left_join(df, cluster_df, by = "doc_id")
  df$doc_id <- NULL
  df
}

# ── LLM ──────────────────────────────────────────────────────────────────────

.classify_llm <- function(df, api_key, base_url) {
  if (is.null(api_key) || !nzchar(api_key)) {
    cli::cli_abort("Provide {.arg llm_api_key} for method='llm'.")
  }

  endpoint <- paste0(sub("/+$", "", base_url), "/v1/messages")

  labels <- vapply(seq_len(nrow(df)), function(i) {
    text <- substr(
      paste(df$title[i] %||% "", df$content_text[i] %||% ""),
      1L, 800L
    )

    body <- list(
      model      = "claude-haiku-4-5-20251001",
      max_tokens = 60L,
      messages   = list(list(
        role    = "user",
        content = paste0(
          "Определи тематическую категорию для следующей новости. ",
          "Ответь ТОЛЬКО названием категории (1-3 слова) на русском языке.\n\n",
          "Новость: ", text
        )
      ))
    )

    resp <- httr2::request(endpoint) |>
      httr2::req_headers(
        "x-api-key"         = api_key,
        "anthropic-version" = "2023-06-01",
        "content-type"      = "application/json"
      ) |>
      httr2::req_body_json(body) |>
      httr2::req_error(is_error = \(r) FALSE) |>
      httr2::req_perform()

    if (httr2::resp_is_error(resp)) return("Без категории")

    parsed <- httr2::resp_body_json(resp)
    trimws(parsed$content[[1L]]$text %||% "Без категории")
  }, character(1L))

  df$topic_label <- labels
  df$topic       <- as.integer(factor(labels))
  df
}

# ── Yandex LLM ────────────────────────────────────────────────────────────────

.yandex_cache <- new.env(parent = emptyenv())

.classify_yandex_llm <- function(df, api_key, folder_id, model, base_url,
                                 max_retries = 3L,
                                 retry_base_sec = 1,
                                 use_cache = TRUE) {
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

  labels <- vapply(seq_len(nrow(df)), function(i) {
    text <- substr(
      paste(df$title[i] %||% "", df$content_text[i] %||% ""),
      1L, 1200L
    )

    body <- list(
      model = model_uri,
      temperature = 0.3,
      instructions = paste0(
        "Определи тематическую категорию для следующей новости. ",
        "Ответь только названием категории (1-3 слова) на русском языке."
      ),
      input = text,
      max_output_tokens = 60L
    )

    cache_key <- .yandex_cache_key(model_uri, text)
    if (isTRUE(use_cache) && exists(cache_key, envir = .yandex_cache, inherits = FALSE)) {
      return(get(cache_key, envir = .yandex_cache, inherits = FALSE))
    }

    req <- httr2::request(endpoint) |>
      httr2::req_headers(
        "Authorization" = paste("Bearer", api_key),
        "Content-Type" = "application/json"
      ) |>
      httr2::req_body_json(body) |>
      httr2::req_error(is_error = \(r) FALSE)

    label <- "Без категории"
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
      label <- trimws(txt %||% "Без категории")
      break
    }

    if (isTRUE(use_cache)) {
      assign(cache_key, label, envir = .yandex_cache)
    }
    label
  }, character(1L))

  df$topic_label <- labels
  df$topic       <- as.integer(factor(labels))
  df
}

.yandex_cache_key <- function(model_uri, text) {
  txt <- text %||% ""
  head_part <- substring(txt, 1L, min(200L, nchar(txt)))
  tail_part <- substring(txt, max(1L, nchar(txt) - 199L), nchar(txt))
  paste(model_uri, nchar(txt), head_part, tail_part, sep = "||")
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
