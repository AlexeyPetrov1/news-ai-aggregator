#' @title Ground-truth and canonical label utilities
#' @description Helpers to build a mini labeled dataset, map raw topic labels
#'   to canonical categories, and compute supervised quality metrics.

#' Create a mini ground-truth sample for manual labeling
#'
#' @param df Input data frame with classified articles.
#' @param n Number of rows to sample.
#' @param output_path Optional CSV path to save a labeling template.
#' @param seed Random seed for reproducible sampling.
#' @return Sampled data frame containing article metadata, predicted topic, and
#'   empty \code{topic_true} column for manual annotation.
#' @export
create_ground_truth_sample <- function(df,
                                       n = 200L,
                                       output_path = NULL,
                                       seed = 42L) {
  if (!is.data.frame(df) || nrow(df) == 0L) {
    cli::cli_abort("{.arg df} must be a non-empty data frame.")
  }

  set.seed(as.integer(seed))
  n <- min(as.integer(n), nrow(df))
  idx <- sample.int(nrow(df), n)

  cols <- intersect(
    c("article_id", "published_at", "feed_title", "title", "content_text",
      "topic_label", "topic_canonical"),
    names(df)
  )
  out <- df[idx, cols, drop = FALSE]
  out$topic_true <- NA_character_

  if (!is.null(output_path) && nzchar(output_path)) {
    dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(out, output_path, row.names = FALSE, fileEncoding = "UTF-8")
  }

  out
}

#' Apply canonical label mapping
#'
#' @param df Input data frame.
#' @param mapping Mapping table/data frame with columns \code{raw_label},
#'   \code{canonical_label}.
#' @param source_col Source column in \code{df} with raw labels.
#' @param target_col Output column in \code{df} with canonical labels.
#' @param unknown_label Label to assign when raw label has no mapping.
#' @return \code{df} with \code{target_col} added/updated.
#' @export
apply_canonical_label_mapping <- function(df,
                                          mapping,
                                          source_col = "topic_label",
                                          target_col = "topic_canonical",
                                          unknown_label = "Без категории") {
  if (!is.data.frame(df)) cli::cli_abort("{.arg df} must be a data frame.")
  if (!source_col %in% names(df)) {
    cli::cli_abort("Column {.field {source_col}} not found in {.arg df}.")
  }

  if (!is.data.frame(mapping)) {
    cli::cli_abort("{.arg mapping} must be a data frame.")
  }
  req_cols <- c("raw_label", "canonical_label")
  if (!all(req_cols %in% names(mapping))) {
    cli::cli_abort("{.arg mapping} must contain columns: raw_label, canonical_label.")
  }

  raw <- trimws(as.character(df[[source_col]]))
  map_key <- trimws(as.character(mapping$raw_label))
  map_val <- trimws(as.character(mapping$canonical_label))
  dict <- stats::setNames(map_val, map_key)

  mapped <- unname(dict[raw])
  mapped[is.na(mapped) | !nzchar(mapped)] <- unknown_label
  df[[target_col]] <- mapped
  df
}

#' Evaluate predictions against ground truth labels
#'
#' @param df Input data frame containing true and predicted labels.
#' @param truth_col Column with manually labeled ground truth.
#' @param pred_col Column with predicted/canonical labels.
#' @return Named list with \code{accuracy}, \code{macro_f1}, support counts,
#'   per-class metrics, and confusion matrix.
#' @export
evaluate_against_ground_truth <- function(df,
                                          truth_col = "topic_true",
                                          pred_col = "topic_canonical") {
  if (!is.data.frame(df) || nrow(df) == 0L) {
    cli::cli_abort("{.arg df} must be a non-empty data frame.")
  }
  if (!truth_col %in% names(df)) {
    cli::cli_abort("Column {.field {truth_col}} not found in {.arg df}.")
  }
  if (!pred_col %in% names(df)) {
    cli::cli_abort("Column {.field {pred_col}} not found in {.arg df}.")
  }

  truth <- trimws(as.character(df[[truth_col]]))
  pred <- trimws(as.character(df[[pred_col]]))
  keep <- nzchar(truth) & !is.na(truth) & nzchar(pred) & !is.na(pred)

  truth <- truth[keep]
  pred <- pred[keep]
  if (!length(truth)) {
    cli::cli_abort("No valid rows with both truth and prediction labels.")
  }

  labels <- sort(unique(c(truth, pred)))
  cm <- table(
    factor(truth, levels = labels),
    factor(pred, levels = labels)
  )

  accuracy <- sum(diag(cm)) / sum(cm)

  per_class <- lapply(seq_along(labels), function(i) {
    cls <- labels[i]
    tp <- cm[i, i]
    fp <- sum(cm[, i]) - tp
    fn <- sum(cm[i, ]) - tp
    precision <- if ((tp + fp) == 0L) 0 else tp / (tp + fp)
    recall <- if ((tp + fn) == 0L) 0 else tp / (tp + fn)
    f1 <- if ((precision + recall) == 0) 0 else 2 * precision * recall / (precision + recall)
    data.frame(
      label = cls,
      precision = as.numeric(precision),
      recall = as.numeric(recall),
      f1 = as.numeric(f1),
      support = as.integer(sum(cm[i, ])),
      stringsAsFactors = FALSE
    )
  })
  per_class <- dplyr::bind_rows(per_class)

  list(
    n_labeled = length(truth),
    accuracy = as.numeric(accuracy),
    macro_f1 = mean(per_class$f1),
    per_class = per_class,
    confusion_matrix = as.matrix(cm)
  )
}
