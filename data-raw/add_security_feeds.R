## ============================================================
## data-raw/add_security_feeds.R
##
## Подписка на RSS-фиды по теме APT / Threat Intelligence
## через TT-RSS API.
## ============================================================

library(ttrssR)

TTRSS_URL  <- "http://localhost:8080"
TTRSS_USER <- "admin"
TTRSS_PASS <- "password"

# ── Источники по категориям ───────────────────────────────────────────────────

feeds <- list(

  # Threat Research от вендоров (первичные данные по APT)
  "Threat Research" = c(
    "https://securelist.com/feed/",                            # Kaspersky GReAT — лучший по APT/RU
    "https://unit42.paloaltonetworks.com/feed/",               # Unit 42 (Palo Alto)
    "https://blog.talosintelligence.com/feeds/posts/default",  # Cisco Talos
    "https://www.welivesecurity.com/feed/",                    # ESET Research
    "https://www.crowdstrike.com/blog/feed/",                  # CrowdStrike
    "https://www.microsoft.com/en-us/security/blog/feed/"      # Microsoft Threat Intelligence
  ),

  # Новости об атаках и кампаниях (EN)
  "Attack News (EN)" = c(
    "https://feeds.feedburner.com/TheHackersNews",             # The Hacker News
    "https://www.bleepingcomputer.com/feed/",                  # BleepingComputer
    "https://krebsonsecurity.com/feed/",                       # Krebs on Security
    "https://www.darkreading.com/rss.xml",                     # Dark Reading
    "https://www.securityweek.com/feed/"                       # SecurityWeek
  ),

  # Государственные / CERT предупреждения
  "CERT / Gov Alerts" = c(
    "https://www.cisa.gov/uscert/ncas/alerts.xml",             # US-CERT (CISA)
    "https://www.ncsc.gov.uk/api/1/services/v1/report-rss-feed.xml" # UK NCSC
  ),

  # Российские источники по APT и атакам
  "APT / Атаки (RU)" = c(
    "https://www.anti-malware.ru/rss.xml",                     # Anti-Malware.ru
    "https://www.securitylab.ru/rss/",                         # SecurityLab
    "https://habr.com/ru/rss/hub/information_security/articles/" # Хабр ИБ
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
      cat(sprintf("  [ERR] %s\n       %s\n", url, conditionMessage(e)))
      "err"
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
