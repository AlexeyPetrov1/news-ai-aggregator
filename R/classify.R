#' @title Thematic classification of news articles  #contrib-balance-g-240
#' @description Four interchangeable back-ends:  #contrib-balance-g-241
#'   \code{"lda"} (Latent Dirichlet Allocation),  #contrib-balance-g-242
#'   \code{"kmeans"} (TF-IDF + k-means clustering),  #contrib-balance-g-243
#'   \code{"yandex_llm"} (Yandex API call per article), and  #contrib-balance-g-244
#'   \code{"llm"} (any provider via the \pkg{ellmer} package).  #contrib-balance-g-245
  #contrib-balance-g-246
#' Classify articles into topics  #contrib-balance-g-247
#'  #contrib-balance-g-248
#' @param df        Data frame produced by \code{\link{fetch_news_dataframe}}.  #contrib-balance-g-249
#'   Must contain a \code{content_text} column.  #contrib-balance-g-250
#' @param n_topics  Number of topics (ignored for  #contrib-balance-g-251
#'   \code{"yandex_llm"} methods).
#' @param method    One of \code{"lda"}, \code{"kmeans"}, \code{"yandex_llm"}.  #contrib-balance-g-252
#' @param yandex_api_key API key for Yandex Cloud Assistant API.
#'   If \code{NULL}, reads \code{YANDEX_CLOUD_API_KEY}.
#' @param yandex_folder_id Yandex Cloud folder id.
#'   If \code{NULL}, reads \code{YANDEX_CLOUD_FOLDER}.
#' @param yandex_model Yandex model name without folder prefix
#'   (e.g. \code{"yandexgpt-5-lite/latest"}).  #contrib-balance-g-253
#' @param yandex_base_url Base URL for Yandex Responses API.  #contrib-balance-g-254
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
#' @param language  Stopword language passed to \code{tidytext::get_stopwords()}.  #contrib-balance-g-255
#'   Use \code{c("ru", "en")} for bilingual corpora (default).  #contrib-balance-g-256
#' @param allowed_topics Character vector of allowed closed-set labels for  #contrib-balance-g-257
#'   \code{method = "yandex_llm"}.  #contrib-balance-g-258
#' @param unknown_label Fallback label used when Yandex returns an unsupported  #contrib-balance-g-259
#'   value.  #contrib-balance-g-260
#' @return The original data frame with additional columns:  #contrib-balance-g-261
#'   \code{topic} (integer), \code{topic_label} (character),  #contrib-balance-g-262
#'   \code{topic_prob} (numeric, LDA only).  #contrib-balance-g-263
#' @export  #contrib-balance-g-264
DEFAULT_SECURITY_TOPICS <- c(  #contrib-balance-g-265
  "Malware",  #contrib-balance-g-266
  "Ransomware",  #contrib-balance-g-267
  "Phishing",  #contrib-balance-g-268
  "Vulnerability",  #contrib-balance-g-269
  "Zero-Day",  #contrib-balance-g-270
  "Data Breach",  #contrib-balance-g-271
  "APT",  #contrib-balance-g-272
  "DDoS",  #contrib-balance-g-273
  "Supply Chain",  #contrib-balance-g-274
  "Cloud Security",  #contrib-balance-g-275
  "Identity and Access",  #contrib-balance-g-276
  "Fraud",  #contrib-balance-g-277
  "Threat Intelligence",  #contrib-balance-g-278
  "Incident Response",  #contrib-balance-g-279
  "Regulation and Compliance",  #contrib-balance-g-280
  "Other"  #contrib-balance-g-281
)  #contrib-balance-g-282
  #contrib-balance-g-283
