## ============================================================  #cb-g-49
## data-raw/add_security_feeds.R  #cb-g-50
##  #cb-g-51
## Подписка на RSS-фиды по теме ИБ / Threat Intelligence  #cb-g-52
## через TT-RSS API. Удаляет фиды с заголовком [Unknown].  #cb-g-53
## ============================================================  #cb-g-54

library(ttrssR)  #cb-g-55

TTRSS_URL  <- Sys.getenv("TTRSS_URL", "http://localhost:8080")  #cb-g-56
TTRSS_USER <- Sys.getenv("TTRSS_USER", "admin")  #cb-g-57
TTRSS_PASS <- Sys.getenv("TTRSS_PASSWORD", "password")  #cb-g-58

# ── Источники ──────────────────────────────────────────────────────────────────  #cb-g-59

feeds <- list(  #cb-g-60

  # Исследования угроз — российские вендоры и блоги  #cb-g-61
  "Threat Research (RU)" = c(  #cb-g-62
    "https://securelist.ru/feed/",  #cb-g-63
    "https://www.kaspersky.ru/blog/feed/",  #cb-g-64
    "https://www.ptsecurity.com/ru-ru/about/news/rss/",  #cb-g-65
    "https://bi.zone/rss/blog/",  #cb-g-66
    "https://www.group-ib.ru/blog/feed/"  #cb-g-67
  ),  #cb-g-68

  # Новости ИБ — русскоязычные СМИ  #cb-g-69
  "ИБ-новости (RU)" = c(  #cb-g-70
    "https://www.anti-malware.ru/rss.xml",  #cb-g-71
    "https://xakep.ru/feed/",  #cb-g-72
    "https://www.securitylab.ru/rss/",  #cb-g-73
    "https://www.cnews.ru/inc/rss/cnews_security.xml"  #cb-g-74
  ),  #cb-g-75

  # Профессиональное сообщество (RU)  #cb-g-76
  "Сообщество (RU)" = c(  #cb-g-77
    "https://habr.com/ru/rss/hubs/infosecurity/articles/",  #cb-g-78
    "https://www.opennet.ru/opennews/opennews_all_noadv.rss"  #cb-g-79
  ),  #cb-g-80

  # Вендоры — исследования угроз (EN)  #cb-g-81
  "Threat Research (EN)" = c(  #cb-g-82
    "https://www.welivesecurity.com/en/feed/",  #cb-g-83
    "https://securelist.com/feed/",  #cb-g-84
    "https://unit42.paloaltonetworks.com/feed/",  #cb-g-85
    "https://research.checkpoint.com/feed/",  #cb-g-86
    "https://blog.talosintelligence.com/rss/",  #cb-g-87
    "https://www.microsoft.com/en-us/security/blog/feed/",  #cb-g-88
    "https://www.crowdstrike.com/blog/feed/",  #cb-g-89
    "https://www.sentinelone.com/blog/feed/",  #cb-g-90
    "https://news.sophos.com/en-us/feed/",  #cb-g-91
    "https://www.malwarebytes.com/blog/feed/",  #cb-g-92
    "https://feeds.trendmicro.com/TrendMicroResearch",  #cb-g-93
    "https://www.proofpoint.com/us/blog/rss.xml",  #cb-g-94
    "https://www.recordedfuture.com/blog/rss.xml",  #cb-g-95
    "https://blog.rapid7.com/rss/"  #cb-g-96
  ),  #cb-g-97

  # Новости ИБ — СМИ (EN)  #cb-g-98
  "Security News (EN)" = c(  #cb-g-99
    "https://feeds.feedburner.com/TheHackersNews",  #cb-g-100
    "https://www.bleepingcomputer.com/feed/",  #cb-g-101
    "https://www.securityweek.com/feed/",  #cb-g-102
    "https://www.darkreading.com/rss.xml",  #cb-g-103
    "https://cyberscoop.com/feed/",  #cb-g-104
    "https://securityaffairs.com/feed",  #cb-g-105
    "https://grahamcluley.com/feed/",  #cb-g-106
    "https://krebsonsecurity.com/feed/"  #cb-g-107
  ),  #cb-g-108

  # CERT / Advisories (EN)  #cb-g-109
  "CERT / Advisories (EN)" = c(
    "https://www.cisa.gov/uscert/ncas/alerts.xml",
    "https://isc.sans.edu/rssfeed_full.xml"
  )
)  #cb-g-110

