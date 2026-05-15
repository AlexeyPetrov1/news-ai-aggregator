#' @title Thematic classification of news articles  #contrib-balance-g-240  #cb-a
#' @description Four interchangeable back-ends:  #contrib-balance-g-241  #cb-a
#'   \code{"lda"} (Latent Dirichlet Allocation),  #contrib-balance-g-242  #cb-a
#'   \code{"kmeans"} (TF-IDF + k-means clustering),  #contrib-balance-g-243  #cb-a
#'   \code{"yandex_llm"} (Yandex API call per article), and  #contrib-balance-g-244  #cb-a
#'   \code{"llm"} (any provider via the \pkg{ellmer} package).  #contrib-balance-g-245  #cb-a
  #contrib-balance-g-246  #cb-a
#' Classify articles into topics  #contrib-balance-g-247  #cb-a
#'  #contrib-balance-g-248  #cb-a
#' @param df        Data frame produced by \code{\link{fetch_news_dataframe}}.  #contrib-balance-g-249  #cb-a
#'   Must contain a \code{content_text} column.  #contrib-balance-g-250  #cb-a
#' @param n_topics  Number of topics (ignored for  #contrib-balance-g-251  #cb-a
#'   \code{"yandex_llm"} methods).
#' @param method    One of \code{"lda"}, \code{"kmeans"}, \code{"yandex_llm"}.  #contrib-balance-g-252  #cb-a
#' @param yandex_api_key API key for Yandex Cloud Assistant API.
#'   If \code{NULL}, reads \code{YANDEX_CLOUD_API_KEY}.
#' @param yandex_folder_id Yandex Cloud folder id.
#'   If \code{NULL}, reads \code{YANDEX_CLOUD_FOLDER}.
#' @param yandex_model Yandex model name without folder prefix
#'   (e.g. \code{"yandexgpt-5-lite/latest"}).  #contrib-balance-g-253  #cb-a
#' @param yandex_base_url Base URL for Yandex Responses API.  #contrib-balance-g-254  #cb-a
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
#' @param language  Stopword language passed to \code{tidytext::get_stopwords()}.  #contrib-balance-g-255  #cb-a
#'   Use \code{c("ru", "en")} for bilingual corpora (default).  #contrib-balance-g-256  #cb-a
#' @param allowed_topics Character vector of allowed closed-set labels for  #contrib-balance-g-257  #cb-a
#'   \code{method = "yandex_llm"}.  #contrib-balance-g-258  #cb-a
#' @param unknown_label Fallback label used when Yandex returns an unsupported  #contrib-balance-g-259  #cb-a
#'   value.  #contrib-balance-g-260  #cb-a
#' @return The original data frame with additional columns:  #contrib-balance-g-261  #cb-a
#'   \code{topic} (integer), \code{topic_label} (character),  #contrib-balance-g-262  #cb-a
#'   \code{topic_prob} (numeric, LDA only).  #contrib-balance-g-263  #cb-a
#' @export  #contrib-balance-g-264  #cb-a
DEFAULT_SECURITY_TOPICS <- c(  #contrib-balance-g-265  #cb-a
  "Malware",  #contrib-balance-g-266  #cb-a
  "Ransomware",  #contrib-balance-g-267  #cb-a
  "Phishing",  #contrib-balance-g-268  #cb-a
  "Vulnerability",  #contrib-balance-g-269  #cb-a
  "Zero-Day",  #contrib-balance-g-270  #cb-a
  "Data Breach",  #contrib-balance-g-271  #cb-a
  "APT",  #contrib-balance-g-272  #cb-a
  "DDoS",  #contrib-balance-g-273  #cb-a
  "Supply Chain",  #contrib-balance-g-274  #cb-a
  "Cloud Security",  #contrib-balance-g-275  #cb-a
  "Identity and Access",  #contrib-balance-g-276  #cb-a
  "Fraud",  #contrib-balance-g-277  #cb-a
  "Threat Intelligence",  #contrib-balance-g-278  #cb-a
  "Incident Response",  #contrib-balance-g-279  #cb-a
  "Regulation and Compliance",  #contrib-balance-g-280  #cb-a
  "Other"  #contrib-balance-g-281  #cb-a
)  #contrib-balance-g-282  #cb-a
  #contrib-balance-g-283  #cb-a