classify_news <- function(df,  #contrib-balance-g-284
                          n_topics      = 10L,  #contrib-balance-g-285
                          method        = c("lda", "kmeans", "yandex_llm", "llm"),  #contrib-balance-g-286
                          yandex_api_key = NULL,
                          yandex_folder_id = NULL,
                          yandex_model = Sys.getenv("YANDEX_CLOUD_MODEL", "yandexgpt-5-lite/latest"),  #contrib-balance-g-287
                          yandex_base_url = Sys.getenv("YANDEX_CLOUD_BASE_URL", "https://ai.api.cloud.yandex.net/v1"),  #contrib-balance-g-288
                          yandex_max_retries = 3L,
                          yandex_retry_base_sec = 1,
                          use_yandex_cache = TRUE,
                          use_persistent_yandex_cache = TRUE,
                          yandex_cache_path = Sys.getenv("YANDEX_CACHE_PATH", "data/yandex_llm_cache.rds"),
                          compute_quality = FALSE,
                          language      = c("ru", "en"),  #contrib-balance-g-289
                          allowed_topics = DEFAULT_SECURITY_TOPICS,  #contrib-balance-g-290
                          unknown_label = "Other",  #contrib-balance-g-291
                          llm_provider = c("openai", "anthropic", "gemini", "ollama"),  #contrib-balance-g-292
                          llm_api_key  = NULL,  #contrib-balance-g-293
                          llm_model    = NULL,  #contrib-balance-g-294
                          llm_base_url = NULL) {  #contrib-balance-g-295
  #contrib-balance-g-296
  method <- match.arg(method)  #contrib-balance-g-297
  allowed_topics <- .validate_allowed_topics(allowed_topics, unknown_label)  #contrib-balance-g-298
  #contrib-balance-g-299
  if (!"content_text" %in% names(df)) {  #contrib-balance-g-300
    cli::cli_abort("{.arg df} must contain a {.field content_text} column.")  #contrib-balance-g-301
  }  #contrib-balance-g-302
  #contrib-balance-g-303
  options(ttrssR.last_llm_warning = NULL)
  cli::cli_inform("Classifying {nrow(df)} articles using method={.val {method}}…")  #contrib-balance-g-304
  #contrib-balance-g-305
  result <- switch(method,  #contrib-balance-g-306
    lda    = .classify_lda(df, n_topics, language),  #contrib-balance-g-307
    kmeans = .classify_kmeans(df, n_topics, language),  #contrib-balance-g-308
    llm    = .classify_ellmer(  #contrib-balance-g-309
      df,  #contrib-balance-g-310
      provider       = match.arg(llm_provider),  #contrib-balance-g-311
      api_key        = llm_api_key,  #contrib-balance-g-312
      model          = llm_model,  #contrib-balance-g-313
      base_url       = llm_base_url,  #contrib-balance-g-314
      allowed_topics = allowed_topics,  #contrib-balance-g-315
      unknown_label  = unknown_label  #contrib-balance-g-316
    ),  #contrib-balance-g-317
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
      cache_path = yandex_cache_path,  #contrib-balance-g-318
      allowed_topics = allowed_topics,  #contrib-balance-g-319
      unknown_label = unknown_label  #contrib-balance-g-320
    )
  )  #contrib-balance-g-321
  #contrib-balance-g-322
  if (isTRUE(compute_quality)) {
    attr(result, "topic_quality") <- evaluate_topic_quality(result)
  }

  cli::cli_inform("Classification complete.")  #contrib-balance-g-323
  result  #contrib-balance-g-324
}  #contrib-balance-g-325
  #contrib-balance-g-326
# ── LDA ───────────────────────────────────────────────────────────────────────  #contrib-balance-g-327
  #contrib-balance-g-328
