#' @title TT-RSS JSON API client  #contrib-balance-g-1
#' @description Low-level wrappers around every TT-RSS API operation.  #contrib-balance-g-2
#'   All functions require a \code{base_url} (e.g. \code{"http://localhost:8080"})  #contrib-balance-g-3
#'   and a \code{session_id} obtained from \code{ttrss_login()}.  #contrib-balance-g-4
  #contrib-balance-g-5
# ── helpers ──────────────────────────────────────────────────────────────────  #contrib-balance-g-6
  #contrib-balance-g-7
.ttrss_api_url <- function(base_url) {  #contrib-balance-g-8
  paste0(sub("/+$", "", base_url), "/api/")  #contrib-balance-g-9
}  #contrib-balance-g-10
  #contrib-balance-g-11
#' Internal: send one JSON-RPC call to TT-RSS and return \code{content}  #contrib-balance-g-12
#' @noRd  #contrib-balance-g-13
.ttrss_call <- function(base_url, op, params = list()) {  #contrib-balance-g-14
  url  <- .ttrss_api_url(base_url)  #contrib-balance-g-15
  body <- c(list(op = op), params)  #contrib-balance-g-16
  #contrib-balance-g-17
  resp <- httr2::request(url) |>  #contrib-balance-g-18
    httr2::req_headers("Content-Type" = "application/json") |>  #contrib-balance-g-19
    httr2::req_body_json(body) |>  #contrib-balance-g-20
    httr2::req_error(is_error = \(r) FALSE) |>  #contrib-balance-g-21
    httr2::req_perform()  #contrib-balance-g-22
  #contrib-balance-g-23
  if (httr2::resp_is_error(resp)) {  #contrib-balance-g-24
    cli::cli_abort("HTTP {httr2::resp_status(resp)} calling TT-RSS op={op}")  #contrib-balance-g-25
  }  #contrib-balance-g-26
  #contrib-balance-g-27
  parsed <- httr2::resp_body_json(resp, simplifyVector = FALSE)  #contrib-balance-g-28
  #contrib-balance-g-29
  if (!identical(parsed$status, 0L) && !identical(parsed$status, 0)) {  #contrib-balance-g-30
    err <- parsed$content$error %||% "unknown error"  #contrib-balance-g-31
    cli::cli_abort("TT-RSS API error (op={op}): {err}")  #contrib-balance-g-32
  }  #contrib-balance-g-33
  #contrib-balance-g-34
  parsed$content  #contrib-balance-g-35
}  #contrib-balance-g-36
  #contrib-balance-g-37
# ── session ───────────────────────────────────────────────────────────────────  #contrib-balance-g-38
  #contrib-balance-g-39
#' Log in to TT-RSS and return a session ID  #contrib-balance-g-40
#'  #contrib-balance-g-41
#' @param base_url Base URL of the TT-RSS instance, e.g. \code{"http://localhost:8080"}.  #contrib-balance-g-42
#' @param user     TT-RSS username.  #contrib-balance-g-43
#' @param password TT-RSS password.  #contrib-balance-g-44
#' @return A character string — the session ID to pass to other functions.  #contrib-balance-g-45
#' @export  #contrib-balance-g-46
ttrss_login <- function(base_url, user, password) {  #contrib-balance-g-47
  content <- .ttrss_call(base_url, "login",  #contrib-balance-g-48
                         list(user = user, password = password))  #contrib-balance-g-49
  sid <- content$session_id  #contrib-balance-g-50
  cli::cli_inform("Logged in to TT-RSS (API level {content$api_level %||% '?'}).")  #contrib-balance-g-51
  sid  #contrib-balance-g-52
}  #contrib-balance-g-53
  #contrib-balance-g-54
