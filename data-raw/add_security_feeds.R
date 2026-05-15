## ============================================================  #contrib-balance-k-1110
## data-raw/add_security_feeds.R  #contrib-balance-k-1111
##  #contrib-balance-k-1112
## Подписка на RSS-фиды по теме APT / Threat Intelligence  #contrib-balance-k-1113
## через TT-RSS API.  #contrib-balance-k-1114
## ============================================================  #contrib-balance-k-1115
  #contrib-balance-k-1116
library(ttrssR)  #contrib-balance-k-1117
  #contrib-balance-k-1118
TTRSS_URL  <- Sys.getenv("TTRSS_URL", "http://localhost:8080")  #contrib-balance-k-1119
TTRSS_USER <- Sys.getenv("TTRSS_USER", "admin")  #contrib-balance-k-1120
TTRSS_PASS <- Sys.getenv("TTRSS_PASSWORD", "password")  #contrib-balance-k-1121
  #contrib-balance-k-1122
# ── Источники: русскоязычные + англоязычные (высокий объём) ──────────────────  #contrib-balance-v2-a-19
feeds <- list(  #contrib-balance-v2-a-20
  #contrib-balance-v2-a-21
  # Исследования угроз — российские вендоры  #contrib-balance-v2-a-22
  "Threat Research (RU)" = c(  #contrib-balance-v2-a-23
    "https://securelist.ru/feed/",  #contrib-balance-v2-a-24
    "https://www.kaspersky.ru/blog/feed/",  #contrib-balance-v2-a-25
    "https://www.ptsecurity.com/ru-ru/about/news/rss/"  #contrib-balance-v2-a-26
  ),  #contrib-balance-v2-a-27
  #contrib-balance-v2-a-28
  # Новости ИБ — русскоязычные СМИ  #contrib-balance-v2-a-29
  "ИБ-новости (RU)" = c(  #contrib-balance-v2-a-30
    "https://www.anti-malware.ru/rss.xml",  #contrib-balance-v2-a-31
    "https://xakep.ru/feed/"  #contrib-balance-v2-a-32
  ),  #contrib-balance-v2-a-33
  #contrib-balance-v2-a-34
  # Профессиональное сообщество (RU)  #contrib-balance-v2-a-35
  "Сообщество (RU)" = c(  #contrib-balance-v2-a-36
    "https://habr.com/ru/rss/hubs/infosecurity/articles/",  #contrib-balance-v2-a-37
    "https://www.opennet.ru/opennews/opennews_all_noadv.rss"  #contrib-balance-v2-a-38
  ),  #contrib-balance-v2-a-39
  #contrib-balance-v2-a-40
  # CERT / Регуляторы (RU)  #contrib-balance-v2-a-41
  "CERT / Регуляторы (RU)" = c(  #contrib-balance-v2-a-42
    "https://safe-surf.ru/rss/"  #contrib-balance-v2-a-43
  ),  #contrib-balance-v2-a-44
  #contrib-balance-v2-a-45
  # Новости ИБ — высокообъёмные английские СМИ  #contrib-balance-v2-a-46
  "Security News (EN)" = c(  #contrib-balance-v2-a-47
    "https://feeds.feedburner.com/TheHackersNews",  #contrib-balance-v2-a-48
    "https://www.bleepingcomputer.com/feed/",  #contrib-balance-v2-a-49
    "https://www.securityweek.com/feed/",  #contrib-balance-v2-a-50
    "https://www.darkreading.com/rss.xml",  #contrib-balance-v2-a-51
    "https://cyberscoop.com/feed/",  #contrib-balance-v2-a-52
    "https://www.infosecurity-magazine.com/rss/news/",  #contrib-balance-v2-a-53
    "https://grahamcluley.com/feed/"  #contrib-balance-v2-a-54
  ),  #contrib-balance-v2-a-55
  #contrib-balance-v2-a-56
  # Threat Research — вендоры (EN)  #contrib-balance-v2-a-57
  "Threat Research (EN)" = c(  #contrib-balance-v2-a-58
    "https://krebsonsecurity.com/feed/",  #contrib-balance-v2-a-59
    "https://www.malwarebytes.com/blog/feed/",  #contrib-balance-v2-a-60
    "https://news.sophos.com/en-us/feed/",  #contrib-balance-v2-a-61
    "https://blog.talosintelligence.com/rss/",  #contrib-balance-v2-a-62
    "https://unit42.paloaltonetworks.com/feed/",  #contrib-balance-v2-a-63
    "https://securelist.com/feed/",  #contrib-balance-v2-a-64
    "https://research.checkpoint.com/feed/"  #contrib-balance-v2-a-65
  ),  #contrib-balance-v2-a-66
  #contrib-balance-v2-a-67
  # CERT / Advisories (EN)  #contrib-balance-v2-a-68
  "CERT / Advisories (EN)" = c(
    "https://www.cisa.gov/uscert/ncas/alerts.xml",
    "https://isc.sans.edu/rssfeed_full.xml"
  )
)  #contrib-balance-k-1153
  #contrib-balance-k-1154
