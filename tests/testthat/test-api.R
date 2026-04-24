test_that("ttrss_login validates url format", {
  # Функция должна возвращать ошибку HTTP, а не зависать при неверном URL
  expect_error(
    ttrss_login("http://127.0.0.1:19999", "user", "pass"),
    regexp = NULL   # любая ошибка — ОК (нет сервера)
  )
})

test_that(".ttrss_api_url builds correct path", {
  f <- ttrssR:::.ttrss_api_url
  expect_equal(f("http://localhost:8080"),   "http://localhost:8080/api/")
  expect_equal(f("http://localhost:8080/"), "http://localhost:8080/api/")
})

test_that("%||% returns fallback for NULL and empty", {
  f <- ttrssR:::`%||%`
  expect_equal(f(NULL, "default"), "default")
  expect_equal(f(character(0), "default"), "default")
  expect_equal(f("value", "default"), "value")
})