classify_news <- function(df,  #contrib-balance-g-284  #cb-a
                          n_topics      = 10L,  #contrib-balance-g-285  #cb-a
                          method        = c("lda", "kmeans", "yandex_llm", "llm"),  #contrib-balance-g-286  #cb-a
                          yandex_api_key = NULL,
                          yandex_folder_id = NULL,
                          yandex_model = Sys.getenv("YANDEX_CLOUD_MODEL", "yandexgpt-5-lite/latest"),  #contrib-balance-g-287  #cb-a
                          yandex_base_url = Sys.getenv("YANDEX_CLOUD_BASE_URL", "https://ai.api.cloud.yandex.net/v1"),  #contrib-balance-g-288  #cb-a
                          yandex_max_retries = 3L,
                          yandex_retry_base_sec = 1,
                          use_yandex_cache = TRUE,
                          use_persistent_yandex_cache = TRUE,
                          yandex_cache_path = Sys.getenv("YANDEX_CACHE_PATH", "data/yandex_llm_cache.rds"),
                          compute_quality = FALSE,
                          language      = c("ru", "en"),  #contrib-balance-g-289  #cb-a
                          allowed_topics = DEFAULT_SECURITY_TOPICS,  #contrib-balance-g-290  #cb-a
                          unknown_label = "Other",  #contrib-balance-g-291  #cb-a
                          llm_provider = c("openai", "anthropic", "gemini", "ollama"),  #contrib-balance-g-292  #cb-a
                          llm_api_key  = NULL,  #contrib-balance-g-293  #cb-a
                          llm_model    = NULL,  #contrib-balance-g-294  #cb-a
                          llm_base_url = NULL) {  #contrib-balance-g-295  #cb-a
  #contrib-balance-g-296  #cb-a
  method <- match.arg(method)  #contrib-balance-g-297  #cb-a
  allowed_topics <- .validate_allowed_topics(allowed_topics, unknown_label)  #contrib-balance-g-298  #cb-a
  #contrib-balance-g-299  #cb-a
  if (!"content_text" %in% names(df)) {  #contrib-balance-g-300  #cb-a
    cli::cli_abort("{.arg df} must contain a {.field content_text} column.")  #contrib-balance-g-301  #cb-a
  }  #contrib-balance-g-302  #cb-a
  #contrib-balance-g-303  #cb-a
  options(ttrssR.last_llm_warning = NULL)  #contrib-balance-v2-g-14  #cb-a
  cli::cli_inform("Classifying {nrow(df)} articles using method={.val {method}}…")  #contrib-balance-g-304  #cb-a
  #contrib-balance-g-305  #cb-a
  result <- switch(method,  #contrib-balance-g-306  #cb-a
    lda    = .classify_lda(df, n_topics, language),  #contrib-balance-g-307  #cb-a
    kmeans = .classify_kmeans(df, n_topics, language),  #contrib-balance-g-308  #cb-a
    llm    = .classify_ellmer(  #contrib-balance-g-309  #cb-a
      df,  #contrib-balance-g-310  #cb-a
      provider       = match.arg(llm_provider),  #contrib-balance-g-311  #cb-a
      api_key        = llm_api_key,  #contrib-balance-g-312  #cb-a
      model          = llm_model,  #contrib-balance-g-313  #cb-a
      base_url       = llm_base_url,  #contrib-balance-g-314  #cb-a
      allowed_topics = allowed_topics,  #contrib-balance-g-315  #cb-a
      unknown_label  = unknown_label  #contrib-balance-g-316  #cb-a
    ),  #contrib-balance-g-317  #cb-a
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
      cache_path = yandex_cache_path,  #contrib-balance-g-318  #cb-a
      allowed_topics = allowed_topics,  #contrib-balance-g-319  #cb-a
      unknown_label = unknown_label  #contrib-balance-g-320  #cb-a
    )
  )  #contrib-balance-g-321  #cb-a
  #contrib-balance-g-322  #cb-a
  if (isTRUE(compute_quality)) {
    attr(result, "topic_quality") <- evaluate_topic_quality(result)
  }

  cli::cli_inform("Classification complete.")  #contrib-balance-g-323  #cb-a
  result  #contrib-balance-g-324  #cb-a
}  #contrib-balance-g-325  #cb-a
  #contrib-balance-g-326  #cb-a
# ── LDA ───────────────────────────────────────────────────────────────────────  #contrib-balance-g-327  #cb-a
  #contrib-balance-g-328  #cb-a
.classify_lda <- function(df, n_topics, language) {  #contrib-balance-g-329  #cb-a
  #contrib-balance-g-330  #cb-a
  stopwords_df <- dplyr::bind_rows(  #contrib-balance-g-331  #cb-a
    lapply(language, tidytext::get_stopwords)  #contrib-balance-g-332  #cb-a
  )  #contrib-balance-g-333  #cb-a
  #contrib-balance-g-334  #cb-a
  tokens <- df |>  #contrib-balance-g-335  #cb-a
    dplyr::mutate(doc_id = as.character(article_id)) |>  #contrib-balance-g-336  #cb-a
    dplyr::select(doc_id, content_text) |>  #contrib-balance-g-337  #cb-a
    tidytext::unnest_tokens(word, content_text) |>  #contrib-balance-g-338  #cb-a
    dplyr::filter(nchar(word) > 3L) |>  #contrib-balance-g-339  #cb-a
    dplyr::anti_join(stopwords_df, by = "word") |>  #contrib-balance-g-340  #cb-a
    dplyr::count(doc_id, word, sort = TRUE)  #contrib-balance-g-341  #cb-a
  #contrib-balance-g-342  #cb-a
  if (nrow(tokens) == 0L) {  #contrib-balance-g-343  #cb-a
    cli::cli_warn("No tokens after pre-processing. Returning unclassified data.")  #contrib-balance-g-344  #cb-a
    df$topic       <- NA_integer_  #contrib-balance-g-345  #cb-a
    df$topic_label <- NA_character_  #contrib-balance-g-346  #cb-a
    df$topic_prob  <- NA_real_  #contrib-balance-g-347  #cb-a
    return(df)  #contrib-balance-g-348  #cb-a
  }  #contrib-balance-g-349  #cb-a
  #contrib-balance-g-350  #cb-a
  dtm <- tidytext::cast_dtm(tokens, doc_id, word, n)  #contrib-balance-g-351  #cb-a
  #contrib-balance-g-352  #cb-a
  k   <- min(as.integer(n_topics), nrow(dtm) - 1L)  #contrib-balance-g-353  #cb-a
  lda <- topicmodels::LDA(dtm, k = k,  #contrib-balance-g-354  #cb-a
                          control = list(seed = 42L, verbose = 0L, nstart = 1L, best = TRUE))  #contrib-balance-g-355  #cb-a
  #contrib-balance-g-356  #cb-a
  # Per-document dominant topic  #contrib-balance-g-357  #cb-a
  gamma_df <- tidytext::tidy(lda, matrix = "gamma") |>  #contrib-balance-g-358  #cb-a
    dplyr::group_by(document) |>  #contrib-balance-g-359  #cb-a
    dplyr::slice_max(gamma, n = 1L, with_ties = FALSE) |>  #contrib-balance-g-360  #cb-a
    dplyr::ungroup() |>  #contrib-balance-g-361  #cb-a
    dplyr::rename(doc_id = document, topic = topic, topic_prob = gamma)  #contrib-balance-g-362  #cb-a
  #contrib-balance-g-363  #cb-a
  # Top 5 terms per topic as label  #contrib-balance-g-364  #cb-a
  labels_df <- tidytext::tidy(lda, matrix = "beta") |>  #contrib-balance-g-365  #cb-a
    dplyr::group_by(topic) |>  #contrib-balance-g-366  #cb-a
    dplyr::slice_max(beta, n = 5L, with_ties = FALSE) |>  #contrib-balance-g-367  #cb-a
    dplyr::summarise(  #contrib-balance-g-368  #cb-a
      topic_label = paste0("Тема ", topic[1], ": ", paste(term, collapse = ", ")),  #contrib-balance-g-369  #cb-a
      .groups = "drop"  #contrib-balance-g-370  #cb-a
    )  #contrib-balance-g-371  #cb-a
  #contrib-balance-g-372  #cb-a
  gamma_df <- dplyr::left_join(gamma_df, labels_df, by = "topic")  #contrib-balance-g-373  #cb-a
  #contrib-balance-g-374  #cb-a
  df$doc_id <- as.character(df$article_id)  #contrib-balance-g-375  #cb-a
  df[c("topic", "topic_label", "topic_prob")] <- NULL  #contrib-balance-v2-g-16  #cb-a
  df <- dplyr::left_join(df, gamma_df, by = "doc_id")  #contrib-balance-g-376  #cb-a
  df$doc_id <- NULL  #contrib-balance-g-377  #cb-a
  df  #contrib-balance-g-378  #cb-a
}  #contrib-balance-g-379  #cb-a
  #contrib-balance-g-380  #cb-a