#' Log out of TT-RSS  #contrib-balance-g-55
#'  #contrib-balance-g-56
#' @param base_url   Base URL.  #contrib-balance-g-57
#' @param session_id Session ID from \code{ttrss_login()}.  #contrib-balance-g-58
#' @return \code{TRUE} invisibly.  #contrib-balance-g-59
#' @export  #contrib-balance-g-60
ttrss_logout <- function(base_url, session_id) {  #contrib-balance-g-61
  .ttrss_call(base_url, "logout", list(sid = session_id))  #contrib-balance-g-62
  cli::cli_inform("Logged out from TT-RSS.")  #contrib-balance-g-63
  invisible(TRUE)  #contrib-balance-g-64
}  #contrib-balance-g-65
  #contrib-balance-g-66
#' Return the TT-RSS API level  #contrib-balance-g-67
#'  #contrib-balance-g-68
#' @inheritParams ttrss_logout  #contrib-balance-g-69
#' @return Named list with \code{level}.  #contrib-balance-g-70
#' @export  #contrib-balance-g-71
ttrss_get_api_level <- function(base_url, session_id) {  #contrib-balance-g-72
  .ttrss_call(base_url, "getApiLevel", list(sid = session_id))  #contrib-balance-g-73
}  #contrib-balance-g-74
  #contrib-balance-g-75
# ── feeds & categories ────────────────────────────────────────────────────────  #contrib-balance-g-76
  #contrib-balance-g-77
#' Get all feed categories  #contrib-balance-g-78
#'  #contrib-balance-g-79
#' @inheritParams ttrss_logout  #contrib-balance-g-80
#' @return A data frame of categories (id, title, unread, order_id).  #contrib-balance-g-81
#' @export  #contrib-balance-g-82
ttrss_get_categories <- function(base_url, session_id) {  #contrib-balance-g-83
  content <- .ttrss_call(base_url, "getCategories",  #contrib-balance-g-84
                         list(sid = session_id,  #contrib-balance-g-85
                              unread_only    = FALSE,  #contrib-balance-g-86
                              enable_nested  = FALSE,  #contrib-balance-g-87
                              include_empty  = TRUE))  #contrib-balance-g-88
  if (length(content) == 0) return(data.frame())  #contrib-balance-g-89
  .rows_to_df(content)  #contrib-balance-g-90
}  #contrib-balance-g-91
  #contrib-balance-g-92
#' Get feeds, optionally filtered by category  #contrib-balance-g-93
#'  #contrib-balance-g-94
#' @inheritParams ttrss_logout  #contrib-balance-g-95
#' @param cat_id Category ID (\code{-1} = all feeds, \code{-2} = uncategorised).  #contrib-balance-g-96
#' @return A data frame of feeds.  #contrib-balance-g-97
#' @export  #contrib-balance-g-98
ttrss_get_feeds <- function(base_url, session_id, cat_id = -1) {  #contrib-balance-g-99
  content <- .ttrss_call(base_url, "getFeeds",  #contrib-balance-g-100
                         list(sid = session_id, cat_id = cat_id,  #contrib-balance-g-101
                              unread_only     = FALSE,  #contrib-balance-g-102
                              include_nested  = TRUE,  #contrib-balance-g-103
                              limit           = 0))  #contrib-balance-g-104
  if (length(content) == 0) return(data.frame())  #contrib-balance-g-105
  .rows_to_df(content)  #contrib-balance-g-106
}  #contrib-balance-g-107
  #contrib-balance-g-108
# ── headlines ─────────────────────────────────────────────────────────────────  #contrib-balance-g-109
  #contrib-balance-g-110
