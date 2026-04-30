## ============================================================
## data-raw/fetch_news.R
##
## Скрипт сбора новостей через TT-RSS API.
## Результат сохраняется в data/news_raw.rds и data/news_raw.csv
## ============================================================

library(ttrssR)
library(dplyr)

# ── Параметры ─────────────────────────────────────────────────────────────────

TTRSS_URL       <- Sys.getenv("TTRSS_URL",       "http://localhost:8080")
TTRSS_USER      <- Sys.getenv("TTRSS_USER",      "admin")
TTRSS_PASSWORD  <- Sys.getenv("TTRSS_PASSWORD",  "password")
MAX_ARTICLES    <- as.integer(Sys.getenv("MAX_ARTICLES",    "500"))
CLASSIFY_METHOD <- Sys.getenv("CLASSIFY_METHOD", "lda")
N_TOPICS        <- as.integer(Sys.getenv("N_TOPICS",        "8"))
USE_CLICKHOUSE  <- nzchar(Sys.getenv("CH_HOST",  ""))

PKG_DIR  <- getwd()
DATA_DIR <- file.path(PKG_DIR, "data")

# ── Шаг 1: Сбор новостей ─────────────────────────────────────────────────────

message("=== Шаг 1: Сбор новостей из TT-RSS ===")
message(sprintf("URL: %s  |  макс. статей: %d", TTRSS_URL, MAX_ARTICLES))

news_df <- fetch_news_dataframe(
  base_url     = TTRSS_URL,
  user         = TTRSS_USER,
  password     = TTRSS_PASSWORD,
  max_articles = MAX_ARTICLES,
  batch_size   = 200L
)

if (nrow(news_df) == 0L) {
  warning("TT-RSS пока не вернул статей; пропускаем цикл без ошибки.")
  quit(save = "no", status = 0L)
}

message(sprintf("Получено статей: %d", nrow(news_df)))
message(sprintf("Колонки: %s", paste(names(news_df), collapse = ", ")))

if ("published_at" %in% names(news_df)) {
  message(sprintf("Период: %s — %s",
    format(min(news_df$published_at, na.rm = TRUE), "%Y-%m-%d"),
    format(max(news_df$published_at, na.rm = TRUE), "%Y-%m-%d")))
}

# Быстрая статистика по источникам
if ("feed_title" %in% names(news_df)) {
  src <- news_df |> count(feed_title, sort = TRUE)
  message("\nСтатей по источникам:")
  print(as.data.frame(src), row.names = FALSE)
}

# ── Шаг 2: Тематическая классификация ────────────────────────────────────────

message(sprintf("\n=== Шаг 2: Классификация (метод: %s, тем: %d) ===",
                CLASSIFY_METHOD, N_TOPICS))

news_classified <- tryCatch(
  classify_news(
    df          = news_df,
    n_topics    = N_TOPICS,
    method      = CLASSIFY_METHOD
  ),
  error = function(e) {
    message("Классификация не удалась: ", conditionMessage(e))
    message("Сохраняем без классификации.")
    news_df
  }
)

if ("topic_label" %in% names(news_classified)) {
  top_topics <- news_classified |>
    filter(!is.na(topic_label), nchar(topic_label) > 0) |>
    count(topic_label, sort = TRUE) |>
    head(5)
  message("\nТоп-5 тем:")
  print(as.data.frame(top_topics), row.names = FALSE)
}

# ── Шаг 3: Сохранение ────────────────────────────────────────────────────────

message(sprintf("\n=== Шаг 3: Сохранение в %s ===", DATA_DIR))
dir.create(DATA_DIR, showWarnings = FALSE, recursive = TRUE)

saveRDS(news_classified, file.path(DATA_DIR, "news_raw.rds"))
write.csv(news_classified,
          file.path(DATA_DIR, "news_raw.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")

message(sprintf("Сохранено: %d статей -> data/news_raw.rds + .csv", nrow(news_classified)))

# ── Шаг 4: ClickHouse (если настроен) ────────────────────────────────────────

if (USE_CLICKHOUSE) {
  message("\n=== Шаг 4: Запись в ClickHouse ===")
  tryCatch({
    con <- ch_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    ch_init_schema(con)
    ch_write_articles(con, news_classified)
    message("ClickHouse: запись завершена.")
  }, error = function(e) message("ClickHouse ошибка: ", conditionMessage(e)))
} else {
  message("\nClickHouse пропущен (CH_HOST не задан).")
}

# ── Финальный glimpse ─────────────────────────────────────────────────────────

message("\n=== Готово. Структура датафрейма: ===")
dplyr::glimpse(news_classified)
