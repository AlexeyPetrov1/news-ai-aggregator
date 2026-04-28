## ============================================================
## data-raw/mini_ground_truth_workflow.R
##
## Минимальный workflow для:
## 1) формирования выборки под ручную разметку (ground-truth)
## 2) применения canonical mapping
## 3) расчета supervised-метрик (accuracy/macro-F1)
## ============================================================

suppressPackageStartupMessages({
  library(ttrssR)
  library(dplyr)
})

PKG_DIR <- Sys.getenv("PKG_DIR", getwd())
DATA_DIR <- file.path(PKG_DIR, "data")
INPUT_RDS <- Sys.getenv("GROUND_TRUTH_INPUT_RDS", file.path(DATA_DIR, "news_raw.rds"))

TEMPLATE_CSV <- file.path(DATA_DIR, "ground_truth_template.csv")
MAPPING_CSV <- Sys.getenv(
  "CANONICAL_MAPPING_CSV",
  file.path(PKG_DIR, "data-raw", "canonical_topic_mapping_template.csv")
)
LABELED_CSV <- file.path(DATA_DIR, "ground_truth_labeled.csv")
REPORT_CSV <- file.path(DATA_DIR, "ground_truth_metrics.csv")
REPORT_RDS <- file.path(DATA_DIR, "ground_truth_metrics.rds")

if (!file.exists(INPUT_RDS)) stop("Не найден входной файл: ", INPUT_RDS)

dir.create(DATA_DIR, recursive = TRUE, showWarnings = FALSE)
df <- readRDS(INPUT_RDS)

if (!file.exists(TEMPLATE_CSV)) {
  message("Шаг 1: создаем шаблон для ручной разметки -> ", TEMPLATE_CSV)
  create_ground_truth_sample(df, n = 200L, output_path = TEMPLATE_CSV, seed = 42L)
  message("Откройте CSV, заполните колонку topic_true и сохраните как ", LABELED_CSV)
  quit(save = "no", status = 0L)
}

if (!file.exists(LABELED_CSV)) {
  message("Шаг 1 уже выполнен. Не найден файл ручной разметки: ", LABELED_CSV)
  message("Скопируйте шаблон и заполните topic_true, затем перезапустите скрипт.")
  quit(save = "no", status = 0L)
}

if (!file.exists(MAPPING_CSV)) stop("Не найден mapping CSV: ", MAPPING_CSV)

message("Шаг 2: считаем метрики на размеченном наборе")
labeled <- utils::read.csv(LABELED_CSV, stringsAsFactors = FALSE)
mapping <- utils::read.csv(MAPPING_CSV, stringsAsFactors = FALSE)
labeled <- apply_canonical_label_mapping(
  labeled,
  mapping = mapping,
  source_col = "topic_label",
  target_col = "topic_canonical",
  unknown_label = "Other"
)

metrics <- evaluate_against_ground_truth(
  labeled,
  truth_col = "topic_true",
  pred_col = "topic_canonical"
)

summary_df <- data.frame(
  n_labeled = metrics$n_labeled,
  accuracy = round(metrics$accuracy, 4),
  macro_f1 = round(metrics$macro_f1, 4),
  stringsAsFactors = FALSE
)
utils::write.csv(summary_df, REPORT_CSV, row.names = FALSE, fileEncoding = "UTF-8")
saveRDS(metrics, REPORT_RDS)

message("=== Готово ===")
print(summary_df)
message("Подробные per-class метрики:")
print(metrics$per_class)
message("Summary CSV: ", REPORT_CSV)
message("Full metrics RDS: ", REPORT_RDS)
