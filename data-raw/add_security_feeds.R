## ============================================================
## data-raw/add_security_feeds.R
##
## Подписка на RSS-фиды по теме ИБ / Threat Intelligence
## через TT-RSS API. Удаляет фиды с заголовком [Unknown].
## ============================================================

library(ttrssR)

TTRSS_URL  <- Sys.getenv("TTRSS_URL", "http://localhost:8080")
TTRSS_USER <- Sys.getenv("TTRSS_USER", "admin")
TTRSS_PASS <- Sys.getenv("TTRSS_PASSWORD", "password")

# ── Источники ──────────────────────────────────────────────────────────────────

feeds <- list(

  # Исследования угроз — российские вендоры и блоги
  "Threat Research (RU)" = c(
    "https://securelist.ru/feed/",
    "https://www.kaspersky.ru/blog/feed/",
    "https://www.ptsecurity.com/ru-ru/about/news/rss/",
    "https://bi.zone/rss/blog/",
    "https://www.group-ib.ru/blog/feed/"
  ),

  # Новости ИБ — русскоязычные СМИ
  "ИБ-новости (RU)" = c(
    "https://www.anti-malware.ru/rss.xml",
    "https://xakep.ru/feed/",
    "https://www.securitylab.ru/rss/",
    "https://www.cnews.ru/inc/rss/cnews_security.xml"
  ),

  # Профессиональное сообщество (RU)
  "Сообщество (RU)" = c(
    "https://habr.com/ru/rss/hubs/infosecurity/articles/",
    "https://www.opennet.ru/opennews/opennews_all_noadv.rss"
  ),

  # Вендоры — исследования угроз (EN)
  "Threat Research (EN)" = c(
    "https://www.welivesecurity.com/en/feed/",
    "https://securelist.com/feed/",
    "https://unit42.paloaltonetworks.com/feed/",
    "https://research.checkpoint.com/feed/",
    "https://blog.talosintelligence.com/rss/",
    "https://www.microsoft.com/en-us/security/blog/feed/",
    "https://www.crowdstrike.com/blog/feed/",
    "https://www.sentinelone.com/blog/feed/",
    "https://news.sophos.com/en-us/feed/",
    "https://www.malwarebytes.com/blog/feed/",
    "https://feeds.trendmicro.com/TrendMicroResearch",
    "https://www.proofpoint.com/us/blog/rss.xml",
    "https://www.recordedfuture.com/blog/rss.xml",
    "https://blog.rapid7.com/rss/"
  ),

  # Новости ИБ — СМИ (EN)
  "Security News (EN)" = c(
    "https://feeds.feedburner.com/TheHackersNews",
    "https://www.bleepingcomputer.com/feed/",
    "https://www.securityweek.com/feed/",
    "https://www.darkreading.com/rss.xml",
    "https://cyberscoop.com/feed/",
    "https://securityaffairs.com/feed",
    "https://grahamcluley.com/feed/",
    "https://krebsonsecurity.com/feed/"
  ),

  # CERT / Advisories (EN)
  "CERT / Advisories (EN)" = c(
    "https://www.cisa.gov/uscert/ncas/alerts.xml",
    "https://isc.sans.edu/rssfeed_full.xml"
  )
)

# ── Подключение ────────────────────────────────────────────────────────────────

cat("Подключение к TT-RSS...\n")
sid <- ttrss_login(TTRSS_URL, TTRSS_USER, TTRSS_PASS)

# ── Очистка фидов с заголовком [Unknown] ──────────────────────────────────────

cat("\n── Поиск и удаление фидов [Unknown] ──\n")
existing <- tryCatch(ttrss_get_feeds(TTRSS_URL, sid, cat_id = -3L), error = function(e) data.frame())
if (nrow(existing) > 0 && "title" %in% names(existing)) {
  unknown_ids <- existing$id[existing$title == "[Unknown]"]
  if (length(unknown_ids) > 0) {
    for (fid in unknown_ids) {
      url_info <- if ("feed_url" %in% names(existing)) existing$feed_url[existing$id == fid] else fid
      tryCatch({
        ttrss_unsubscribe_feed(TTRSS_URL, sid, feed_id = as.integer(fid))
        cat(sprintf("  [DEL] id=%s  %s\n", fid, url_info))
      }, error = function(e) {
        cat(sprintf("  [ERR] id=%s: %s\n", fid, conditionMessage(e)))
      })
    }
  } else {
    cat("  Фиды [Unknown] не найдены.\n")
  }
}

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
      msg    <- conditionMessage(e)
      msg_lc <- tolower(msg)
      if (grepl("already|exists|уже", msg_lc)) {
        cat(sprintf("  [SKIP] %s\n", url))
        "ok"
      } else {
        cat(sprintf("  [ERR] %s\n       %s\n", url, msg))
        "err"
      }
    })

    if (result == "ok") total_ok  <- total_ok  + 1L
    else                total_err <- total_err + 1L

    Sys.sleep(0.3)
  }
}

# ── Итог ──────────────────────────────────────────────────────────────────────

cat(sprintf(
  "\n=== Готово: добавлено/пропущено %d фидов, ошибок: %d ===\n",
  total_ok, total_err
))

cat("\nТекущие фиды в TT-RSS:\n")
feeds_df <- ttrss_get_feeds(TTRSS_URL, sid, cat_id = -3L)
if (nrow(feeds_df) > 0) {
  show_cols <- intersect(c("id", "title", "feed_url"), names(feeds_df))
  print(feeds_df[, show_cols, drop = FALSE])
}

ttrss_logout(TTRSS_URL, sid)

if (total_ok == 0L) {
  stop("Не удалось добавить ни одного фида. Проверьте доступность источников и TT-RSS API.")
}