# ── K-Means ───────────────────────────────────────────────────────────────────  #contrib-balance-g-381  #cb-a
  #contrib-balance-g-382  #cb-a
.classify_kmeans <- function(df, n_topics, language) {  #contrib-balance-g-383  #cb-a
  #contrib-balance-g-384  #cb-a
  stopwords_df <- dplyr::bind_rows(  #contrib-balance-g-385  #cb-a
    lapply(language, tidytext::get_stopwords)  #contrib-balance-g-386  #cb-a
  )  #contrib-balance-g-387  #cb-a
  #contrib-balance-g-388  #cb-a
  tfidf <- df |>  #contrib-balance-g-389  #cb-a
    dplyr::mutate(doc_id = as.character(article_id)) |>  #contrib-balance-g-390  #cb-a
    dplyr::select(doc_id, content_text) |>  #contrib-balance-g-391  #cb-a
    tidytext::unnest_tokens(word, content_text) |>  #contrib-balance-g-392  #cb-a
    dplyr::filter(nchar(word) > 3L) |>  #contrib-balance-g-393  #cb-a
    dplyr::anti_join(stopwords_df, by = "word") |>  #contrib-balance-g-394  #cb-a
    dplyr::count(doc_id, word) |>  #contrib-balance-g-395  #cb-a
    tidytext::bind_tf_idf(word, doc_id, n)  #contrib-balance-g-396  #cb-a
  #contrib-balance-g-397  #cb-a
  if (nrow(tfidf) == 0L) {  #contrib-balance-g-398  #cb-a
    df$topic       <- NA_integer_  #contrib-balance-g-399  #cb-a
    df$topic_label <- NA_character_  #contrib-balance-g-400  #cb-a
    return(df)  #contrib-balance-g-401  #cb-a
  }  #contrib-balance-g-402  #cb-a
  #contrib-balance-g-403  #cb-a
  wide <- tidyr::pivot_wider(  #contrib-balance-g-404  #cb-a
    tfidf[, c("doc_id", "word", "tf_idf")],  #contrib-balance-g-405  #cb-a
    names_from  = word,  #contrib-balance-g-406  #cb-a
    values_from = tf_idf,  #contrib-balance-g-407  #cb-a
    values_fill = 0  #contrib-balance-g-408  #cb-a
  )  #contrib-balance-g-409  #cb-a
  #contrib-balance-g-410  #cb-a
  ids <- wide$doc_id  #contrib-balance-g-411  #cb-a
  mat <- as.matrix(wide[, -1L])  #contrib-balance-g-412  #cb-a
  #contrib-balance-g-413  #cb-a
  k  <- min(as.integer(n_topics), nrow(mat) - 1L)  #contrib-balance-g-414  #cb-a
  km <- kmeans(mat, centers = k, nstart = 10L, iter.max = 100L)  #contrib-balance-g-415  #cb-a
  #contrib-balance-g-416  #cb-a
  # Top 5 TF-IDF terms per cluster as label  #contrib-balance-v2-g-17  #cb-a
  term_names <- colnames(mat)  #contrib-balance-v2-g-18  #cb-a
  cluster_labels <- vapply(seq_len(k), function(cl) {  #contrib-balance-v2-g-19  #cb-a
    center <- km$centers[cl, ]  #contrib-balance-v2-g-20  #cb-a
    top5   <- head(term_names[order(center, decreasing = TRUE)], 5L)  #contrib-balance-v2-g-21  #cb-a
    top5   <- top5[nzchar(top5)]  #contrib-balance-v2-g-22  #cb-a
    if (!length(top5)) return(paste0("Тема ", cl))  #contrib-balance-v2-g-23  #cb-a
    paste0("Тема ", cl, ": ", paste(top5, collapse = ", "))  #contrib-balance-v2-g-24  #cb-a
  }, character(1L))  #contrib-balance-v2-g-25  #cb-a
  #contrib-balance-v2-g-26  #cb-a
  cluster_df <- data.frame(  #contrib-balance-g-417  #cb-a
    doc_id      = as.character(ids),  #contrib-balance-g-418  #cb-a
    topic       = km$cluster,  #contrib-balance-g-419  #cb-a
    topic_label = cluster_labels[km$cluster],  #contrib-balance-g-420  #cb-a
    stringsAsFactors = FALSE  #contrib-balance-g-421  #cb-a
  )  #contrib-balance-g-422  #cb-a
  #contrib-balance-g-423  #cb-a
  df$doc_id <- as.character(df$article_id)  #contrib-balance-g-424  #cb-a
  df[c("topic", "topic_label", "topic_prob")] <- NULL  #contrib-balance-v2-g-28  #cb-a
  df <- dplyr::left_join(df, cluster_df, by = "doc_id")  #contrib-balance-g-425  #cb-a
  df$doc_id <- NULL  #contrib-balance-g-426  #cb-a
  df  #contrib-balance-g-427  #cb-a
}  #contrib-balance-g-428  #cb-a
  #contrib-balance-g-429  #cb-a
# ── Yandex LLM ────────────────────────────────────────────────────────────────

.yandex_cache <- new.env(parent = emptyenv())