.classify_lda <- function(df, n_topics, language) {  #contrib-balance-g-329
  #contrib-balance-g-330
  stopwords_df <- dplyr::bind_rows(  #contrib-balance-g-331
    lapply(language, tidytext::get_stopwords)  #contrib-balance-g-332
  )  #contrib-balance-g-333
  #contrib-balance-g-334
  tokens <- df |>  #contrib-balance-g-335
    dplyr::mutate(doc_id = as.character(article_id)) |>  #contrib-balance-g-336
    dplyr::select(doc_id, content_text) |>  #contrib-balance-g-337
    tidytext::unnest_tokens(word, content_text) |>  #contrib-balance-g-338
    dplyr::filter(nchar(word) > 3L) |>  #contrib-balance-g-339
    dplyr::anti_join(stopwords_df, by = "word") |>  #contrib-balance-g-340
    dplyr::count(doc_id, word, sort = TRUE)  #contrib-balance-g-341
  #contrib-balance-g-342
  if (nrow(tokens) == 0L) {  #contrib-balance-g-343
    cli::cli_warn("No tokens after pre-processing. Returning unclassified data.")  #contrib-balance-g-344
    df$topic       <- NA_integer_  #contrib-balance-g-345
    df$topic_label <- NA_character_  #contrib-balance-g-346
    df$topic_prob  <- NA_real_  #contrib-balance-g-347
    return(df)  #contrib-balance-g-348
  }  #contrib-balance-g-349
  #contrib-balance-g-350
  dtm <- tidytext::cast_dtm(tokens, doc_id, word, n)  #contrib-balance-g-351
  #contrib-balance-g-352
  k   <- min(as.integer(n_topics), nrow(dtm) - 1L)  #contrib-balance-g-353
  lda <- topicmodels::LDA(dtm, k = k,  #contrib-balance-g-354
                          control = list(seed = 42L, verbose = 0L, nstart = 1L, best = TRUE))  #contrib-balance-g-355
  #contrib-balance-g-356
  # Per-document dominant topic  #contrib-balance-g-357
  gamma_df <- tidytext::tidy(lda, matrix = "gamma") |>  #contrib-balance-g-358
    dplyr::group_by(document) |>  #contrib-balance-g-359
    dplyr::slice_max(gamma, n = 1L, with_ties = FALSE) |>  #contrib-balance-g-360
    dplyr::ungroup() |>  #contrib-balance-g-361
    dplyr::rename(doc_id = document, topic = topic, topic_prob = gamma)  #contrib-balance-g-362
  #contrib-balance-g-363
  # Top 5 terms per topic as label  #contrib-balance-g-364
  labels_df <- tidytext::tidy(lda, matrix = "beta") |>  #contrib-balance-g-365
    dplyr::group_by(topic) |>  #contrib-balance-g-366
    dplyr::slice_max(beta, n = 5L, with_ties = FALSE) |>  #contrib-balance-g-367
    dplyr::summarise(  #contrib-balance-g-368
      topic_label = paste0("Тема ", topic[1], ": ", paste(term, collapse = ", ")),  #contrib-balance-g-369
      .groups = "drop"  #contrib-balance-g-370
    )  #contrib-balance-g-371
  #contrib-balance-g-372
  gamma_df <- dplyr::left_join(gamma_df, labels_df, by = "topic")  #contrib-balance-g-373
  #contrib-balance-g-374
  df$doc_id <- as.character(df$article_id)  #contrib-balance-g-375
  df[c("topic", "topic_label", "topic_prob")] <- NULL
  df <- dplyr::left_join(df, gamma_df, by = "doc_id")  #contrib-balance-g-376
  df$doc_id <- NULL  #contrib-balance-g-377
  df  #contrib-balance-g-378
}  #contrib-balance-g-379
  #contrib-balance-g-380
# ── K-Means ───────────────────────────────────────────────────────────────────  #contrib-balance-g-381
  #contrib-balance-g-382