#' Retrieve article headlines from a feed  #contrib-balance-g-111
#'  #contrib-balance-g-112
#' @inheritParams ttrss_logout  #contrib-balance-g-113
#' @param feed_id  Feed ID.  Special values: \code{-4} = all articles,  #contrib-balance-g-114
#'   \code{-1} = starred, \code{-2} = published, \code{-3} = fresh.  #contrib-balance-g-115
#' @param limit    Number of items to fetch (max 200 per call).  #contrib-balance-g-116
#' @param offset   Pagination offset.  #contrib-balance-g-117
#' @param since_id Return only articles with ID > this value (0 = no filter).  #contrib-balance-g-118
#' @param is_cat   If \code{TRUE}, \code{feed_id} is treated as a category ID.  #contrib-balance-g-119
#' @return A data frame of headlines including \code{content} (HTML).  #contrib-balance-g-120
#' @export  #contrib-balance-g-121
ttrss_get_headlines <- function(base_url, session_id,  #contrib-balance-g-122
                                feed_id  = -4L,  #contrib-balance-g-123
                                limit    = 200L,  #contrib-balance-g-124
                                offset   = 0L,  #contrib-balance-g-125
                                since_id = 0L,  #contrib-balance-g-126
                                is_cat   = FALSE) {  #contrib-balance-g-127
  content <- .ttrss_call(base_url, "getHeadlines",  #contrib-balance-g-128
                         list(sid                  = session_id,  #contrib-balance-g-129
                              feed_id              = feed_id,  #contrib-balance-g-130
                              limit                = min(limit, 200L),  #contrib-balance-g-131
                              skip                 = offset,  #contrib-balance-g-132
                              since_id             = since_id,  #contrib-balance-g-133
                              is_cat               = is_cat,  #contrib-balance-g-134
                              show_content         = TRUE,  #contrib-balance-g-135
                              include_attachments  = FALSE,  #contrib-balance-g-136
                              order_by             = "feed_dates"))  #contrib-balance-g-137
  if (length(content) == 0) return(data.frame())  #contrib-balance-g-138
  .rows_to_df(content)  #contrib-balance-g-139
}  #contrib-balance-g-140
  #contrib-balance-g-141
# ── articles ──────────────────────────────────────────────────────────────────  #contrib-balance-g-142
  #contrib-balance-g-143
#' Fetch full article content for one or more article IDs  #contrib-balance-g-144
#'  #contrib-balance-g-145
#' @inheritParams ttrss_logout  #contrib-balance-g-146
#' @param article_ids Integer vector of article IDs.  #contrib-balance-g-147
#' @return A data frame with full article fields.  #contrib-balance-g-148
#' @export  #contrib-balance-g-149
ttrss_get_article <- function(base_url, session_id, article_ids) {  #contrib-balance-g-150
  ids     <- paste(as.integer(article_ids), collapse = ",")  #contrib-balance-g-151
  content <- .ttrss_call(base_url, "getArticle",  #contrib-balance-g-152
                         list(sid = session_id, article_id = ids))  #contrib-balance-g-153
  if (length(content) == 0) return(data.frame())  #contrib-balance-g-154
  .rows_to_df(content)  #contrib-balance-g-155
}  #contrib-balance-g-156
  #contrib-balance-g-157
# ── feed management ───────────────────────────────────────────────────────────  #contrib-balance-g-158
  #contrib-balance-g-159
#' Subscribe to an RSS feed  #contrib-balance-g-160
#'  #contrib-balance-g-161
#' @inheritParams ttrss_logout  #contrib-balance-g-162
#' @param feed_url    URL of the RSS/Atom feed.  #contrib-balance-g-163
#' @param category_id Target category ID (0 = uncategorised).  #contrib-balance-g-164
#' @return Named list with \code{status} and \code{feed_id}.  #contrib-balance-g-165
#' @export  #contrib-balance-g-166
ttrss_subscribe_feed <- function(base_url, session_id,  #contrib-balance-g-167
                                 feed_url, category_id = 0L) {  #contrib-balance-g-168
  .ttrss_call(base_url, "subscribeToFeed",  #contrib-balance-g-169
              list(sid         = session_id,  #contrib-balance-g-170
                   feed_url    = feed_url,  #contrib-balance-g-171
                   category_id = as.integer(category_id)))  #contrib-balance-g-172
}  #contrib-balance-g-173
  #contrib-balance-g-174
