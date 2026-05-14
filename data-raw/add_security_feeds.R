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
# ── Источники по категориям (только русскоязычные) ───────────────────────────  #contrib-balance-k-1123
  #contrib-balance-k-1124
feeds <- list(  #contrib-balance-k-1125
  #contrib-balance-k-1126
  # Исследования угроз — российские вендоры  #contrib-balance-k-1127
  "Threat Research (RU)" = c(  #contrib-balance-k-1128
    "https://securelist.ru/feed/",                                    # Kaspersky GReAT (рус.)  #contrib-balance-k-1129
    "https://www.kaspersky.ru/blog/feed/",                            # Kaspersky блог  #contrib-balance-k-1130
    "https://www.ptsecurity.com/ru-ru/about/news/rss/"               # Positive Technologies  #contrib-balance-k-1131
  ),  #contrib-balance-k-1132
  #contrib-balance-k-1133
  # Новости ИБ — русскоязычные СМИ  #contrib-balance-k-1134
  "ИБ-новости (RU)" = c(  #contrib-balance-k-1135
    "https://www.anti-malware.ru/rss.xml",                            # Anti-Malware.ru  #contrib-balance-k-1136
    "https://www.securitylab.ru/rss/",                                # SecurityLab  #contrib-balance-k-1137
    "https://xakep.ru/feed/",                                         # Хакер.ру  #contrib-balance-k-1138
    "https://cisoclub.ru/feed/"                                       # CISO Club  #contrib-balance-k-1139
  ),  #contrib-balance-k-1140
  #contrib-balance-k-1141
  # Профессиональное сообщество  #contrib-balance-k-1142
  "Сообщество (RU)" = c(  #contrib-balance-k-1143
    "https://habr.com/ru/rss/hub/information_security/articles/",     # Хабр — ИБ  #contrib-balance-k-1144
    "https://habr.com/ru/rss/hub/netsecurity/articles/"               # Хабр — сетевая безопасность  #contrib-balance-k-1145
  ),  #contrib-balance-k-1146
  #contrib-balance-k-1147
  # Государственные / CERT  #contrib-balance-k-1148
  "CERT / Регуляторы (RU)" = c(  #contrib-balance-k-1149
    "https://bdu.fstec.ru/news/rss",                                  # БДУ ФСТЭК  #contrib-balance-k-1150
    "https://safe-surf.ru/rss/"                                       # SafeSurf (НКЦКИ)  #contrib-balance-k-1151
  )  #contrib-balance-k-1152
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