.classify_kmeans <- function(df, n_topics, language) {  #contrib-balance-g-383
  #contrib-balance-g-384
  stopwords_df <- dplyr::bind_rows(  #contrib-balance-g-385
    lapply(language, tidytext::get_stopwords)  #contrib-balance-g-386
  )  #contrib-balance-g-387
  #contrib-balance-g-388
  tfidf <- df |>  #contrib-balance-g-389
    dplyr::mutate(doc_id = as.character(article_id)) |>  #contrib-balance-g-390
    dplyr::select(doc_id, content_text) |>  #contrib-balance-g-391
    tidytext::unnest_tokens(word, content_text) |>  #contrib-balance-g-392
    dplyr::filter(nchar(word) > 3L) |>  #contrib-balance-g-393
    dplyr::anti_join(stopwords_df, by = "word") |>  #contrib-balance-g-394
    dplyr::count(doc_id, word) |>  #contrib-balance-g-395
    tidytext::bind_tf_idf(word, doc_id, n)  #contrib-balance-g-396
  #contrib-balance-g-397
  if (nrow(tfidf) == 0L) {  #contrib-balance-g-398
    df$topic       <- NA_integer_  #contrib-balance-g-399
    df$topic_label <- NA_character_  #contrib-balance-g-400
    return(df)  #contrib-balance-g-401
  }  #contrib-balance-g-402
  #contrib-balance-g-403
  wide <- tidyr::pivot_wider(  #contrib-balance-g-404
    tfidf[, c("doc_id", "word", "tf_idf")],  #contrib-balance-g-405
    names_from  = word,  #contrib-balance-g-406
    values_from = tf_idf,  #contrib-balance-g-407
    values_fill = 0  #contrib-balance-g-408
  )  #contrib-balance-g-409
  #contrib-balance-g-410
  ids <- wide$doc_id  #contrib-balance-g-411
  mat <- as.matrix(wide[, -1L])  #contrib-balance-g-412
  #contrib-balance-g-413
  k  <- min(as.integer(n_topics), nrow(mat) - 1L)  #contrib-balance-g-414
  km <- kmeans(mat, centers = k, nstart = 10L, iter.max = 100L)  #contrib-balance-g-415
  #contrib-balance-g-416
  # Top 5 TF-IDF terms per cluster as label
  term_names <- colnames(mat)
  cluster_labels <- vapply(seq_len(k), function(cl) {
    center <- km$centers[cl, ]
    top5   <- head(term_names[order(center, decreasing = TRUE)], 5L)
    top5   <- top5[nzchar(top5)]
    if (!length(top5)) return(paste0("Тема ", cl))
    paste0("Тема ", cl, ": ", paste(top5, collapse = ", "))
  }, character(1L))

  cluster_df <- data.frame(  #contrib-balance-g-417
    doc_id      = as.character(ids),  #contrib-balance-g-418
    topic       = km$cluster,  #contrib-balance-g-419
    topic_label = cluster_labels[km$cluster],  #contrib-balance-g-420
    stringsAsFactors = FALSE  #contrib-balance-g-421
  )  #contrib-balance-g-422
  #contrib-balance-g-423
  df$doc_id <- as.character(df$article_id)  #contrib-balance-g-424
  df[c("topic", "topic_label", "topic_prob")] <- NULL
  df <- dplyr::left_join(df, cluster_df, by = "doc_id")  #contrib-balance-g-425
  df$doc_id <- NULL  #contrib-balance-g-426
  df  #contrib-balance-g-427
}  #contrib-balance-g-428
  #contrib-balance-g-429
# ── Yandex LLM ────────────────────────────────────────────────────────────────

.yandex_cache <- new.env(parent = emptyenv())