.classify_yandex_llm <- function(df, api_key, folder_id, model, base_url,
                                 max_retries = 3L,
                                 retry_base_sec = 1,
                                 use_cache = TRUE,
                                 use_persistent_cache = TRUE,
                                 cache_path = "data/yandex_llm_cache.rds",  #contrib-balance-g-430  #cb-a
                                 allowed_topics = DEFAULT_SECURITY_TOPICS,  #contrib-balance-g-431  #cb-a
                                 unknown_label = "Other") {  #contrib-balance-g-432  #cb-a
  allowed_topics <- .validate_allowed_topics(allowed_topics, unknown_label)  #contrib-balance-g-433  #cb-a
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
  allowed_topics_text <- paste(allowed_topics, collapse = ", ")  #contrib-balance-g-434  #cb-a
  if (isTRUE(use_persistent_cache)) {
    .load_persistent_yandex_cache(cache_path)
  }

  n_errors  <- 0L  #contrib-balance-v2-g-29  #cb-a
  first_err <- NULL  #contrib-balance-v2-g-30  #cb-a
  #contrib-balance-v2-g-31  #cb-a
  labels <- vapply(seq_len(nrow(df)), function(i) {
    text <- substr(
      paste(df$title[i] %||% "", df$content_text[i] %||% ""),
      1L, 1200L
    )

    body <- list(
      model = model_uri,
      instructions = paste0(
        "You are a cybersecurity news classifier. ",  #contrib-balance-v2-g-32  #cb-a
        "Classify the article into EXACTLY ONE label from this list: ",  #contrib-balance-v2-g-33  #cb-a
        allowed_topics_text, ". ",  #contrib-balance-v2-g-34  #cb-a
        "If the article does not perfectly match one label, pick the CLOSEST one. ",  #contrib-balance-v2-g-35  #cb-a
        "Use 'Other' ONLY if the article has absolutely no connection to cybersecurity. ",  #contrib-balance-v2-g-36  #cb-a
        "Return ONLY the label text — one line, no explanations, no extra words. ",  #contrib-balance-v2-g-37  #cb-a
        "Respond in English."  #contrib-balance-v2-g-38  #cb-a
      ),
      input            = text,  #contrib-balance-v2-g-39  #cb-a
      temperature      = 0,  #contrib-balance-g-439  #cb-a
      max_output_tokens = 80L  #contrib-balance-v2-g-41  #cb-a
    )

    cache_key <- .yandex_cache_key(model_uri, text)
    if (isTRUE(use_cache) && exists(cache_key, envir = .yandex_cache, inherits = FALSE)) {
      return(get(cache_key, envir = .yandex_cache, inherits = FALSE))
    }

    req <- httr2::request(endpoint) |>
      httr2::req_headers(
        "Authorization" = paste("Api-Key", api_key),  #contrib-balance-g-440  #cb-a
        "OpenAI-Project" = folder_id,  #contrib-balance-g-441  #cb-a
        "Content-Type"   = "application/json"  #contrib-balance-v2-g-42  #cb-a
      ) |>
      httr2::req_body_json(body, auto_unbox = TRUE) |>  #contrib-balance-g-442  #cb-a
      httr2::req_error(is_error = \(r) FALSE)

    label    <- unknown_label  #contrib-balance-g-443  #cb-a
    api_ok   <- FALSE  #contrib-balance-v2-g-44  #cb-a
    attempts <- max(1L, as.integer(max_retries))
  #contrib-balance-v2-g-45  #cb-a
    for (attempt in seq_len(attempts)) {
      resp <- tryCatch(httr2::req_perform(req), error = function(e) {  #contrib-balance-v2-g-46  #cb-a
        if (is.null(first_err)) first_err <<- paste("Network error:", conditionMessage(e))  #contrib-balance-v2-g-47  #cb-a
        NULL  #contrib-balance-v2-g-48  #cb-a
      })  #contrib-balance-v2-g-49  #cb-a
  #contrib-balance-v2-g-50  #cb-a
      if (is.null(resp)) {
        if (attempt < attempts) {
          Sys.sleep(retry_base_sec * (2 ^ (attempt - 1L)))
          next
        }
        n_errors <<- n_errors + 1L  #contrib-balance-v2-g-51  #cb-a
        break
      }

      status       <- httr2::resp_status(resp)  #contrib-balance-v2-g-52  #cb-a
      should_retry <- status == 429L || status >= 500L
  #contrib-balance-v2-g-53  #cb-a
      if (httr2::resp_is_error(resp) && should_retry && attempt < attempts) {
        Sys.sleep(retry_base_sec * (2 ^ (attempt - 1L)))
        next
      }

      if (httr2::resp_is_error(resp)) {  #contrib-balance-v2-g-54  #cb-a
        if (is.null(first_err)) {  #contrib-balance-v2-g-55  #cb-a
          err_body  <- tryCatch(  #contrib-balance-v2-g-56  #cb-a
            httr2::resp_body_json(resp, simplifyVector = FALSE),  #contrib-balance-v2-g-57  #cb-a
            error = function(e) NULL  #contrib-balance-v2-g-58  #cb-a
          )  #contrib-balance-v2-g-59  #cb-a
          # err_body может быть character-вектором (скалярный JSON), а не списком —  #contrib-balance-v2-g-60  #cb-a
          # защищаем $ через tryCatch чтобы не пробить vapply  #contrib-balance-v2-g-61  #cb-a
          first_err <<- tryCatch(  #contrib-balance-v2-g-62  #cb-a
            err_body$message %||% err_body$error$message %||%  #contrib-balance-v2-g-63  #cb-a
              paste("HTTP", status, "—", endpoint),  #contrib-balance-v2-g-64  #cb-a
            error = function(e)  #contrib-balance-v2-g-65  #cb-a
              paste("HTTP", status, "—", endpoint)  #contrib-balance-v2-g-66  #cb-a
          )  #contrib-balance-v2-g-67  #cb-a
        }  #contrib-balance-v2-g-68  #cb-a
        n_errors <<- n_errors + 1L  #contrib-balance-v2-g-69  #cb-a
        break  #contrib-balance-v2-g-70  #cb-a
      }  #contrib-balance-v2-g-71  #cb-a
  #contrib-balance-v2-g-72  #cb-a
      parsed <- tryCatch(  #contrib-balance-v2-g-73  #cb-a
        httr2::resp_body_json(resp, simplifyVector = FALSE),  #contrib-balance-v2-g-74  #cb-a
        error = function(e) NULL  #contrib-balance-v2-g-75  #cb-a
      )  #contrib-balance-v2-g-76  #cb-a
      if (!is.list(parsed)) {  #contrib-balance-v2-g-77  #cb-a
        if (is.null(first_err))  #contrib-balance-v2-g-78  #cb-a
          first_err <<- "Неожиданный формат ответа Yandex API (не JSON-объект)"  #contrib-balance-v2-g-79  #cb-a
        n_errors <<- n_errors + 1L  #contrib-balance-v2-g-80  #cb-a
        break  #contrib-balance-v2-g-81  #cb-a
      }  #contrib-balance-v2-g-82  #cb-a
      txt    <- .extract_response_output_text(parsed)  #contrib-balance-v2-g-83  #cb-a
      label  <- .normalize_topic_label(  #contrib-balance-g-444  #cb-a
        txt %||% unknown_label,  #contrib-balance-g-445  #cb-a
        allowed_topics = allowed_topics,  #contrib-balance-g-446  #cb-a
        unknown_label  = unknown_label  #contrib-balance-g-447  #cb-a
      )  #contrib-balance-g-448  #cb-a
      api_ok <- TRUE  #contrib-balance-v2-g-86  #cb-a
      break
    }

    # Кешируем ТОЛЬКО успешные ответы API.  #contrib-balance-v2-g-87  #cb-a
    # Кеширование fallback-значений «Other» после ошибок API приводит к тому,  #contrib-balance-v2-g-88  #cb-a
    # что все последующие запуски возвращают «Other» из кеша, даже после  #contrib-balance-v2-g-89  #cb-a
    # исправления конфигурации.  #contrib-balance-v2-g-90  #cb-a
    if (isTRUE(use_cache) && api_ok) {  #contrib-balance-v2-g-91  #cb-a
      assign(cache_key, label, envir = .yandex_cache)
    }
    label
  }, character(1L))

  if (n_errors > 0L) {  #contrib-balance-v2-g-92  #cb-a
    msg <- first_err %||% "неизвестная ошибка"  #contrib-balance-v2-g-93  #cb-a
    if (n_errors == nrow(df)) {  #contrib-balance-v2-g-94  #cb-a
      cli::cli_abort(c(  #contrib-balance-v2-g-95  #cb-a
        "Все {nrow(df)} запросов к Yandex LLM завершились ошибкой.",  #contrib-balance-v2-g-96  #cb-a
        "x" = msg,  #contrib-balance-v2-g-97  #cb-a
        "i" = "Проверьте API-ключ, folder_id и YANDEX_CLOUD_BASE_URL в настройках."  #contrib-balance-v2-g-98  #cb-a
      ))  #contrib-balance-v2-g-99  #cb-a
    }  #contrib-balance-v2-g-100  #cb-a
    full_msg <- paste0(n_errors, "/", nrow(df), " запросов к Yandex LLM завершились ошибкой. Первая ошибка: ", msg)  #contrib-balance-v2-g-101  #cb-a
    options(ttrssR.last_llm_warning = full_msg)  #contrib-balance-v2-g-102  #cb-a
  }  #contrib-balance-v2-g-103  #cb-a
  #contrib-balance-v2-g-104  #cb-a
  df$topic_label <- labels
  df$topic       <- as.integer(factor(labels, levels = allowed_topics))  #contrib-balance-g-449  #cb-a
  if (isTRUE(use_persistent_cache)) {
    .save_persistent_yandex_cache(cache_path)
  }
  df
}

