## ============================================================
## data-raw/add_security_feeds.R
##
## Подписка на RSS-фиды по теме APT / Threat Intelligence
## через TT-RSS API.
## ============================================================

library(ttrssR)

TTRSS_URL  <- Sys.getenv("TTRSS_URL", "http://localhost:8080")
TTRSS_USER <- Sys.getenv("TTRSS_USER", "admin")
TTRSS_PASS <- Sys.getenv("TTRSS_PASSWORD", "password")

# ── Источники по категориям (только русскоязычные) ───────────────────────────

feeds <- list(

  # Исследования угроз — российские вендоры
  "Threat Research (RU)" = c(
    "https://securelist.ru/feed/",                                    # Kaspersky GReAT (рус.)
    "https://www.kaspersky.ru/blog/feed/",                            # Kaspersky блог
    "https://www.ptsecurity.com/ru-ru/about/news/rss/"               # Positive Technologies
  ),

  # Новости ИБ — русскоязычные СМИ
  "ИБ-новости (RU)" = c(
    "https://www.anti-malware.ru/rss.xml",                            # Anti-Malware.ru
    "https://www.securitylab.ru/rss/",                                # SecurityLab
    "https://xakep.ru/feed/",                                         # Хакер.ру
    "https://cisoclub.ru/feed/"                                       # CISO Club
  ),

  # Профессиональное сообщество
  "Сообщество (RU)" = c(
    "https://habr.com/ru/rss/hub/information_security/articles/",     # Хабр — ИБ
    "https://habr.com/ru/rss/hub/netsecurity/articles/"               # Хабр — сетевая безопасность
  ),

  # Государственные / CERT
  "CERT / Регуляторы (RU)" = c(
    "https://bdu.fstec.ru/news/rss",                                  # БДУ ФСТЭК
    "https://safe-surf.ru/rss/"                                       # SafeSurf (НКЦКИ)
  )
)

# ── Подключение ───────────────────────────────────────────────────────────────

cat("Подключение к TT-RSS...\n")
sid <- ttrss_login(TTRSS_URL, TTRSS_USER, TTRSS_PASS)

# ── Подписка ──────────────────────────────────────────────────────────────────

total_ok  <- 0L
total_err <- 0L

for (cat_name in names(feeds)) {
  cat(sprintf("\n── Категория: %s ──\n", cat_name))

  for (url in feeds[[cat_name]]) {
    result <- tryCatch({
      ttrss_subscribe_feed(TTRSS_URL, sid, feed_url = url, category_id = 0L)
      cat(sprintf("  [OK]  %s\n", url))
      "ok"
    }, error = function(e) {
      msg <- conditionMessage(e)
      msg_lc <- tolower(msg)
      if (grepl("already|exists|уже", msg_lc)) {
        cat(sprintf("  [SKIP] %s\n       %s\n", url, msg))
        "ok"
      } else {
        cat(sprintf("  [ERR] %s\n       %s\n", url, msg))
        "err"
      }
    })

    if (result == "ok") total_ok  <- total_ok  + 1L
    else                total_err <- total_err + 1L

    Sys.sleep(0.5)
  }
}

# ── Итог ──────────────────────────────────────────────────────────────────────

cat(sprintf(
  "\n=== Готово: добавлено %d фидов, ошибок: %d ===\n",
  total_ok, total_err
))

cat("\nТекущие фиды в TT-RSS:\n")
feeds_df <- ttrss_get_feeds(TTRSS_URL, sid)
if (nrow(feeds_df) > 0) {
  show_cols <- intersect(c("id", "title", "feed_url", "url"), names(feeds_df))
  print(feeds_df[, show_cols, drop = FALSE])
}

ttrss_logout(TTRSS_URL, sid)

if (total_ok == 0L) {
  stop("Не удалось добавить ни одного фида. Проверьте доступность источников и TT-RSS API.")
}