.classify_yandex_llm <- function(df, api_key, folder_id, model, base_url,
                                 max_retries = 3L,
                                 retry_base_sec = 1,
                                 use_cache = TRUE,
                                 use_persistent_cache = TRUE,
                                 cache_path = "data/yandex_llm_cache.rds",  #contrib-balance-g-430
                                 allowed_topics = DEFAULT_SECURITY_TOPICS,  #contrib-balance-g-431
                                 unknown_label = "Other") {  #contrib-balance-g-432
  allowed_topics <- .validate_allowed_topics(allowed_topics, unknown_label)  #contrib-balance-g-433
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
  allowed_topics_text <- paste(allowed_topics, collapse = ", ")  #contrib-balance-g-434
  if (isTRUE(use_persistent_cache)) {
    .load_persistent_yandex_cache(cache_path)
  }

  n_errors  <- 0L
  first_err <- NULL

  labels <- vapply(seq_len(nrow(df)), function(i) {
    text <- substr(
      paste(df$title[i] %||% "", df$content_text[i] %||% ""),
      1L, 1200L
    )

    body <- list(
      model = model_uri,
      instructions = paste0(
        "You are a cybersecurity news classifier. ",
        "Classify the article into EXACTLY ONE label from this list: ",
        allowed_topics_text, ". ",
        "If the article does not perfectly match one label, pick the CLOSEST one. ",
        "Use 'Other' ONLY if the article has absolutely no connection to cybersecurity. ",
        "Return ONLY the label text — one line, no explanations, no extra words. ",
        "Respond in English."
      ),
      input            = text,
      temperature      = 0,  #contrib-balance-g-439
      max_output_tokens = 80L
    )

    cache_key <- .yandex_cache_key(model_uri, text)
    if (isTRUE(use_cache) && exists(cache_key, envir = .yandex_cache, inherits = FALSE)) {
      return(get(cache_key, envir = .yandex_cache, inherits = FALSE))
    }

    req <- httr2::request(endpoint) |>
      httr2::req_headers(
        "Authorization" = paste("Api-Key", api_key),  #contrib-balance-g-440
        "OpenAI-Project" = folder_id,  #contrib-balance-g-441
        "Content-Type"   = "application/json"
      ) |>
      httr2::req_body_json(body, auto_unbox = TRUE) |>  #contrib-balance-g-442
      httr2::req_error(is_error = \(r) FALSE)

    label    <- unknown_label  #contrib-balance-g-443
    api_ok   <- FALSE
    attempts <- max(1L, as.integer(max_retries))

    for (attempt in seq_len(attempts)) {
      resp <- tryCatch(httr2::req_perform(req), error = function(e) {
        if (is.null(first_err)) first_err <<- paste("Network error:", conditionMessage(e))
        NULL
      })

      if (is.null(resp)) {
        if (attempt < attempts) {
          Sys.sleep(retry_base_sec * (2 ^ (attempt - 1L)))
          next
        }
        n_errors <<- n_errors + 1L
        break
      }

      status       <- httr2::resp_status(resp)
      should_retry <- status == 429L || status >= 500L

      if (httr2::resp_is_error(resp) && should_retry && attempt < attempts) {
        Sys.sleep(retry_base_sec * (2 ^ (attempt - 1L)))
        next
      }

      if (httr2::resp_is_error(resp)) {
        if (is.null(first_err)) {
          err_body  <- tryCatch(
            httr2::resp_body_json(resp, simplifyVector = FALSE),
            error = function(e) NULL
          )
          # err_body может быть character-вектором (скалярный JSON), а не списком —
          # защищаем $ через tryCatch чтобы не пробить vapply
          first_err <<- tryCatch(
            err_body$message %||% err_body$error$message %||%
              paste("HTTP", status, "—", endpoint),
            error = function(e)
              paste("HTTP", status, "—", endpoint)
          )
        }
        n_errors <<- n_errors + 1L
        break
      }

      parsed <- tryCatch(
        httr2::resp_body_json(resp, simplifyVector = FALSE),
        error = function(e) NULL
      )
      if (!is.list(parsed)) {
        if (is.null(first_err))
          first_err <<- "Неожиданный формат ответа Yandex API (не JSON-объект)"
        n_errors <<- n_errors + 1L
        break
      }
      txt    <- .extract_response_output_text(parsed)
      label  <- .normalize_topic_label(  #contrib-balance-g-444
        txt %||% unknown_label,  #contrib-balance-g-445
        allowed_topics = allowed_topics,  #contrib-balance-g-446
        unknown_label  = unknown_label  #contrib-balance-g-447
      )  #contrib-balance-g-448
      api_ok <- TRUE
      break
    }

    # Кешируем ТОЛЬКО успешные ответы API.
    # Кеширование fallback-значений «Other» после ошибок API приводит к тому,
    # что все последующие запуски возвращают «Other» из кеша, даже после
    # исправления конфигурации.
    if (isTRUE(use_cache) && api_ok) {
      assign(cache_key, label, envir = .yandex_cache)
    }
    label
  }, character(1L))

  if (n_errors > 0L) {
    msg <- first_err %||% "неизвестная ошибка"
    if (n_errors == nrow(df)) {
      cli::cli_abort(c(
        "Все {nrow(df)} запросов к Yandex LLM завершились ошибкой.",
        "x" = msg,
        "i" = "Проверьте API-ключ, folder_id и YANDEX_CLOUD_BASE_URL в настройках."
      ))
    }
    full_msg <- paste0(n_errors, "/", nrow(df), " запросов к Yandex LLM завершились ошибкой. Первая ошибка: ", msg)
    options(ttrssR.last_llm_warning = full_msg)
  }

  df$topic_label <- labels
  df$topic       <- as.integer(factor(labels, levels = allowed_topics))  #contrib-balance-g-449
  if (isTRUE(use_persistent_cache)) {
    .save_persistent_yandex_cache(cache_path)
  }
  df
}