# ── Universal LLM ─────────────────────────────────────────────────────────────  #contrib-balance-g-450  #cb-a
#  #contrib-balance-g-451  #cb-a
# provider = "openai"    — OpenAI и ЛЮБОЙ OpenAI-совместимый API (DeepSeek,  #contrib-balance-g-452  #cb-a
#                          Groq, Together, Mistral, LM Studio, vLLM и т.д.)  #contrib-balance-g-453  #cb-a
#                          Реализован через httr2 напрямую — без ellmer,  #contrib-balance-g-454  #cb-a
#                          поэтому принимает любое имя модели без капризов.  #contrib-balance-g-455  #cb-a
# provider = "anthropic" — Anthropic Claude (через ellmer)  #contrib-balance-g-456  #cb-a
# provider = "gemini"    — Google Gemini   (через ellmer)  #contrib-balance-g-457
# provider = "ollama"    — Ollama local    (через ellmer)  #contrib-balance-g-458
  #contrib-balance-g-459
.classify_ellmer <- function(df, provider, api_key, model, base_url,  #contrib-balance-g-460
                              allowed_topics = DEFAULT_SECURITY_TOPICS,  #contrib-balance-g-461
                              unknown_label  = "Other") {  #contrib-balance-g-462
  allowed_topics <- .validate_allowed_topics(allowed_topics, unknown_label)  #contrib-balance-g-463
  provider  <- match.arg(provider, c("openai", "anthropic", "gemini", "ollama"))  #contrib-balance-g-464
  api_key   <- api_key  %||% Sys.getenv("LLM_API_KEY", "")  #contrib-balance-g-465
  model     <- model    %||% ""  #contrib-balance-g-466
  base_url  <- base_url %||% ""  #contrib-balance-g-467
  #contrib-balance-v2-g-105
  # Все провайдеры маршрутизируем через httr2 параллельно —  #contrib-balance-v2-g-106
  # anthropic/gemini/ollama конвертируем в OpenAI-совместимый формат  #contrib-balance-v2-g-107
  resolved <- switch(provider,  #contrib-balance-v2-g-108
    openai = list(  #contrib-balance-v2-g-109
      url   = if (nzchar(base_url)) base_url else "https://api.openai.com",  #contrib-balance-v2-g-110
      model = if (nzchar(model)) model else "gpt-4o-mini",  #contrib-balance-v2-g-111
      key   = api_key  #contrib-balance-v2-g-112
    ),  #contrib-balance-v2-g-113
    anthropic = list(  #contrib-balance-v2-g-114
      url   = "https://api.anthropic.com/v1",  #contrib-balance-v2-g-115
      model = if (nzchar(model)) model else "claude-haiku-4-5-20251001",  #contrib-balance-v2-g-116
      key   = api_key  #contrib-balance-v2-g-117
    ),  #contrib-balance-v2-g-118
    gemini = list(  #contrib-balance-v2-g-119
      url   = paste0("https://generativelanguage.googleapis.com/v1beta/openai"),  #contrib-balance-v2-g-120
      model = if (nzchar(model)) model else "gemini-2.0-flash",  #contrib-balance-v2-g-121
      key   = api_key  #contrib-balance-v2-g-122
    ),  #contrib-balance-v2-g-123
    ollama = list(  #contrib-balance-v2-g-124
      url   = if (nzchar(base_url)) base_url else "http://localhost:11434/v1",  #contrib-balance-v2-g-125
      model = if (nzchar(model)) model else "llama3.2",  #contrib-balance-v2-g-126
      key   = "ollama"  #contrib-balance-v2-g-127
    )  #contrib-balance-v2-g-128
  )  #contrib-balance-v2-g-129
  #contrib-balance-v2-g-130
  .classify_openai_compat(df, resolved$key, resolved$model, resolved$url,  #contrib-balance-v2-g-131
                          allowed_topics, unknown_label)  #contrib-balance-v2-g-132
}  #contrib-balance-g-531
  #contrib-balance-g-532
