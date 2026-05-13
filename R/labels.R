#' @title TT-RSS label management
#' @description Create, list, and manage TT-RSS labels.
#'   Label creation goes directly to PostgreSQL because the TT-RSS API
#'   does not expose a create-label endpoint. Assigning/removing labels
#'   on articles uses the API via \code{ttrss_set_article_label()}.

# ── PostgreSQL helpers ─────────────────────────────────────────────────────────

#' Create a new label in TT-RSS (via PostgreSQL)
#'
#' TT-RSS API does not support label creation, so this function writes
#' directly to the \code{ttrss_labels2} table.
#'
#' @param caption  Label name.
#' @param fg_color Foreground colour in hex (e.g. \code{"#e14a00"}).
#' @param bg_color Background colour in hex (e.g. \code{"#ffffff"}).
#' @param owner_uid User ID that owns this label (default 1 = admin).
#' @param db_host  PostgreSQL host, default \code{"ttrss-db"} (Docker) or
#'   \code{"localhost"} (outside Docker).
#' @param db_name  Database name.
#' @param db_user  Database user.
#' @param db_pass  Database password.
#' @param db_port  Database port.
#' @return The new label ID (invisibly).
#' @export
ttrss_create_label <- function(caption,
                               fg_color  = "#e14a00",
                               bg_color  = "#ffffff",
                               owner_uid = 1L,
                               db_host = Sys.getenv("TTRSS_DB_HOST", "ttrss-db"),
                               db_name = Sys.getenv("TTRSS_DB_NAME", "ttrss"),
                               db_user = Sys.getenv("TTRSS_DB_USER", "ttrss"),
                               db_pass = Sys.getenv("TTRSS_DB_PASS", "ttrss_secret"),
                               db_port = Sys.getenv("TTRSS_DB_PORT", "5432")) {
  con <- DBI::dbConnect(RPostgres::Postgres(),
                        host     = db_host,
                        port     = as.integer(db_port),
                        dbname   = db_name,
                        user     = db_user,
                        password = db_pass)
  on.exit(DBI::dbDisconnect(con))

  exists <- DBI::dbGetQuery(con, sprintf(
    "SELECT id FROM ttrss_labels2 WHERE owner_uid = %d AND caption = %s",
    as.integer(owner_uid), DBI::dbQuoteString(con, caption)
  ))

  if (nrow(exists) > 0) {
    cli::cli_inform("Label {.val {caption}} already exists (id={exists$id[1]}).")
    return(invisible(exists$id[1]))
  }

  DBI::dbExecute(con, sprintf(
    "INSERT INTO ttrss_labels2 (owner_uid, fg_color, bg_color, caption)
     VALUES (%d, %s, %s, %s)",
    as.integer(owner_uid),
    DBI::dbQuoteString(con, fg_color),
    DBI::dbQuoteString(con, bg_color),
    DBI::dbQuoteString(con, caption)
  ))

  new_id <- as.integer(DBI::dbGetQuery(con,
    "SELECT currval('ttrss_labels2_id_seq')::int AS id")$id)
  cli::cli_inform("Created label {.val {caption}} (db_id={new_id}).")
  invisible(new_id)
}

#' Delete a label from TT-RSS (via PostgreSQL)
#'
#' @param label_id  Label ID to delete.
#' @inheritParams ttrss_create_label
#' @return \code{TRUE} invisibly.
#' @export
ttrss_delete_label <- function(label_id,
                               db_host = Sys.getenv("TTRSS_DB_HOST", "ttrss-db"),
                               db_name = Sys.getenv("TTRSS_DB_NAME", "ttrss"),
                               db_user = Sys.getenv("TTRSS_DB_USER", "ttrss"),
                               db_pass = Sys.getenv("TTRSS_DB_PASS", "ttrss_secret"),
                               db_port = Sys.getenv("TTRSS_DB_PORT", "5432")) {
  con <- DBI::dbConnect(RPostgres::Postgres(),
                        host     = db_host,
                        port     = as.integer(db_port),
                        dbname   = db_name,
                        user     = db_user,
                        password = db_pass)
  on.exit(DBI::dbDisconnect(con))

  DBI::dbExecute(con, sprintf(
    "DELETE FROM ttrss_user_labels2 WHERE label_id = %d",
    as.integer(label_id)
  ))
  DBI::dbExecute(con, sprintf(
    "DELETE FROM ttrss_labels2 WHERE id = %d",
    as.integer(label_id)
  ))
  cli::cli_inform("Deleted label id={label_id}.")
  invisible(TRUE)
}

# ── API-ID helpers ──────────────────────────────────────────────────────────────