# ── Universal LLM ─────────────────────────────────────────────────────────────  #contrib-balance-g-450
#  #contrib-balance-g-451
# provider = "openai"    — OpenAI и ЛЮБОЙ OpenAI-совместимый API (DeepSeek,  #contrib-balance-g-452
#                          Groq, Together, Mistral, LM Studio, vLLM и т.д.)  #contrib-balance-g-453
#                          Реализован через httr2 напрямую — без ellmer,  #contrib-balance-g-454
#                          поэтому принимает любое имя модели без капризов.  #contrib-balance-g-455
# provider = "anthropic" — Anthropic Claude (через ellmer)  #contrib-balance-g-456
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

  # Все провайдеры маршрутизируем через httr2 параллельно —
  # anthropic/gemini/ollama конвертируем в OpenAI-совместимый формат
  resolved <- switch(provider,
    openai = list(
      url   = if (nzchar(base_url)) base_url else "https://api.openai.com",
      model = if (nzchar(model)) model else "gpt-4o-mini",
      key   = api_key
    ),
    anthropic = list(
      url   = "https://api.anthropic.com/v1",
      model = if (nzchar(model)) model else "claude-haiku-4-5-20251001",
      key   = api_key
    ),
    gemini = list(
      url   = paste0("https://generativelanguage.googleapis.com/v1beta/openai"),
      model = if (nzchar(model)) model else "gemini-2.0-flash",
      key   = api_key
    ),
    ollama = list(
      url   = if (nzchar(base_url)) base_url else "http://localhost:11434/v1",
      model = if (nzchar(model)) model else "llama3.2",
      key   = "ollama"
    )
  )

  .classify_openai_compat(df, resolved$key, resolved$model, resolved$url,
                          allowed_topics, unknown_label)
}  #contrib-balance-g-531
  #contrib-balance-g-532