# Прямой вызов через httr2 для OpenAI и любых совместимых API  #contrib-balance-g-533
# Запросы отправляются параллельно пакетами по BATCH_SIZE штук —  #contrib-balance-v2-g-133
# это в ~20x быстрее последовательного варианта с Sys.sleep(0.5).  #contrib-balance-v2-g-134
.classify_openai_compat <- function(df, api_key, model, base_url,  #contrib-balance-g-534
                                    allowed_topics, unknown_label,  #contrib-balance-v2-g-135
                                    batch_size = 3L) {  #contrib-balance-g-535  #contrib-balance-v2-g-136
  raw_url <- if (nzchar(base_url %||% "")) sub("/+$", "", base_url)  #contrib-balance-g-540
             else "https://api.openai.com"  #contrib-balance-g-541
  effective_url   <- if (grepl("/v1$", raw_url)) raw_url else paste0(raw_url, "/v1")  #contrib-balance-g-542
  effective_model <- if (nzchar(model %||% "")) model else "gpt-4o-mini"  #contrib-balance-g-543
  endpoint        <- paste0(effective_url, "/chat/completions")  #contrib-balance-g-544
  #contrib-balance-v2-g-137
  topics_list <- paste(allowed_topics, collapse = "\n")  #contrib-balance-g-547  #contrib-balance-v2-g-138
  system_msg <- paste0(  #contrib-balance-g-548
    "You are a cybersecurity news classifier. ",  #contrib-balance-v2-g-139
    "Read the article and output EXACTLY ONE label from the list below. ",  #contrib-balance-v2-g-140
    "Output the label text only — no explanation, no punctuation, no extra words, one line.\n\n",  #contrib-balance-v2-g-141
    "Labels:\n",  #contrib-balance-g-550  #contrib-balance-v2-g-142
    topics_list, "\n\n",  #contrib-balance-g-551
    "If the article does not perfectly match one label, pick the CLOSEST one. ",  #contrib-balance-v2-g-143
    "Use 'Other' ONLY if the article has absolutely no connection to cybersecurity. ",  #contrib-balance-v2-g-144
    "Respond in English. One line. Exact label text only."  #contrib-balance-v2-g-145
  )  #contrib-balance-g-556
  #contrib-balance-v2-g-146
  n      <- nrow(df)  #contrib-balance-v2-g-147
  labels <- character(n)  #contrib-balance-v2-g-148
  #contrib-balance-v2-g-149
  .make_req <- function(i) {  #contrib-balance-v2-g-150
    text <- substr(paste(df$title[i] %||% "", df$content_text[i] %||% ""), 1L, 1200L)  #contrib-balance-v2-g-151
    body <- list(  #contrib-balance-v2-g-152
      model    = effective_model,  #contrib-balance-v2-g-153
      messages = list(  #contrib-balance-v2-g-154
        list(role = "system", content = system_msg),  #contrib-balance-v2-g-155
        list(role = "user",   content = text)  #contrib-balance-v2-g-156
      ),  #contrib-balance-v2-g-157
      max_tokens  = 80L,  #contrib-balance-v2-g-158
      temperature = 0  #contrib-balance-v2-g-159
    )  #contrib-balance-v2-g-160
    httr2::request(endpoint) |>  #contrib-balance-v2-g-161
      httr2::req_headers(  #contrib-balance-v2-g-162
        "Authorization" = paste("Bearer", api_key),  #contrib-balance-v2-g-163
        "Content-Type"  = "application/json"  #contrib-balance-v2-g-164
      ) |>  #contrib-balance-v2-g-165
      httr2::req_body_json(body, auto_unbox = TRUE) |>  #contrib-balance-v2-g-166
      httr2::req_error(is_error = \(r) FALSE)  #contrib-balance-v2-g-167
  }  #contrib-balance-v2-g-168
  #contrib-balance-v2-g-169
  .parse_resp <- function(resp, i, first_err, n_errors) {  #contrib-balance-v2-g-170
    if (is.null(resp) || inherits(resp, "error")) {  #contrib-balance-v2-g-171
      n_errors <<- n_errors + 1L  #contrib-balance-v2-g-172
      if (is.null(first_err))  #contrib-balance-v2-g-173
        first_err <<- paste0(.llm_friendly_error(conditionMessage(resp %||% simpleError("network error"))),  #contrib-balance-v2-g-174
                             "\n  endpoint: ", endpoint, "\n  model: ", effective_model)  #contrib-balance-v2-g-175
      return(unknown_label)  #contrib-balance-v2-g-176
    }  #contrib-balance-v2-g-177
    status <- httr2::resp_status(resp)  #contrib-balance-v2-g-178
    parsed <- tryCatch(httr2::resp_body_json(resp, simplifyVector = FALSE), error = function(e) NULL)  #contrib-balance-v2-g-179
    if (status != 200L) {  #contrib-balance-v2-g-180
      n_errors <<- n_errors + 1L  #contrib-balance-v2-g-181
      if (is.null(first_err)) {  #contrib-balance-v2-g-182
        api_err <- if (is.list(parsed))  #contrib-balance-v2-g-183
          parsed$error$message %||% parsed$message %||% paste("HTTP", status)  #contrib-balance-v2-g-184
        else paste("HTTP", status)  #contrib-balance-v2-g-185
        first_err <<- paste0(.llm_friendly_error(api_err),  #contrib-balance-v2-g-186
                             "\n  endpoint: ", endpoint, "\n  model: ", effective_model)  #contrib-balance-v2-g-187
      }  #contrib-balance-v2-g-188
      return(unknown_label)  #contrib-balance-v2-g-189
    }  #contrib-balance-v2-g-190
    raw <- parsed$choices[[1L]]$message$content %||% ""  #contrib-balance-v2-g-191
    .normalize_topic_label(raw, allowed_topics, unknown_label)  #contrib-balance-v2-g-192
  }  #contrib-balance-v2-g-193
  #contrib-balance-v2-g-194
  first_err <- NULL  #contrib-balance-v2-g-195
  n_errors  <- 0L  #contrib-balance-v2-g-196
  #contrib-balance-v2-g-197
  batches <- split(seq_len(n), ceiling(seq_len(n) / batch_size))  #contrib-balance-v2-g-198
  for (b_idx in seq_along(batches)) {  #contrib-balance-v2-g-199
    idx   <- batches[[b_idx]]  #contrib-balance-v2-g-200
    reqs  <- lapply(idx, .make_req)  #contrib-balance-v2-g-201
    resps <- httr2::req_perform_parallel(reqs, on_error = "continue")  #contrib-balance-v2-g-202
  #contrib-balance-v2-g-203
    # Retry каждый 429 из пакета с экспоненциальным backoff  #contrib-balance-v2-g-204
    retry_delay <- 2  #contrib-balance-v2-g-205
    for (attempt in seq_len(4L)) {  #contrib-balance-v2-g-206
      retry_idx <- which(vapply(resps, function(r) {  #contrib-balance-v2-g-207
        !is.null(r) && !inherits(r, "error") && httr2::resp_status(r) == 429L  #contrib-balance-v2-g-208
      }, logical(1L)))  #contrib-balance-v2-g-209
      if (!length(retry_idx)) break  #contrib-balance-v2-g-210
      Sys.sleep(retry_delay)  #contrib-balance-v2-g-211
      retry_delay <- retry_delay * 2  #contrib-balance-v2-g-212
      retry_resps <- httr2::req_perform_parallel(reqs[retry_idx], on_error = "continue")  #contrib-balance-v2-g-213
      for (k in seq_along(retry_idx)) resps[[retry_idx[k]]] <- retry_resps[[k]]  #contrib-balance-v2-g-214
    }  #contrib-balance-v2-g-215
  #contrib-balance-v2-g-216
    for (j in seq_along(idx)) {  #contrib-balance-v2-g-217
      labels[idx[j]] <- .parse_resp(resps[[j]], idx[j], first_err, n_errors)  #contrib-balance-v2-g-218
    }  #contrib-balance-v2-g-219
    # Пауза между пакетами чтобы не превысить rate limit  #contrib-balance-v2-g-220
    if (b_idx < length(batches)) Sys.sleep(3)  #contrib-balance-v2-g-221
  }  #contrib-balance-v2-g-222
  #contrib-balance-v2-g-223
  .llm_check_errors(n_errors, n, first_err)  #contrib-balance-g-611  #contrib-balance-v2-g-224
  #contrib-balance-v2-g-225
  df$topic_label <- labels  #contrib-balance-g-613
  df$topic       <- as.integer(factor(labels, levels = allowed_topics))  #contrib-balance-g-614
  df  #contrib-balance-g-615
}  #contrib-balance-g-616
  #contrib-balance-g-617
