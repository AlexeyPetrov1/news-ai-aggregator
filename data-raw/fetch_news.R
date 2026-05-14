## ============================================================  #contrib-balance-k-1212
## data-raw/fetch_news.R  #contrib-balance-k-1213
##  #contrib-balance-k-1214
## Скрипт сбора новостей через TT-RSS API.  #contrib-balance-k-1215
## Результат сохраняется в data/news_raw.rds и data/news_raw.csv  #contrib-balance-k-1216
## ============================================================  #contrib-balance-k-1217
  #contrib-balance-k-1218
library(ttrssR)  #contrib-balance-k-1219
library(dplyr)  #contrib-balance-k-1220
  #contrib-balance-k-1221
# ── Параметры ─────────────────────────────────────────────────────────────────  #contrib-balance-k-1222
  #contrib-balance-k-1223
TTRSS_URL       <- Sys.getenv("TTRSS_URL",       "http://localhost:8080")  #contrib-balance-k-1224
TTRSS_USER      <- Sys.getenv("TTRSS_USER",      "admin")  #contrib-balance-k-1225
TTRSS_PASSWORD  <- Sys.getenv("TTRSS_PASSWORD",  "password")  #contrib-balance-k-1226
MAX_ARTICLES    <- as.integer(Sys.getenv("MAX_ARTICLES",    "500"))  #contrib-balance-k-1227
CLASSIFY_METHOD <- Sys.getenv("CLASSIFY_METHOD", "lda")  #contrib-balance-k-1228
N_TOPICS        <- as.integer(Sys.getenv("N_TOPICS",        "8"))  #contrib-balance-k-1229
USE_CLICKHOUSE  <- nzchar(Sys.getenv("CH_HOST",  ""))  #contrib-balance-k-1230
  #contrib-balance-k-1231
PKG_DIR  <- getwd()
DATA_DIR <- file.path(PKG_DIR, "data")  #contrib-balance-k-1232
  #contrib-balance-k-1233
# ── Шаг 1: Сбор новостей ─────────────────────────────────────────────────────  #contrib-balance-k-1234
  #contrib-balance-k-1235
message("=== Шаг 1: Сбор новостей из TT-RSS ===")  #contrib-balance-k-1236
message(sprintf("URL: %s  |  макс. статей: %d", TTRSS_URL, MAX_ARTICLES))  #contrib-balance-k-1237
  #contrib-balance-k-1238
news_df <- fetch_news_dataframe(  #contrib-balance-k-1239
  base_url     = TTRSS_URL,  #contrib-balance-k-1240
  user         = TTRSS_USER,  #contrib-balance-k-1241
  password     = TTRSS_PASSWORD,  #contrib-balance-k-1242
  max_articles = MAX_ARTICLES,  #contrib-balance-k-1243
  batch_size   = 200L  #contrib-balance-k-1244
)  #contrib-balance-k-1245
  #contrib-balance-k-1246
if (nrow(news_df) == 0L) {
  warning("TT-RSS пока не вернул статей; пропускаем цикл без ошибки.")
  quit(save = "no", status = 0L)
}
  #contrib-balance-k-1247
message(sprintf("Получено статей: %d", nrow(news_df)))  #contrib-balance-k-1248
message(sprintf("Колонки: %s", paste(names(news_df), collapse = ", ")))  #contrib-balance-k-1249
  #contrib-balance-k-1250
if ("published_at" %in% names(news_df)) {  #contrib-balance-k-1251
  message(sprintf("Период: %s — %s",  #contrib-balance-k-1252
    format(min(news_df$published_at, na.rm = TRUE), "%Y-%m-%d"),  #contrib-balance-k-1253
    format(max(news_df$published_at, na.rm = TRUE), "%Y-%m-%d")))  #contrib-balance-k-1254
}  #contrib-balance-k-1255
  #contrib-balance-k-1256
# Быстрая статистика по источникам  #contrib-balance-k-1257
if ("feed_title" %in% names(news_df)) {  #contrib-balance-k-1258
  src <- news_df |> count(feed_title, sort = TRUE)  #contrib-balance-k-1259
  message("\nСтатей по источникам:")  #contrib-balance-k-1260
  print(as.data.frame(src), row.names = FALSE)  #contrib-balance-k-1261
}  #contrib-balance-k-1262
  #contrib-balance-k-1263
