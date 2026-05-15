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
# ── Источники: русскоязычные + англоязычные (высокий объём) ──────────────────
feeds <- list(

  # Исследования угроз — российские вендоры
  "Threat Research (RU)" = c(
    "https://securelist.ru/feed/",
    "https://www.kaspersky.ru/blog/feed/",
    "https://www.ptsecurity.com/ru-ru/about/news/rss/"
  ),

  # Новости ИБ — русскоязычные СМИ
  "ИБ-новости (RU)" = c(
    "https://www.anti-malware.ru/rss.xml",
    "https://www.securitylab.ru/rss/",
    "https://xakep.ru/feed/",
    "https://cisoclub.ru/feed/"
  ),

  # Профессиональное сообщество (RU)
  "Сообщество (RU)" = c(
    "https://habr.com/ru/rss/hub/information_security/articles/",
    "https://habr.com/ru/rss/hub/netsecurity/articles/"
  ),

  # CERT / Регуляторы (RU)
  "CERT / Регуляторы (RU)" = c(
    "https://bdu.fstec.ru/news/rss",
    "https://safe-surf.ru/rss/"
  ),

  # Новости ИБ — высокообъёмные английские СМИ
  "Security News (EN)" = c(
    "https://feeds.feedburner.com/TheHackersNews",
    "https://www.bleepingcomputer.com/feed/",
    "https://www.securityweek.com/feed/",
    "https://www.darkreading.com/rss.xml",
    "https://cyberscoop.com/feed/",
    "https://www.infosecurity-magazine.com/rss/news/",
    "https://grahamcluley.com/feed/"
  ),

  # Threat Research — вендоры (EN)
  "Threat Research (EN)" = c(
    "https://krebsonsecurity.com/feed/",
    "https://www.malwarebytes.com/blog/feed/",
    "https://news.sophos.com/en-us/feed/",
    "https://blog.talosintelligence.com/rss/",
    "https://unit42.paloaltonetworks.com/feed/",
    "https://securelist.com/feed/",
    "https://research.checkpoint.com/feed/"
  ),

  # CERT / Advisories (EN)
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
