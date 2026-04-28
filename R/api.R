#' @title TT-RSS JSON API client
#' @description Low-level wrappers around every TT-RSS API operation.
#'   All functions require a \code{base_url} (e.g. \code{"http://localhost:8080"})
#'   and a \code{session_id} obtained from \code{ttrss_login()}.

# ── helpers ──────────────────────────────────────────────────────────────────

.ttrss_api_url <- function(base_url) {
  paste0(sub("/+$", "", base_url), "/api/")
}

#' Internal: send one JSON-RPC call to TT-RSS and return \code{content}
#' @noRd
.ttrss_call <- function(base_url, op, params = list()) {
  url  <- .ttrss_api_url(base_url)
  body <- c(list(op = op), params)

  resp <- httr2::request(url) |>
    httr2::req_headers("Content-Type" = "application/json") |>
    httr2::req_body_json(body) |>
    httr2::req_error(is_error = \(r) FALSE) |>
    httr2::req_perform()

  if (httr2::resp_is_error(resp)) {
    cli::cli_abort("HTTP {httr2::resp_status(resp)} calling TT-RSS op={op}")
  }

  parsed <- httr2::resp_body_json(resp, simplifyVector = FALSE)

  if (!identical(parsed$status, 0L) && !identical(parsed$status, 0)) {
    err <- parsed$content$error %||% "unknown error"
    cli::cli_abort("TT-RSS API error (op={op}): {err}")
  }

  parsed$content
}

# ── session ───────────────────────────────────────────────────────────────────

#' Log in to TT-RSS and return a session ID
#'
#' @param base_url Base URL of the TT-RSS instance, e.g. \code{"http://localhost:8080"}.
#' @param user     TT-RSS username.
#' @param password TT-RSS password.
#' @return A character string — the session ID to pass to other functions.
#' @export
ttrss_login <- function(base_url, user, password) {
  content <- .ttrss_call(base_url, "login",
                         list(user = user, password = password))
  sid <- content$session_id
  cli::cli_inform("Logged in to TT-RSS (API level {content$api_level %||% '?'}).")
  sid
}

#' Log out of TT-RSS
#'
#' @param base_url   Base URL.
#' @param session_id Session ID from \code{ttrss_login()}.
#' @return \code{TRUE} invisibly.
#' @export
ttrss_logout <- function(base_url, session_id) {
  .ttrss_call(base_url, "logout", list(sid = session_id))
  cli::cli_inform("Logged out from TT-RSS.")
  invisible(TRUE)
}

#' Return the TT-RSS API level
#'
#' @inheritParams ttrss_logout
#' @return Named list with \code{level}.
#' @export
ttrss_get_api_level <- function(base_url, session_id) {
  .ttrss_call(base_url, "getApiLevel", list(sid = session_id))
}

# ── feeds & categories ────────────────────────────────────────────────────────

#' Get all feed categories
#'
#' @inheritParams ttrss_logout
#' @return A data frame of categories (id, title, unread, order_id).
#' @export
ttrss_get_categories <- function(base_url, session_id) {
  content <- .ttrss_call(base_url, "getCategories",
                         list(sid = session_id,
                              unread_only    = FALSE,
                              enable_nested  = FALSE,
                              include_empty  = TRUE))
  if (length(content) == 0) return(data.frame())
  .rows_to_df(content)
}

#' Get feeds, optionally filtered by category
#'
#' @inheritParams ttrss_logout
#' @param cat_id Category ID (\code{-1} = all feeds, \code{-2} = uncategorised).
#' @return A data frame of feeds.
#' @export
ttrss_get_feeds <- function(base_url, session_id, cat_id = -1) {
  content <- .ttrss_call(base_url, "getFeeds",
                         list(sid = session_id, cat_id = cat_id,
                              unread_only     = FALSE,
                              include_nested  = TRUE,
                              limit           = 0))
  if (length(content) == 0) return(data.frame())
  .rows_to_df(content)
}

# ── headlines ─────────────────────────────────────────────────────────────────

#' Retrieve article headlines from a feed
#'
#' @inheritParams ttrss_logout
#' @param feed_id  Feed ID.  Special values: \code{-4} = all articles,
#'   \code{-1} = starred, \code{-2} = published, \code{-3} = fresh.
#' @param limit    Number of items to fetch (max 200 per call).
#' @param offset   Pagination offset.
#' @param since_id Return only articles with ID > this value (0 = no filter).
#' @param is_cat   If \code{TRUE}, \code{feed_id} is treated as a category ID.
#' @return A data frame of headlines including \code{content} (HTML).
#' @export
ttrss_get_headlines <- function(base_url, session_id,
                                feed_id  = -4L,
                                limit    = 200L,
                                offset   = 0L,
                                since_id = 0L,
                                is_cat   = FALSE) {
  content <- .ttrss_call(base_url, "getHeadlines",
                         list(sid                  = session_id,
                              feed_id              = feed_id,
                              limit                = min(limit, 200L),
                              skip                 = offset,
                              since_id             = since_id,
                              is_cat               = is_cat,
                              show_content         = TRUE,
                              include_attachments  = FALSE,
                              order_by             = "date_reverse"))
  if (length(content) == 0) return(data.frame())
  .rows_to_df(content)
}

# ── articles ──────────────────────────────────────────────────────────────────

#' Fetch full article content for one or more article IDs
#'
#' @inheritParams ttrss_logout
#' @param article_ids Integer vector of article IDs.
#' @return A data frame with full article fields.
#' @export
ttrss_get_article <- function(base_url, session_id, article_ids) {
  ids     <- paste(as.integer(article_ids), collapse = ",")
  content <- .ttrss_call(base_url, "getArticle",
                         list(sid = session_id, article_id = ids))
  if (length(content) == 0) return(data.frame())
  .rows_to_df(content)
}

# ── feed management ───────────────────────────────────────────────────────────

#' Subscribe to an RSS feed
#'
#' @inheritParams ttrss_logout
#' @param feed_url    URL of the RSS/Atom feed.
#' @param category_id Target category ID (0 = uncategorised).
#' @return Named list with \code{status} and \code{feed_id}.
#' @export
ttrss_subscribe_feed <- function(base_url, session_id,
                                 feed_url, category_id = 0L) {
  .ttrss_call(base_url, "subscribeToFeed",
              list(sid         = session_id,
                   feed_url    = feed_url,
                   category_id = as.integer(category_id)))
}

#' Unsubscribe from an RSS feed
#'
#' @inheritParams ttrss_logout
#' @param feed_id Integer feed ID (from \code{ttrss_get_feeds()}).
#' @return \code{TRUE} invisibly on success.
#' @export
ttrss_unsubscribe_feed <- function(base_url, session_id, feed_id) {
  .ttrss_call(base_url, "unsubscribeFeed",
              list(sid     = session_id,
                   feed_id = as.integer(feed_id)))
  invisible(TRUE)
}

# ── internal ──────────────────────────────────────────────────────────────────

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

# Convert a list-of-records from the API into a unified data frame.
# Every value is collapsed to a single character string to avoid type/length
# conflicts across rows (TT-RSS returns mixed scalars, vectors, and lists).
.rows_to_df <- function(lst) {
  rows <- lapply(lst, function(x) {
    # Force every field to a length-1 character scalar
    scalars <- lapply(x, function(v) {
      if (is.null(v) || length(v) == 0)  return(NA_character_)
      if (length(v) > 1 || is.list(v))   return(paste(unlist(v), collapse = "|"))
      as.character(v[[1]])
    })
    as.data.frame(scalars, stringsAsFactors = FALSE, check.names = FALSE)
  })
  dplyr::bind_rows(rows)
}