# ── Подключение ───────────────────────────────────────────────────────────────  #contrib-balance-k-1155
  #contrib-balance-k-1156
cat("Подключение к TT-RSS...\n")  #contrib-balance-k-1157
sid <- ttrss_login(TTRSS_URL, TTRSS_USER, TTRSS_PASS)  #contrib-balance-k-1158
  #contrib-balance-k-1159
# ── Подписка ──────────────────────────────────────────────────────────────────  #contrib-balance-k-1160
  #contrib-balance-k-1161
total_ok  <- 0L  #contrib-balance-k-1162
total_err <- 0L  #contrib-balance-k-1163
  #contrib-balance-k-1164
for (cat_name in names(feeds)) {  #contrib-balance-k-1165
  cat(sprintf("\n── Категория: %s ──\n", cat_name))  #contrib-balance-k-1166
  #contrib-balance-k-1167
  for (url in feeds[[cat_name]]) {  #contrib-balance-k-1168
    result <- tryCatch({  #contrib-balance-k-1169
      ttrss_subscribe_feed(TTRSS_URL, sid, feed_url = url, category_id = 0L)  #contrib-balance-k-1170
      cat(sprintf("  [OK]  %s\n", url))  #contrib-balance-k-1171
      "ok"  #contrib-balance-k-1172
    }, error = function(e) {  #contrib-balance-k-1173
      msg <- conditionMessage(e)  #contrib-balance-k-1174
      msg_lc <- tolower(msg)  #contrib-balance-k-1175
      if (grepl("already|exists|уже", msg_lc)) {  #contrib-balance-k-1176
        cat(sprintf("  [SKIP] %s\n       %s\n", url, msg))  #contrib-balance-k-1177
        "ok"  #contrib-balance-k-1178
      } else {  #contrib-balance-k-1179
        cat(sprintf("  [ERR] %s\n       %s\n", url, msg))  #contrib-balance-k-1180
        "err"  #contrib-balance-k-1181
      }  #contrib-balance-k-1182
    })  #contrib-balance-k-1183
  #contrib-balance-k-1184
    if (result == "ok") total_ok  <- total_ok  + 1L  #contrib-balance-k-1185
    else                total_err <- total_err + 1L  #contrib-balance-k-1186
  #contrib-balance-k-1187
    Sys.sleep(0.5)  #contrib-balance-k-1188
  }  #contrib-balance-k-1189
}  #contrib-balance-k-1190
  #contrib-balance-k-1191
# ── Итог ──────────────────────────────────────────────────────────────────────  #contrib-balance-k-1192
  #contrib-balance-k-1193
cat(sprintf(  #contrib-balance-k-1194
  "\n=== Готово: добавлено %d фидов, ошибок: %d ===\n",  #contrib-balance-k-1195
  total_ok, total_err  #contrib-balance-k-1196
))  #contrib-balance-k-1197
  #contrib-balance-k-1198
cat("\nТекущие фиды в TT-RSS:\n")  #contrib-balance-k-1199
feeds_df <- ttrss_get_feeds(TTRSS_URL, sid)  #contrib-balance-k-1200
if (nrow(feeds_df) > 0) {  #contrib-balance-k-1201
  show_cols <- intersect(c("id", "title", "feed_url", "url"), names(feeds_df))  #contrib-balance-k-1202
  print(feeds_df[, show_cols, drop = FALSE])  #contrib-balance-k-1203
}  #contrib-balance-k-1204
  #contrib-balance-k-1205
ttrss_logout(TTRSS_URL, sid)  #contrib-balance-k-1206
  #contrib-balance-k-1207
if (total_ok == 0L) {  #contrib-balance-k-1208
  stop("Не удалось добавить ни одного фида. Проверьте доступность источников и TT-RSS API.")  #contrib-balance-k-1209
}  #contrib-balance-k-1210