#' Find a label by caption and return its API ID
#'
#' Labels returned by \code{ttrss_get_labels()} use negative API IDs
#' (legacy format), but \code{ttrss_create_label()} returns the database ID.
#' Use this helper to get the API ID needed for \code{ttrss_set_article_label()}.
#'
#' @param base_url   TT-RSS base URL.
#' @param session_id Session ID from \code{ttrss_login()}.
#' @param caption    Label name to search for (exact match, case-insensitive).
#' @return The API label ID (integer), or \code{NA_integer_} if not found.
#' @export
ttrss_find_label_api_id <- function(base_url, session_id, caption) {
  labels <- ttrss_get_labels(base_url, session_id)
  if (nrow(labels) == 0) return(NA_integer_)
  hit <- labels[trimws(tolower(labels$caption)) == trimws(tolower(caption)), , drop = FALSE]
  if (nrow(hit) == 0) return(NA_integer_)
  as.integer(hit$id[1])
}

#' Create a label and return its API ID ready for use
#'
#' Combines \code{ttrss_create_label()} (via PostgreSQL) and
#' \code{ttrss_find_label_api_id()} so callers get the API ID directly.
#'
#' @inheritParams ttrss_create_label
#' @param base_url   TT-RSS base URL.
#' @param session_id Session ID from \code{ttrss_login()}.
#' @return The API label ID (invisibly).
#' @export
ttrss_create_label_api <- function(caption,
                                   fg_color  = "#e14a00",
                                   bg_color  = "#ffffff",
                                   owner_uid = 1L,
                                   base_url  = Sys.getenv("TTRSS_URL", "http://ttrss/"),
                                   session_id = NULL,
                                   db_host = Sys.getenv("TTRSS_DB_HOST", "ttrss-db"),
                                   db_name = Sys.getenv("TTRSS_DB_NAME", "ttrss"),
                                   db_user = Sys.getenv("TTRSS_DB_USER", "ttrss"),
                                   db_pass = Sys.getenv("TTRSS_DB_PASS", "ttrss_secret"),
                                   db_port = Sys.getenv("TTRSS_DB_PORT", "5432")) {
  ttrss_create_label(caption, fg_color, bg_color, owner_uid,
                     db_host, db_name, db_user, db_pass, db_port)
  if (is.null(session_id)) return(invisible(NA_integer_))
  api_id <- ttrss_find_label_api_id(base_url, session_id, caption)
  if (is.na(api_id)) {
    cli::cli_warn("Label {.val {caption}} created but API ID not found.")
  } else {
    cli::cli_inform("API ID for {.val {caption}}: {api_id}.")
  }
  invisible(api_id)
}

# ── high-level helpers ─────────────────────────────────────────────────────────

#' Apply labels to articles in bulk
#'
#' High-level wrapper: applies each label from a named list to the
#' corresponding article IDs. Uses \code{ttrss_set_article_label()} API.
#'
#' @param base_url   TT-RSS base URL.
#' @param session_id Session ID from \code{ttrss_login()}.
#' @param mapping    Named list mapping label IDs (names) to article ID vectors
#'   (values).  Example: \code{list("2" = c(1, 2, 3), "5" = c(10))}.
#' @return Number of articles updated (invisibly).
#' @export
ttrss_bulk_label_articles <- function(base_url, session_id, mapping) {
  total <- 0L
  for (label_id in names(mapping)) {
    article_ids <- mapping[[label_id]]
    if (!length(article_ids)) next
    res <- ttrss_set_article_label(base_url, session_id,
                                   article_ids = article_ids,
                                   label_id    = as.integer(label_id),
                                   assign      = TRUE)
    n <- as.integer(res$updated %||% 0)
    total <- total + n
    cli::cli_inform("Label {label_id}: assigned to {n} articles.")
  }
  cli::cli_inform("Total: {total} articles labelled.")
  invisible(total)
}

#' Get labels currently assigned to a set of articles
#'
#' Calls \code{ttrss_get_labels()} for each article ID and returns
#' only the labels that are checked (assigned).
#'
#' @inheritParams ttrss_bulk_label_articles
#' @param article_ids Integer vector of article IDs.
#' @return Data frame with columns \code{article_id}, \code{label_id},
#'   \code{caption}, \code{fg_color}, \code{bg_color}.
#' @export
ttrss_get_article_labels <- function(base_url, session_id, article_ids) {
  out <- data.frame(article_id = integer(), label_id = integer(),
                    caption = character(), fg_color = character(),
                    bg_color = character(), stringsAsFactors = FALSE)
  for (aid in as.integer(article_ids)) {
    labels <- ttrss_get_labels(base_url, session_id, article_id = aid)
    if (nrow(labels) == 0) next
    checked <- labels[isTRUE(as.logical(labels$checked)), , drop = FALSE]
    if (nrow(checked) == 0) next
    checked$article_id <- aid
    out <- rbind(out, checked[, c("article_id", "id", "caption",
                                   "fg_color", "bg_color")])
  }
  names(out)[names(out) == "id"] <- "label_id"
  rownames(out) <- NULL
  out
}
