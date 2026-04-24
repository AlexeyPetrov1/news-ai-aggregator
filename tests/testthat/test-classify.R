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