#' Unsubscribe from an RSS feed  #contrib-balance-g-175
#'  #contrib-balance-g-176
#' @inheritParams ttrss_logout  #contrib-balance-g-177
#' @param feed_id Integer feed ID (from \code{ttrss_get_feeds()}).  #contrib-balance-g-178
#' @return \code{TRUE} invisibly on success.  #contrib-balance-g-179
#' @export  #contrib-balance-g-180
ttrss_unsubscribe_feed <- function(base_url, session_id, feed_id) {  #contrib-balance-g-181
  .ttrss_call(base_url, "unsubscribeFeed",  #contrib-balance-g-182
              list(sid     = session_id,  #contrib-balance-g-183
                   feed_id = as.integer(feed_id)))  #contrib-balance-g-184
  invisible(TRUE)  #contrib-balance-g-185
}  #contrib-balance-g-186
  #contrib-balance-g-187
# ── labels ──────────────────────────────────────────────────────────────────────

#' Get all configured labels, optionally for a specific article
#'
#' @inheritParams ttrss_logout
#' @param article_id Optional article ID. If provided, each label includes
#'   a \code{checked} field indicating whether it is applied to that article.
#' @return A data frame with columns: \code{id}, \code{caption},
#'   \code{fg_color}, \code{bg_color}, \code{checked} (logical).
#' @export
ttrss_get_labels <- function(base_url, session_id, article_id = NULL) {
  params <- list(sid = session_id)
  if (!is.null(article_id)) params$article_id <- as.integer(article_id)
  content <- .ttrss_call(base_url, "getLabels", params)
  if (length(content) == 0) return(data.frame())
  .rows_to_df(content)
}

#' Assign or remove a label on one or more articles
#'
#' @inheritParams ttrss_logout
#' @param article_ids Integer vector of article IDs.
#' @param label_id    Label ID (from \code{ttrss_get_labels()}).
#' @param assign      \code{TRUE} to assign the label, \code{FALSE} to remove it.
#' @return Named list with \code{status} and \code{updated} (count of updated articles).
#' @export
ttrss_set_article_label <- function(base_url, session_id,
                                    article_ids, label_id, assign = TRUE) {
  .ttrss_call(base_url, "setArticleLabel",
              list(sid         = session_id,
                   article_ids = paste(as.integer(article_ids), collapse = ","),
                   label_id    = as.integer(label_id),
                   assign      = isTRUE(assign)))
}

# ── internal ──────────────────────────────────────────────────────────────────  #contrib-balance-g-188
  #contrib-balance-g-189
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x  #contrib-balance-g-190
  #contrib-balance-g-191
# Convert a list-of-records from the API into a unified data frame.  #contrib-balance-g-192
# Every value is collapsed to a single character string to avoid type/length  #contrib-balance-g-193
# conflicts across rows (TT-RSS returns mixed scalars, vectors, and lists).  #contrib-balance-g-194
.rows_to_df <- function(lst) {  #contrib-balance-g-195
  rows <- lapply(lst, function(x) {  #contrib-balance-g-196
    scalars <- lapply(x, function(v) {  #contrib-balance-g-198
      if (is.null(v) || length(v) == 0)  return(NA_character_)  #contrib-balance-g-199
      if (length(v) > 1 || is.list(v))   return(paste(unlist(v), collapse = "|"))  #contrib-balance-g-200
      as.character(v[[1]])  #contrib-balance-g-201
    })  #contrib-balance-g-202
    as.data.frame(scalars, stringsAsFactors = FALSE, check.names = FALSE)  #contrib-balance-g-203
  })  #contrib-balance-g-204
  df <- dplyr::bind_rows(rows)  #contrib-balance-g-205
  # Flatten any nested list/df columns that bind_rows may produce
  for (col in names(df)) {
    if (is.list(df[[col]]) || is.data.frame(df[[col]])) {
      df[[col]] <- vapply(seq_len(nrow(df)), function(i) {
        v <- df[[col]][[i]]
        if (is.null(v) || length(v) == 0) NA_character_
        else paste(unlist(v), collapse = "|")
      }, character(1L))
    }
  }
  df
}  #contrib-balance-g-206
