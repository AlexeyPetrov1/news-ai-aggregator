make_gt_df <- function() {
  data.frame(
    article_id = 1:6,
    title = paste("News", 1:6),
    content_text = c(
      "apt campaign malware actor",
      "phishing mail credential",
      "ransomware extortion payment",
      "patch vulnerability cve",
      "breach leaked database",
      "other short note"
    ),
    topic_label = c("APT raw", "Phish raw", "Ransom raw", "Vuln raw", "Breach raw", "Unknown raw"),
    stringsAsFactors = FALSE
  )
}

test_that("apply_canonical_label_mapping maps known and unknown labels", {
  df <- make_gt_df()
  mapping <- data.frame(
    raw_label = c("APT raw", "Phish raw", "Ransom raw"),
    canonical_label = c("APT Campaigns", "Phishing", "Ransomware"),
    stringsAsFactors = FALSE
  )
  out <- apply_canonical_label_mapping(df, mapping, unknown_label = "Other")

  expect_true("topic_canonical" %in% names(out))
  expect_equal(out$topic_canonical[1], "APT Campaigns")
  expect_equal(out$topic_canonical[2], "Phishing")
  expect_equal(out$topic_canonical[6], "Other")
})

test_that("create_ground_truth_sample creates topic_true column", {
  df <- make_gt_df()
  sample_df <- create_ground_truth_sample(df, n = 3, seed = 1)
  expect_equal(nrow(sample_df), 3)
  expect_true("topic_true" %in% names(sample_df))
  expect_true(all(is.na(sample_df$topic_true)))
})

test_that("evaluate_against_ground_truth computes metrics", {
  df <- data.frame(
    topic_true = c("APT", "APT", "Phishing", "Ransomware"),
    topic_canonical = c("APT", "Phishing", "Phishing", "Ransomware"),
    stringsAsFactors = FALSE
  )
  m <- evaluate_against_ground_truth(df)
  expect_type(m, "list")
  expect_true("accuracy" %in% names(m))
  expect_true("macro_f1" %in% names(m))
  expect_s3_class(m$per_class, "data.frame")
  expect_true(is.matrix(m$confusion_matrix))
  expect_equal(m$n_labeled, 4)
})