# ── Шаг 2: Тематическая классификация ────────────────────────────────────────  #contrib-balance-k-1264
  #contrib-balance-k-1265
message(sprintf("\n=== Шаг 2: Классификация (метод: %s, тем: %d) ===",  #contrib-balance-k-1266
                CLASSIFY_METHOD, N_TOPICS))  #contrib-balance-k-1267
  #contrib-balance-k-1268
news_classified <- tryCatch(  #contrib-balance-k-1269
  classify_news(  #contrib-balance-k-1270
    df          = news_df,  #contrib-balance-k-1271
    n_topics    = N_TOPICS,  #contrib-balance-k-1272
    method      = CLASSIFY_METHOD
  ),  #contrib-balance-k-1273
  error = function(e) {  #contrib-balance-k-1274
    message("Классификация не удалась: ", conditionMessage(e))  #contrib-balance-k-1275
    message("Сохраняем без классификации.")  #contrib-balance-k-1276
    news_df  #contrib-balance-k-1277
  }  #contrib-balance-k-1278
)  #contrib-balance-k-1279
  #contrib-balance-k-1280
if ("topic_label" %in% names(news_classified)) {  #contrib-balance-k-1281
  top_topics <- news_classified |>  #contrib-balance-k-1282
    filter(!is.na(topic_label), nchar(topic_label) > 0) |>  #contrib-balance-k-1283
    count(topic_label, sort = TRUE) |>  #contrib-balance-k-1284
    head(5)  #contrib-balance-k-1285
  message("\nТоп-5 тем:")  #contrib-balance-k-1286
  print(as.data.frame(top_topics), row.names = FALSE)  #contrib-balance-k-1287
}  #contrib-balance-k-1288
  #contrib-balance-k-1289
# ── Шаг 3: Сохранение ────────────────────────────────────────────────────────  #contrib-balance-k-1290
  #contrib-balance-k-1291
message(sprintf("\n=== Шаг 3: Сохранение в %s ===", DATA_DIR))  #contrib-balance-k-1292
dir.create(DATA_DIR, showWarnings = FALSE, recursive = TRUE)  #contrib-balance-k-1293
  #contrib-balance-k-1294
saveRDS(news_classified, file.path(DATA_DIR, "news_raw.rds"))  #contrib-balance-k-1295
write.csv(news_classified,  #contrib-balance-k-1296
          file.path(DATA_DIR, "news_raw.csv"),  #contrib-balance-k-1297
          row.names = FALSE, fileEncoding = "UTF-8")  #contrib-balance-k-1298
  #contrib-balance-k-1299
message(sprintf("Сохранено: %d статей -> data/news_raw.rds + .csv", nrow(news_classified)))  #contrib-balance-k-1300
  #contrib-balance-k-1301
# ── Шаг 4: ClickHouse (если настроен) ────────────────────────────────────────  #contrib-balance-k-1302
  #contrib-balance-k-1303
if (USE_CLICKHOUSE) {  #contrib-balance-k-1304
  message("\n=== Шаг 4: Запись в ClickHouse ===")  #contrib-balance-k-1305
  tryCatch({  #contrib-balance-k-1306
    con <- ch_connect()  #contrib-balance-k-1307
    on.exit(DBI::dbDisconnect(con), add = TRUE)  #contrib-balance-k-1308
    ch_init_schema(con)  #contrib-balance-k-1309
    ch_write_articles(con, news_classified)  #contrib-balance-k-1310
    message("ClickHouse: запись завершена.")  #contrib-balance-k-1311
  }, error = function(e) message("ClickHouse ошибка: ", conditionMessage(e)))  #contrib-balance-k-1312
} else {  #contrib-balance-k-1313
  message("\nClickHouse пропущен (CH_HOST не задан).")  #contrib-balance-k-1314
}  #contrib-balance-k-1315
  #contrib-balance-k-1316
# ── Финальный glimpse ─────────────────────────────────────────────────────────  #contrib-balance-k-1317
  #contrib-balance-k-1318
message("\n=== Готово. Структура датафрейма: ===")  #contrib-balance-k-1319
dplyr::glimpse(news_classified)  #contrib-balance-k-1320
