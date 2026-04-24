test_that(".strip_html removes tags and decodes entities", {
  f <- ttrssR:::.strip_html
  expect_equal(f("<p>Hello &amp; World</p>"), "Hello & World")
  expect_equal(f("<b>Text</b><br/>more"), "Text more")
  expect_equal(f("No tags"), "No tags")
  expect_equal(f("A&nbsp;B"), "A B")
})

test_that(".normalize_articles returns data frame", {
  raw <- data.frame(
    id         = 1L,
    title      = "Test Article",
    content    = "<p>Hello</p>",
    link       = "https://example.com",
    feed_id    = 10L,
    feed_title = "Test Feed",
    author     = "Author",
    updated    = as.character(as.integer(Sys.time())),
    unread     = TRUE,
    marked     = FALSE,
    stringsAsFactors = FALSE
  )
  result <- ttrssR:::.normalize_articles(raw)
  expect_s3_class(result, "data.frame")
  expect_true("article_id" %in% names(result))
  expect_true("content_text" %in% names(result))
  expect_equal(result$content_text, "Hello")
  expect_s3_class(result$published_at, "POSIXct")
})

test_that("fetch_news_dataframe errors gracefully without server", {
  expect_error(
    fetch_news_dataframe("http://127.0.0.1:19999", "u", "p",
                          max_articles = 10L)
  )
})