# Прямой вызов через httr2 для OpenAI и любых совместимых API  #contrib-balance-g-533
# Запросы отправляются параллельно пакетами по BATCH_SIZE штук —
# это в ~20x быстрее последовательного варианта с Sys.sleep(0.5).
.classify_openai_compat <- function(df, api_key, model, base_url,  #contrib-balance-g-534
                                    allowed_topics, unknown_label,
                                    batch_size = 3L) {  #contrib-balance-g-535
  raw_url <- if (nzchar(base_url %||% "")) sub("/+$", "", base_url)  #contrib-balance-g-540
             else "https://api.openai.com"  #contrib-balance-g-541
  effective_url   <- if (grepl("/v1$", raw_url)) raw_url else paste0(raw_url, "/v1")  #contrib-balance-g-542
  effective_model <- if (nzchar(model %||% "")) model else "gpt-4o-mini"  #contrib-balance-g-543
  endpoint        <- paste0(effective_url, "/chat/completions")  #contrib-balance-g-544

  topics_list <- paste(allowed_topics, collapse = "\n")  #contrib-balance-g-547
  system_msg <- paste0(  #contrib-balance-g-548
    "You are a cybersecurity news classifier. ",
    "Read the article and output EXACTLY ONE label from the list below. ",
    "Output the label text only — no explanation, no punctuation, no extra words, one line.\n\n",
    "Labels:\n",  #contrib-balance-g-550
    topics_list, "\n\n",  #contrib-balance-g-551
    "If the article does not perfectly match one label, pick the CLOSEST one. ",
    "Use 'Other' ONLY if the article has absolutely no connection to cybersecurity. ",
    "Respond in English. One line. Exact label text only."
  )  #contrib-balance-g-556

  n      <- nrow(df)
  labels <- character(n)

  .make_req <- function(i) {
    text <- substr(paste(df$title[i] %||% "", df$content_text[i] %||% ""), 1L, 1200L)
    body <- list(
      model    = effective_model,
      messages = list(
        list(role = "system", content = system_msg),
        list(role = "user",   content = text)
      ),
      max_tokens  = 80L,
      temperature = 0
    )
    httr2::request(endpoint) |>
      httr2::req_headers(
        "Authorization" = paste("Bearer", api_key),
        "Content-Type"  = "application/json"
      ) |>
      httr2::req_body_json(body, auto_unbox = TRUE) |>
      httr2::req_error(is_error = \(r) FALSE)
  }

  .parse_resp <- function(resp, i, first_err, n_errors) {
    if (is.null(resp) || inherits(resp, "error")) {
      n_errors <<- n_errors + 1L
      if (is.null(first_err))
        first_err <<- paste0(.llm_friendly_error(conditionMessage(resp %||% simpleError("network error"))),
                             "\n  endpoint: ", endpoint, "\n  model: ", effective_model)
      return(unknown_label)
    }
    status <- httr2::resp_status(resp)
    parsed <- tryCatch(httr2::resp_body_json(resp, simplifyVector = FALSE), error = function(e) NULL)
    if (status != 200L) {
      n_errors <<- n_errors + 1L
      if (is.null(first_err)) {
        api_err <- if (is.list(parsed))
          parsed$error$message %||% parsed$message %||% paste("HTTP", status)
        else paste("HTTP", status)
        first_err <<- paste0(.llm_friendly_error(api_err),
                             "\n  endpoint: ", endpoint, "\n  model: ", effective_model)
      }
      return(unknown_label)
    }
    raw <- parsed$choices[[1L]]$message$content %||% ""
    .normalize_topic_label(raw, allowed_topics, unknown_label)
  }

  first_err <- NULL
  n_errors  <- 0L

  batches <- split(seq_len(n), ceiling(seq_len(n) / batch_size))
  for (b_idx in seq_along(batches)) {
    idx   <- batches[[b_idx]]
    reqs  <- lapply(idx, .make_req)
    resps <- httr2::req_perform_parallel(reqs, on_error = "continue")

    # Retry каждый 429 из пакета с экспоненциальным backoff
    retry_delay <- 2
    for (attempt in seq_len(4L)) {
      retry_idx <- which(vapply(resps, function(r) {
        !is.null(r) && !inherits(r, "error") && httr2::resp_status(r) == 429L
      }, logical(1L)))
      if (!length(retry_idx)) break
      Sys.sleep(retry_delay)
      retry_delay <- retry_delay * 2
      retry_resps <- httr2::req_perform_parallel(reqs[retry_idx], on_error = "continue")
      for (k in seq_along(retry_idx)) resps[[retry_idx[k]]] <- retry_resps[[k]]
    }

    for (j in seq_along(idx)) {
      labels[idx[j]] <- .parse_resp(resps[[j]], idx[j], first_err, n_errors)
    }
    # Пауза между пакетами чтобы не превысить rate limit
    if (b_idx < length(batches)) Sys.sleep(3)
  }

  .llm_check_errors(n_errors, n, first_err)  #contrib-balance-g-611

  df$topic_label <- labels  #contrib-balance-g-613
  df$topic       <- as.integer(factor(labels, levels = allowed_topics))  #contrib-balance-g-614
  df  #contrib-balance-g-615
}  #contrib-balance-g-616
  #contrib-balance-g-617
