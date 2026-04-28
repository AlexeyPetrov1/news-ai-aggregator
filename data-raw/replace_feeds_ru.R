## ============================================================
## data-raw/_replace_feeds_ru.R
##
## Удаляет все текущие фиды из TT-RSS и подписывается
## только на русскоязычные источники по ИБ.
## ============================================================

library(ttrssR)

TTRSS_URL  <- Sys.getenv("TTRSS_URL",      "http://localhost:8080")
TTRSS_USER <- Sys.getenv("TTRSS_USER",     "admin")
TTRSS_PASS <- Sys.getenv("TTRSS_PASSWORD", "password")

ru_feeds <- list(

  "Threat Research (RU)" = c(
    "https://securelist.ru/feed/",
    "https://www.kaspersky.ru/blog/feed/",
    "https://www.ptsecurity.com/ru-ru/about/news/rss/"
  ),

  "ИБ-новости (RU)" = c(
    "https://www.anti-malware.ru/rss.xml",
    "https://www.securitylab.ru/rss/",
    "https://xakep.ru/feed/",
    "https://cisoclub.ru/feed/"
  ),

  "Сообщество (RU)" = c(
    "https://habr.com/ru/rss/hub/information_security/articles/",
    "https://habr.com/ru/rss/hub/netsecurity/articles/"
  ),

  "CERT / Регуляторы (RU)" = c(
    "https://bdu.fstec.ru/news/rss",
    "https://safe-surf.ru/rss/"
  )
)

cat("Подключение к TT-RSS...\n")
sid <- ttrss_login(TTRSS_URL, TTRSS_USER, TTRSS_PASS)

# ── Шаг 1: удалить все текущие фиды ──────────────────────────────────────────

cat("\n=== Шаг 1: Удаление текущих фидов ===\n")
existing <- ttrss_get_feeds(TTRSS_URL, sid)

if (nrow(existing) > 0 && "id" %in% names(existing)) {
  feed_ids <- as.integer(existing$id[existing$id > 0])
  for (fid in feed_ids) {
    tryCatch({
      ttrss_unsubscribe_feed(TTRSS_URL, sid, fid)
      cat(sprintf("  [УДАЛЁН] id=%d\n", fid))
    }, error = function(e) {
      cat(sprintf("  [ОШИБКА] id=%d: %s\n", fid, conditionMessage(e)))
    })
    Sys.sleep(0.3)
  }
  cat(sprintf("Удалено: %d фидов\n", length(feed_ids)))
} else {
  cat("Фидов не найдено.\n")
}

# ── Шаг 2: подписаться на русские источники ───────────────────────────────────

cat("\n=== Шаг 2: Подписка на русскоязычные источники ===\n")
ok  <- 0L
err <- 0L

for (cat_name in names(ru_feeds)) {
  cat(sprintf("\n── %s ──\n", cat_name))
  for (url in ru_feeds[[cat_name]]) {
    tryCatch({
      ttrss_subscribe_feed(TTRSS_URL, sid, feed_url = url, category_id = 0L)
      cat(sprintf("  [OK]  %s\n", url))
      ok <- ok + 1L
    }, error = function(e) {
      cat(sprintf("  [ERR] %s\n       %s\n", url, conditionMessage(e)))
      err <- err + 1L
    })
    Sys.sleep(0.5)
  }
}

cat(sprintf("\n=== Готово: добавлено %d фидов, ошибок: %d ===\n", ok, err))

ttrss_logout(TTRSS_URL, sid)