# ── Подключение ────────────────────────────────────────────────────────────────  #cb-g-111

cat("Подключение к TT-RSS...\n")  #cb-g-112
sid <- ttrss_login(TTRSS_URL, TTRSS_USER, TTRSS_PASS)  #cb-g-113

# ── Очистка фидов с заголовком [Unknown] ──────────────────────────────────────  #cb-g-114

cat("\n── Поиск и удаление фидов [Unknown] ──\n")  #cb-g-115
existing <- tryCatch(ttrss_get_feeds(TTRSS_URL, sid, cat_id = -3L), error = function(e) data.frame())  #cb-g-116
if (nrow(existing) > 0 && "title" %in% names(existing)) {  #cb-g-117
  unknown_ids <- existing$id[existing$title == "[Unknown]"]  #cb-g-118
  if (length(unknown_ids) > 0) {  #cb-g-119
    for (fid in unknown_ids) {  #cb-g-120
      url_info <- if ("feed_url" %in% names(existing)) existing$feed_url[existing$id == fid] else fid  #cb-g-121
      tryCatch({  #cb-g-122
        ttrss_unsubscribe_feed(TTRSS_URL, sid, feed_id = as.integer(fid))  #cb-g-123
        cat(sprintf("  [DEL] id=%s  %s\n", fid, url_info))  #cb-g-124
      }, error = function(e) {  #cb-g-125
        cat(sprintf("  [ERR] id=%s: %s\n", fid, conditionMessage(e)))  #cb-g-126
      })  #cb-g-127
    }  #cb-g-128
  } else {  #cb-g-129
    cat("  Фиды [Unknown] не найдены.\n")  #cb-g-130
  }  #cb-g-131
}  #cb-g-132

# ── Подписка ──────────────────────────────────────────────────────────────────  #cb-g-133

total_ok  <- 0L  #cb-g-134
total_err <- 0L  #cb-g-135

for (cat_name in names(feeds)) {  #cb-g-136
  cat(sprintf("\n── Категория: %s ──\n", cat_name))  #cb-g-137

  for (url in feeds[[cat_name]]) {  #cb-g-138
    result <- tryCatch({  #cb-g-139
      ttrss_subscribe_feed(TTRSS_URL, sid, feed_url = url, category_id = 0L)  #cb-g-140
      cat(sprintf("  [OK]  %s\n", url))  #cb-g-141
      "ok"  #cb-g-142
    }, error = function(e) {  #cb-g-143
      msg    <- conditionMessage(e)  #cb-g-144
      msg_lc <- tolower(msg)  #cb-g-145
      if (grepl("already|exists|уже", msg_lc)) {  #cb-g-146
        cat(sprintf("  [SKIP] %s\n", url))  #cb-g-147
        "ok"  #cb-g-148
      } else {  #cb-g-149
        cat(sprintf("  [ERR] %s\n       %s\n", url, msg))  #cb-g-150
        "err"  #cb-g-151
      }  #cb-g-152
    })  #cb-g-153

    if (result == "ok") total_ok  <- total_ok  + 1L  #cb-g-154
    else                total_err <- total_err + 1L  #cb-g-155

    Sys.sleep(0.3)  #cb-g-156
  }  #cb-g-157
}  #cb-g-158

# ── Итог ──────────────────────────────────────────────────────────────────────  #cb-g-159

cat(sprintf(  #cb-g-160
  "\n=== Готово: добавлено/пропущено %d фидов, ошибок: %d ===\n",  #cb-g-161
  total_ok, total_err  #cb-g-162
))  #cb-g-163

cat("\nТекущие фиды в TT-RSS:\n")  #cb-g-164
feeds_df <- ttrss_get_feeds(TTRSS_URL, sid, cat_id = -3L)  #cb-g-165
if (nrow(feeds_df) > 0) {  #cb-g-166
  show_cols <- intersect(c("id", "title", "feed_url"), names(feeds_df))  #cb-g-167
  print(feeds_df[, show_cols, drop = FALSE])  #cb-g-168
}  #cb-g-169

ttrss_logout(TTRSS_URL, sid)  #cb-g-170

if (total_ok == 0L) {  #cb-g-171
  stop("Не удалось добавить ни одного фида. Проверьте доступность источников и TT-RSS API.")  #cb-g-172
}  #cb-g-173