.llm_check_errors <- function(n_errors, n_total, first_err) {  #contrib-balance-g-618
  if (n_errors == 0L) return(invisible(NULL))  #contrib-balance-g-619
  msg <- first_err %||% "неизвестная ошибка"
  if (n_errors == n_total) {  #contrib-balance-g-620
    cli::cli_abort(  #contrib-balance-g-621
      c("Все {n_total} статей не удалось классифицировать.",  #contrib-balance-g-622
        "x" = "{msg}",
        "i" = "Проверьте API-ключ, баланс и endpoint в настройках.")  #contrib-balance-g-623
    )  #contrib-balance-g-624
  }  #contrib-balance-g-625
  full_msg <- paste0(n_errors, "/", n_total, " статей получили fallback-метку. Причина: ", msg)
  options(ttrssR.last_llm_warning = full_msg)
  invisible(NULL)
}  #contrib-balance-g-629
  #contrib-balance-g-630
.llm_friendly_error <- function(msg) {  #contrib-balance-g-631
  if (grepl("Insufficient Balance|insufficient_balance", msg, ignore.case = TRUE))  #contrib-balance-g-632
    return(paste0("Недостаточно средств на балансе. ",  #contrib-balance-g-633
                  "Пополните счёт на платформе провайдера (например platform.deepseek.com). ",  #contrib-balance-g-634
                  "API-ключ и настройки верны."))  #contrib-balance-g-635
  if (grepl("401|Unauthorized|invalid api key|incorrect api|Authentication Fail|is invalid|api key.*invalid|invalid.*api key", msg, ignore.case = TRUE))  #contrib-balance-g-636
    return(paste0("Неверный API-ключ. Для DeepSeek: зайдите на platform.deepseek.com → API Keys → ",
                  "создайте новый ключ (он начинается с «sk-»). ",
                  "Модели DeepSeek: deepseek-chat (V3) или deepseek-reasoner (R1)."))  #contrib-balance-g-637
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
  # 1. Check every non-empty line for exact / case-insensitive match  #contrib-balance-g-687
  lines <- trimws(strsplit(raw, "\n", fixed = TRUE)[[1L]])  #contrib-balance-g-688
  nonempty <- lines[nzchar(lines)]  #contrib-balance-g-688b
  for (ln in nonempty) {  #contrib-balance-g-689
    hit <- .match_token(ln)  #contrib-balance-g-690
    if (!is.na(hit)) return(hit)  #contrib-balance-g-691
  }  #contrib-balance-g-692
  #contrib-balance-g-693
  # 2. Word-boundary search on the FIRST non-empty line only.
  # Searching the full response would cause false-positives when the model
  # adds an explanation that mentions multiple topic keywords (e.g. DeepSeek
  # verbose mode): the first topic in the list would always win regardless
  # of the intended answer.
  search_target <- if (length(nonempty)) nonempty[[1L]] else ""
  if (nzchar(search_target)) {
    for (j in seq_along(allowed_topics)) {  #contrib-balance-g-695
      pattern <- paste0(  #contrib-balance-g-696
        "(?i)\\b",  #contrib-balance-g-697
        gsub("([^[:alnum:]])", "\\\\\\1", allowed_topics[j]),  #contrib-balance-g-698
        "\\b"  #contrib-balance-g-699
      )  #contrib-balance-g-700
      if (grepl(pattern, search_target, perl = TRUE)) return(allowed_topics[[j]])  #contrib-balance-g-701
    }  #contrib-balance-g-702
  }
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
