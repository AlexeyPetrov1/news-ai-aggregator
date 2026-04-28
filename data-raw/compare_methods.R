## ============================================================
## data-raw/compare_methods.R
##
## Сравнение методов классификации на одном наборе статей:
## - lda
## - kmeans
## - yandex_llm (если заданы Yandex env)
##
## Выход:
##   data/method_comparison.csv
##   data/method_comparison.rds
## ============================================================

suppressPackageStartupMessages({
  library(ttrssR)
  library(dplyr)
})

PKG_DIR <- Sys.getenv("PKG_DIR", getwd())
DATA_DIR <- file.path(PKG_DIR, "data")
INPUT_RDS <- Sys.getenv("COMPARE_INPUT_RDS", file.path(DATA_DIR, "news_raw.rds"))
N_TOPICS <- as.integer(Sys.getenv("N_TOPICS", "8"))
MAX_DOCS <- as.integer(Sys.getenv("COMPARE_MAX_DOCS", "300"))

methods <- c("lda", "kmeans")
if (nzchar(Sys.getenv("YANDEX_CLOUD_API_KEY", "")) &&
    nzchar(Sys.getenv("YANDEX_CLOUD_FOLDER", ""))) {
  methods <- c(methods, "yandex_llm")
}

if (!file.exists(INPUT_RDS)) {
  stop("Не найден входной файл: ", INPUT_RDS)
}

dir.create(DATA_DIR, showWarnings = FALSE, recursive = TRUE)

message("=== Сравнение методов классификации ===")
message("Вход: ", INPUT_RDS)
message("Методы: ", paste(methods, collapse = ", "))

df <- readRDS(INPUT_RDS)
if (!"content_text" %in% names(df)) stop("В датасете нет колонки content_text")
if (nrow(df) == 0L) stop("Пустой входной датасет")

if (nrow(df) > MAX_DOCS) {
  set.seed(42)
  df <- df[sample.int(nrow(df), MAX_DOCS), , drop = FALSE]
  message("Сэмплирование до ", nrow(df), " статей")
}

run_one <- function(method_name) {
  message("\n--- Метод: ", method_name, " ---")
  started <- Sys.time()

  classified <- classify_news(
    df,
    method = method_name,
    n_topics = N_TOPICS,
    compute_quality = TRUE
  )
  metrics <- attr(classified, "topic_quality")
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))

  data.frame(
    method = method_name,
    n_documents = metrics$n_documents,
    n_labeled = metrics$n_labeled,
    label_coverage = round(metrics$label_coverage, 4),
    n_topics = metrics$n_topics,
    dominant_topic_share = round(metrics$dominant_topic_share, 4),
    topic_balance_entropy = round(metrics$topic_balance_entropy, 4),
    topic_distinctiveness = round(metrics$topic_distinctiveness, 4),
    elapsed_sec = round(elapsed, 2),
    stringsAsFactors = FALSE
  )
}

comparison <- bind_rows(lapply(methods, run_one))

csv_path <- file.path(DATA_DIR, "method_comparison.csv")
rds_path <- file.path(DATA_DIR, "method_comparison.rds")
write.csv(comparison, csv_path, row.names = FALSE, fileEncoding = "UTF-8")
saveRDS(comparison, rds_path)

message("\n=== Готово ===")
print(comparison)
message("CSV: ", csv_path)
message("RDS: ", rds_path)