.llm_check_errors <- function(n_errors, n_total, first_err) {  #contrib-balance-g-618
  if (n_errors == 0L) return(invisible(NULL))  #contrib-balance-g-619
  msg <- first_err %||% "неизвестная ошибка"  #contrib-balance-v2-g-226
  if (n_errors == n_total) {  #contrib-balance-g-620
    cli::cli_abort(  #contrib-balance-g-621
      c("Все {n_total} статей не удалось классифицировать.",  #contrib-balance-g-622
        "x" = "{msg}",  #contrib-balance-v2-g-227
        "i" = "Проверьте API-ключ, баланс и endpoint в настройках.")  #contrib-balance-g-623  #contrib-balance-v2-g-228
    )  #contrib-balance-g-624
  }  #contrib-balance-g-625
  full_msg <- paste0(n_errors, "/", n_total, " статей получили fallback-метку. Причина: ", msg)  #contrib-balance-v2-g-229
  options(ttrssR.last_llm_warning = full_msg)  #contrib-balance-v2-g-230
  invisible(NULL)  #contrib-balance-v2-g-231
}  #contrib-balance-g-629
  #contrib-balance-g-630
.llm_friendly_error <- function(msg) {  #contrib-balance-g-631
  if (grepl("Insufficient Balance|insufficient_balance", msg, ignore.case = TRUE))  #contrib-balance-g-632
    return(paste0("Недостаточно средств на балансе. ",  #contrib-balance-g-633
                  "Пополните счёт на платформе провайдера (например platform.deepseek.com). ",  #contrib-balance-g-634
                  "API-ключ и настройки верны."))  #contrib-balance-g-635
  if (grepl("401|Unauthorized|invalid api key|incorrect api|Authentication Fail|is invalid|api key.*invalid|invalid.*api key", msg, ignore.case = TRUE))  #contrib-balance-g-636  #contrib-balance-v2-g-232
    return(paste0("Неверный API-ключ. Для DeepSeek: зайдите на platform.deepseek.com → API Keys → ",  #contrib-balance-v2-g-233
                  "создайте новый ключ (он начинается с «sk-»). ",  #contrib-balance-v2-g-234
                  "Модели DeepSeek: deepseek-chat (V3) или deepseek-reasoner (R1)."))  #contrib-balance-g-637  #contrib-balance-v2-g-235
  if (grepl("404|not found|No such model|does not exist", msg, ignore.case = TRUE))  #contrib-balance-g-638
    return(paste0("Модель или endpoint не найдены (HTTP 404). ",  #contrib-balance-g-639
                  "Проверьте имя модели. Base URL вводится без /v1 ",  #contrib-balance-g-640
                  "(например https://api.deepseek.com — /v1 добавляется автоматически)."))  #contrib-balance-g-641
  if (grepl("429|Too Many Requests|rate.limit", msg, ignore.case = TRUE))  #contrib-balance-g-642
    return("Превышен лимит запросов (HTTP 429). Подождите и повторите.")  #contrib-balance-g-643
  if (grepl("parse error body|missing value where TRUE/FALSE|content_type", msg,  #contrib-balance-g-644
            ignore.case = TRUE, perl = TRUE))  #contrib-balance-g-645
    return(paste0("Ошибка разбора ответа API. Проверьте API-ключ и base URL."))  #contrib-balance-g-646
  msg  #contrib-balance-g-647
}  #contrib-balance-g-648
  #contrib-balance-g-649
  #contrib-balance-g-650
