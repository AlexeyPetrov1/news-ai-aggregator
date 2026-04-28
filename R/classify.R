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
      base_url = yandex_base_url
    )
  )

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

.classify_yandex_llm <- function(df, api_key, folder_id, model, base_url) {
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

    req <- httr2::request(endpoint) |>
      httr2::req_headers(
        "Authorization" = paste("Bearer", api_key),
        "Content-Type" = "application/json"
      ) |>
      httr2::req_body_json(body) |>
      httr2::req_error(is_error = \(r) FALSE)

    resp <- tryCatch(httr2::req_perform(req), error = function(e) NULL)
    if (is.null(resp) || httr2::resp_is_error(resp)) return("Без категории")

    parsed <- httr2::resp_body_json(resp, simplifyVector = FALSE)
    txt <- .extract_response_output_text(parsed)
    trimws(txt %||% "Без категории")
  }, character(1L))

  df$topic_label <- labels
  df$topic       <- as.integer(factor(labels))
  df
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
