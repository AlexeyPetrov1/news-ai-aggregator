make_df <- function(n = 20) {
  data.frame(
    article_id   = seq_len(n),
    title        = paste("Новость", seq_len(n)),
    content_text = rep(c(
      "Политика правительство парламент выборы депутаты закон президент",
      "Экономика рынок биржа инвестиции валюта рубль доллар финансы",
      "Спорт футбол чемпионат команда победа матч тренер игроки"
    ), length.out = n),
    stringsAsFactors = FALSE
  )
}

test_that("classify_news lda returns topic columns", {
  skip_if_not_installed("topicmodels")
  skip_if_not_installed("tidytext")
  df     <- make_df(30)
  result <- classify_news(df, n_topics = 3L, method = "lda")
  expect_true("topic"       %in% names(result))
  expect_true("topic_label" %in% names(result))
  expect_true("topic_prob"  %in% names(result))
  expect_equal(nrow(result), 30L)
})

test_that("classify_news kmeans returns topic columns", {
  skip_if_not_installed("tidytext")
  df     <- make_df(15)
  result <- classify_news(df, n_topics = 3L, method = "kmeans")
  expect_true("topic"       %in% names(result))
  expect_true("topic_label" %in% names(result))
  expect_equal(nrow(result), 15L)
})

test_that("classify_news errors on missing content_text", {
  df <- data.frame(article_id = 1L, title = "x")
  expect_error(classify_news(df, method = "lda"), "content_text")
})

test_that("classify_news llm errors without api key", {
  df <- make_df(3)
  expect_error(classify_news(df, method = "llm", llm_api_key = NULL),
               "llm_api_key")
})

test_that("classify_news yandex_llm errors without api key", {
  df <- make_df(3)
  expect_error(
    classify_news(
      df,
      method = "yandex_llm",
      yandex_api_key = NULL,
      yandex_folder_id = "b1examplefolder"
    ),
    "yandex_api_key|YANDEX_CLOUD_API_KEY"
  )
})

test_that("classify_news yandex_llm errors without folder id", {
  df <- make_df(3)
  expect_error(
    classify_news(
      df,
      method = "yandex_llm",
      yandex_api_key = "dummy-key",
      yandex_folder_id = ""
    ),
    "yandex_folder_id|YANDEX_CLOUD_FOLDER"
  )
})

test_that("evaluate_topic_quality returns summary metrics", {
  df <- make_df(12)
  df$topic_label <- rep(c("APT", "Ransomware", "Phishing"), length.out = 12)
  metrics <- evaluate_topic_quality(df)

  expect_type(metrics, "list")
  expect_true("label_coverage" %in% names(metrics))
  expect_true("topic_distinctiveness" %in% names(metrics))
  expect_true("per_topic" %in% names(metrics))
  expect_s3_class(metrics$per_topic, "data.frame")
  expect_equal(metrics$n_documents, 12)
})

test_that("yandex cache can persist to disk", {
  cache_env <- ttrssR:::.yandex_cache
  cache_file <- tempfile(fileext = ".rds")
  old_vals <- as.list(cache_env, all.names = TRUE)
  rm(list = ls(cache_env, all.names = TRUE), envir = cache_env)

  on.exit({
    rm(list = ls(cache_env, all.names = TRUE), envir = cache_env)
    for (nm in names(old_vals)) assign(nm, old_vals[[nm]], envir = cache_env)
    if (file.exists(cache_file)) unlink(cache_file)
  }, add = TRUE)

  assign("k1", "label-a", envir = cache_env)
  ttrssR:::.save_persistent_yandex_cache(cache_file)
  rm(list = ls(cache_env, all.names = TRUE), envir = cache_env)

  ttrssR:::.load_persistent_yandex_cache(cache_file)
  expect_true(exists("k1", envir = cache_env, inherits = FALSE))
  expect_equal(get("k1", envir = cache_env, inherits = FALSE), "label-a")
})