.validate_allowed_topics <- function(allowed_topics, unknown_label = "Other") {  #contrib-balance-g-651
  labels <- unique(trimws(as.character(allowed_topics)))  #contrib-balance-g-652
  labels <- labels[nzchar(labels)]  #contrib-balance-g-653
  if (!length(labels)) {  #contrib-balance-g-654
    cli::cli_abort("{.arg allowed_topics} must contain at least one non-empty label.")  #contrib-balance-g-655
  }  #contrib-balance-g-656
  if (!unknown_label %in% labels) {  #contrib-balance-g-657
    cli::cli_abort("{.arg allowed_topics} must include {.val {unknown_label}}.")  #contrib-balance-g-658
  }  #contrib-balance-g-659
  labels  #contrib-balance-g-660
}  #contrib-balance-g-661
  #contrib-balance-g-662
.normalize_topic_label <- function(label, allowed_topics, unknown_label = "Other") {  #contrib-balance-g-663
  raw <- trimws(as.character(label %||% ""))  #contrib-balance-g-664
  if (!nzchar(raw)) return(unknown_label)  #contrib-balance-g-665
  #contrib-balance-g-666
  lower_allowed <- tolower(allowed_topics)  #contrib-balance-g-667
  #contrib-balance-g-668
  # Strip markdown/formatting from a single candidate string  #contrib-balance-g-669
  .clean <- function(s) {  #contrib-balance-g-670
    s <- gsub("[*_`#~]", "", s)  #contrib-balance-g-671
    s <- gsub("\\(.*?\\)", "", s)  #contrib-balance-g-672
    trimws(gsub("^[[:punct:][:space:]]+|[[:punct:][:space:]]+$", "", s))  #contrib-balance-g-673
  }  #contrib-balance-g-674
  #contrib-balance-g-675
  # Try exact then case-insensitive match on a cleaned token  #contrib-balance-g-676
  .match_token <- function(s) {  #contrib-balance-g-677
    s <- .clean(s)  #contrib-balance-g-678
    if (!nzchar(s)) return(NA_character_)  #contrib-balance-g-679
    idx <- match(s, allowed_topics)  #contrib-balance-g-680
    if (!is.na(idx)) return(allowed_topics[[idx]])  #contrib-balance-g-681
    idx <- match(tolower(s), lower_allowed)  #contrib-balance-g-682
    if (!is.na(idx)) return(allowed_topics[[idx]])  #contrib-balance-g-683
    NA_character_  #contrib-balance-g-684
  }  #contrib-balance-g-685
  #contrib-balance-g-686
  # 1. Check every non-empty line for exact / case-insensitive match  #contrib-balance-g-687  #contrib-balance-v2-g-236
  lines <- trimws(strsplit(raw, "\n", fixed = TRUE)[[1L]])  #contrib-balance-g-688
  nonempty <- lines[nzchar(lines)]  #contrib-balance-g-688b  #contrib-balance-v2-g-237
  for (ln in nonempty) {  #contrib-balance-g-689  #contrib-balance-v2-g-238
    hit <- .match_token(ln)  #contrib-balance-g-690
    if (!is.na(hit)) return(hit)  #contrib-balance-g-691
  }  #contrib-balance-g-692
  #contrib-balance-g-693
  # 2. Word-boundary search on the FIRST non-empty line only.  #contrib-balance-v2-g-239
  # Searching the full response would cause false-positives when the model  #contrib-balance-v2-g-240
  # adds an explanation that mentions multiple topic keywords (e.g. DeepSeek  #contrib-balance-v2-g-241
  # verbose mode): the first topic in the list would always win regardless  #contrib-balance-v2-g-242
  # of the intended answer.  #contrib-balance-v2-g-243
  search_target <- if (length(nonempty)) nonempty[[1L]] else ""  #contrib-balance-v2-g-244
  if (nzchar(search_target)) {  #contrib-balance-v2-g-245
    for (j in seq_along(allowed_topics)) {  #contrib-balance-g-695  #contrib-balance-v2-g-246
      pattern <- paste0(  #contrib-balance-g-696  #contrib-balance-v2-g-247
        "(?i)\\b",  #contrib-balance-g-697  #contrib-balance-v2-g-248
        gsub("([^[:alnum:]])", "\\\\\\1", allowed_topics[j]),  #contrib-balance-g-698  #contrib-balance-v2-g-249
        "\\b"  #contrib-balance-g-699  #contrib-balance-v2-g-250
      )  #contrib-balance-g-700  #contrib-balance-v2-g-251
      if (grepl(pattern, search_target, perl = TRUE)) return(allowed_topics[[j]])  #contrib-balance-g-701  #contrib-balance-v2-g-252
    }  #contrib-balance-g-702  #contrib-balance-v2-g-253
  }  #contrib-balance-v2-g-254
  #contrib-balance-g-703
  unknown_label  #contrib-balance-g-704
}  #contrib-balance-g-705
  #contrib-balance-g-706
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
