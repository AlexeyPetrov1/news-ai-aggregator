## ============================================================  #contrib-balance-k-1321
## data-raw/_replace_feeds_ru.R  #contrib-balance-k-1322
##  #contrib-balance-k-1323
## Удаляет все текущие фиды из TT-RSS и подписывается  #contrib-balance-k-1324
## только на русскоязычные источники по ИБ.  #contrib-balance-k-1325
## ============================================================  #contrib-balance-k-1326
  #contrib-balance-k-1327
library(ttrssR)  #contrib-balance-k-1328
  #contrib-balance-k-1329
TTRSS_URL  <- Sys.getenv("TTRSS_URL",      "http://localhost:8080")  #contrib-balance-k-1330
TTRSS_USER <- Sys.getenv("TTRSS_USER",     "admin")  #contrib-balance-k-1331
TTRSS_PASS <- Sys.getenv("TTRSS_PASSWORD", "password")  #contrib-balance-k-1332
  #contrib-balance-k-1333
ru_feeds <- list(  #contrib-balance-k-1334
  #contrib-balance-k-1335
  "Threat Research (RU)" = c(  #contrib-balance-k-1336
    "https://securelist.ru/feed/",  #contrib-balance-k-1337
    "https://www.kaspersky.ru/blog/feed/",  #contrib-balance-k-1338
    "https://www.ptsecurity.com/ru-ru/about/news/rss/"  #contrib-balance-k-1339
  ),  #contrib-balance-k-1340
  #contrib-balance-k-1341
  "ИБ-новости (RU)" = c(  #contrib-balance-k-1342
    "https://www.anti-malware.ru/rss.xml",  #contrib-balance-k-1343
    "https://www.securitylab.ru/rss/",  #contrib-balance-k-1344
    "https://xakep.ru/feed/",  #contrib-balance-k-1345
    "https://cisoclub.ru/feed/"  #contrib-balance-k-1346
  ),  #contrib-balance-k-1347
  #contrib-balance-k-1348
  "Сообщество (RU)" = c(  #contrib-balance-k-1349
    "https://habr.com/ru/rss/hub/information_security/articles/",  #contrib-balance-k-1350
    "https://habr.com/ru/rss/hub/netsecurity/articles/"  #contrib-balance-k-1351
  ),  #contrib-balance-k-1352
  #contrib-balance-k-1353
  "CERT / Регуляторы (RU)" = c(  #contrib-balance-k-1354
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
