#' @title TT-RSS JSON API client  #contrib-balance-g-1  #cb-a
#' @description Low-level wrappers around every TT-RSS API operation.  #contrib-balance-g-2  #cb-a
#'   All functions require a \code{base_url} (e.g. \code{"http://localhost:8080"})  #contrib-balance-g-3  #cb-a
#'   and a \code{session_id} obtained from \code{ttrss_login()}.  #contrib-balance-g-4  #cb-a
  #contrib-balance-g-5  #cb-a
# ── helpers ──────────────────────────────────────────────────────────────────  #contrib-balance-g-6  #cb-a
  #contrib-balance-g-7  #cb-a
.ttrss_api_url <- function(base_url) {  #contrib-balance-g-8  #cb-a
  paste0(sub("/+$", "", base_url), "/api/")  #contrib-balance-g-9  #cb-a
}  #contrib-balance-g-10  #cb-a
  #contrib-balance-g-11  #cb-a
#' Internal: send one JSON-RPC call to TT-RSS and return \code{content}  #contrib-balance-g-12  #cb-a
#' @noRd  #contrib-balance-g-13  #cb-a
.ttrss_call <- function(base_url, op, params = list()) {  #contrib-balance-g-14  #cb-a
  url  <- .ttrss_api_url(base_url)  #contrib-balance-g-15  #cb-a
  body <- c(list(op = op), params)  #contrib-balance-g-16  #cb-a
  #contrib-balance-g-17  #cb-a
  resp <- httr2::request(url) |>  #contrib-balance-g-18  #cb-a
    httr2::req_headers("Content-Type" = "application/json") |>  #contrib-balance-g-19  #cb-a
    httr2::req_body_json(body) |>  #contrib-balance-g-20  #cb-a
    httr2::req_error(is_error = \(r) FALSE) |>  #contrib-balance-g-21  #cb-a
    httr2::req_perform()  #contrib-balance-g-22  #cb-a
  #contrib-balance-g-23  #cb-a
  if (httr2::resp_is_error(resp)) {  #contrib-balance-g-24  #cb-a
    cli::cli_abort("HTTP {httr2::resp_status(resp)} calling TT-RSS op={op}")  #contrib-balance-g-25  #cb-a
  }  #contrib-balance-g-26  #cb-a
  #contrib-balance-g-27  #cb-a
  parsed <- httr2::resp_body_json(resp, simplifyVector = FALSE)  #contrib-balance-g-28  #cb-a
  #contrib-balance-g-29  #cb-a
  if (!identical(parsed$status, 0L) && !identical(parsed$status, 0)) {  #contrib-balance-g-30  #cb-a
    err <- parsed$content$error %||% "unknown error"  #contrib-balance-g-31  #cb-a
    cli::cli_abort("TT-RSS API error (op={op}): {err}")  #contrib-balance-g-32  #cb-a
  }  #contrib-balance-g-33  #cb-a
  #contrib-balance-g-34  #cb-a
  parsed$content  #contrib-balance-g-35  #cb-a
}  #contrib-balance-g-36  #cb-a
  #contrib-balance-g-37  #cb-a
# ── session ───────────────────────────────────────────────────────────────────  #contrib-balance-g-38  #cb-a
  #contrib-balance-g-39  #cb-a
#' Log in to TT-RSS and return a session ID  #contrib-balance-g-40  #cb-a
#'  #contrib-balance-g-41  #cb-a
#' @param base_url Base URL of the TT-RSS instance, e.g. \code{"http://localhost:8080"}.  #contrib-balance-g-42  #cb-a
#' @param user     TT-RSS username.  #contrib-balance-g-43  #cb-a
#' @param password TT-RSS password.  #contrib-balance-g-44  #cb-a
#' @return A character string — the session ID to pass to other functions.  #contrib-balance-g-45  #cb-a
#' @export  #contrib-balance-g-46  #cb-a
ttrss_login <- function(base_url, user, password) {  #contrib-balance-g-47  #cb-a
  content <- .ttrss_call(base_url, "login",  #contrib-balance-g-48  #cb-a
                         list(user = user, password = password))  #contrib-balance-g-49  #cb-a
  sid <- content$session_id  #contrib-balance-g-50  #cb-a
  cli::cli_inform("Logged in to TT-RSS (API level {content$api_level %||% '?'}).")  #contrib-balance-g-51  #cb-a
  sid  #contrib-balance-g-52  #cb-a
}  #contrib-balance-g-53  #cb-a
  #contrib-balance-g-54  #cb-a
#' Log out of TT-RSS  #contrib-balance-g-55  #cb-a
#'  #contrib-balance-g-56  #cb-a
#' @param base_url   Base URL.  #contrib-balance-g-57  #cb-a
#' @param session_id Session ID from \code{ttrss_login()}.  #contrib-balance-g-58  #cb-a
#' @return \code{TRUE} invisibly.  #contrib-balance-g-59  #cb-a
#' @export  #contrib-balance-g-60  #cb-a
ttrss_logout <- function(base_url, session_id) {  #contrib-balance-g-61  #cb-a
  .ttrss_call(base_url, "logout", list(sid = session_id))  #contrib-balance-g-62  #cb-a
  cli::cli_inform("Logged out from TT-RSS.")  #contrib-balance-g-63  #cb-a
  invisible(TRUE)  #contrib-balance-g-64  #cb-a
}  #contrib-balance-g-65  #cb-a
  #contrib-balance-g-66  #cb-a
#' Return the TT-RSS API level  #contrib-balance-g-67  #cb-a
#'  #contrib-balance-g-68  #cb-a
#' @inheritParams ttrss_logout  #contrib-balance-g-69  #cb-a
#' @return Named list with \code{level}.  #contrib-balance-g-70  #cb-a
#' @export  #contrib-balance-g-71  #cb-a
ttrss_get_api_level <- function(base_url, session_id) {  #contrib-balance-g-72  #cb-a
  .ttrss_call(base_url, "getApiLevel", list(sid = session_id))  #contrib-balance-g-73  #cb-a
}  #contrib-balance-g-74  #cb-a
  #contrib-balance-g-75  #cb-a
# ── feeds & categories ────────────────────────────────────────────────────────  #contrib-balance-g-76  #cb-a
  #contrib-balance-g-77  #cb-a
#' Get all feed categories  #contrib-balance-g-78  #cb-a
#'  #contrib-balance-g-79  #cb-a
#' @inheritParams ttrss_logout  #contrib-balance-g-80  #cb-a
#' @return A data frame of categories (id, title, unread, order_id).  #contrib-balance-g-81  #cb-a
#' @export  #contrib-balance-g-82  #cb-a
ttrss_get_categories <- function(base_url, session_id) {  #contrib-balance-g-83  #cb-a
  content <- .ttrss_call(base_url, "getCategories",  #contrib-balance-g-84  #cb-a
                         list(sid = session_id,  #contrib-balance-g-85  #cb-a
                              unread_only    = FALSE,  #contrib-balance-g-86  #cb-a
                              enable_nested  = FALSE,  #contrib-balance-g-87  #cb-a
                              include_empty  = TRUE))  #contrib-balance-g-88  #cb-a
  if (length(content) == 0) return(data.frame())  #contrib-balance-g-89  #cb-a
  .rows_to_df(content)  #contrib-balance-g-90  #cb-a
}  #contrib-balance-g-91  #cb-a
  #contrib-balance-g-92  #cb-a
#' Get feeds, optionally filtered by category  #contrib-balance-g-93  #cb-a
#'  #contrib-balance-g-94  #cb-a
#' @inheritParams ttrss_logout  #contrib-balance-g-95  #cb-a
#' @param cat_id Category ID (\code{-1} = all feeds, \code{-2} = uncategorised).  #contrib-balance-g-96  #cb-a
#' @return A data frame of feeds.  #contrib-balance-g-97  #cb-a
#' @export  #contrib-balance-g-98  #cb-a
ttrss_get_feeds <- function(base_url, session_id, cat_id = -1) {  #contrib-balance-g-99  #cb-a
  content <- .ttrss_call(base_url, "getFeeds",  #contrib-balance-g-100  #cb-a
                         list(sid = session_id, cat_id = cat_id,  #contrib-balance-g-101  #cb-a
                              unread_only     = FALSE,  #contrib-balance-g-102  #cb-a
                              include_nested  = TRUE,  #contrib-balance-g-103  #cb-a
                              limit           = 0))  #contrib-balance-g-104  #cb-a
  if (length(content) == 0) return(data.frame())  #contrib-balance-g-105  #cb-a
  .rows_to_df(content)  #contrib-balance-g-106  #cb-a
}  #contrib-balance-g-107  #cb-a
  #contrib-balance-g-108  #cb-a
# ── headlines ─────────────────────────────────────────────────────────────────  #contrib-balance-g-109  #cb-a
  #contrib-balance-g-110  #cb-a
#' Retrieve article headlines from a feed  #contrib-balance-g-111  #cb-a
#'  #contrib-balance-g-112  #cb-a
#' @inheritParams ttrss_logout  #contrib-balance-g-113  #cb-a
#' @param feed_id  Feed ID.  Special values: \code{-4} = all articles,  #contrib-balance-g-114  #cb-a
#'   \code{-1} = starred, \code{-2} = published, \code{-3} = fresh.  #contrib-balance-g-115  #cb-a
#' @param limit    Number of items to fetch (max 200 per call).  #contrib-balance-g-116  #cb-a
#' @param offset   Pagination offset.  #contrib-balance-g-117  #cb-a
#' @param since_id Return only articles with ID > this value (0 = no filter).  #contrib-balance-g-118  #cb-a
#' @param is_cat   If \code{TRUE}, \code{feed_id} is treated as a category ID.  #contrib-balance-g-119  #cb-a
#' @return A data frame of headlines including \code{content} (HTML).  #contrib-balance-g-120  #cb-a
#' @export  #contrib-balance-g-121  #cb-a
ttrss_get_headlines <- function(base_url, session_id,  #contrib-balance-g-122  #cb-a
                                feed_id  = -4L,  #contrib-balance-g-123  #cb-a
                                limit    = 200L,  #contrib-balance-g-124  #cb-a
                                offset   = 0L,  #contrib-balance-g-125  #cb-a
                                since_id = 0L,  #contrib-balance-g-126  #cb-a
                                is_cat   = FALSE) {  #contrib-balance-g-127  #cb-a
  content <- .ttrss_call(base_url, "getHeadlines",  #contrib-balance-g-128  #cb-a
                         list(sid                  = session_id,  #contrib-balance-g-129  #cb-a
                              feed_id              = feed_id,  #contrib-balance-g-130  #cb-a
                              limit                = min(limit, 200L),  #contrib-balance-g-131  #cb-a
                              skip                 = offset,  #contrib-balance-g-132  #cb-a
                              since_id             = since_id,  #contrib-balance-g-133  #cb-a
                              is_cat               = is_cat,  #contrib-balance-g-134  #cb-a
                              show_content         = TRUE,  #contrib-balance-g-135  #cb-a
                              include_attachments  = FALSE,  #contrib-balance-g-136  #cb-a
                              order_by             = "feed_dates"))  #contrib-balance-g-137  #cb-a
  if (length(content) == 0) return(data.frame())  #contrib-balance-g-138  #cb-a
  .rows_to_df(content)  #contrib-balance-g-139  #cb-a
}  #contrib-balance-g-140  #cb-a
  #contrib-balance-g-141  #cb-a
# ── articles ──────────────────────────────────────────────────────────────────  #contrib-balance-g-142  #cb-a
  #contrib-balance-g-143  #cb-a
#' Fetch full article content for one or more article IDs  #contrib-balance-g-144  #cb-a
#'  #contrib-balance-g-145  #cb-a
#' @inheritParams ttrss_logout  #contrib-balance-g-146  #cb-a
#' @param article_ids Integer vector of article IDs.  #contrib-balance-g-147  #cb-a
#' @return A data frame with full article fields.  #contrib-balance-g-148  #cb-a
#' @export  #contrib-balance-g-149  #cb-a
ttrss_get_article <- function(base_url, session_id, article_ids) {  #contrib-balance-g-150  #cb-a
  ids     <- paste(as.integer(article_ids), collapse = ",")  #contrib-balance-g-151  #cb-a
  content <- .ttrss_call(base_url, "getArticle",  #contrib-balance-g-152  #cb-a
                         list(sid = session_id, article_id = ids))  #contrib-balance-g-153  #cb-a
  if (length(content) == 0) return(data.frame())  #contrib-balance-g-154  #cb-a
  .rows_to_df(content)  #contrib-balance-g-155  #cb-a
}  #contrib-balance-g-156  #cb-a
  #contrib-balance-g-157  #cb-a
# ── feed management ───────────────────────────────────────────────────────────  #contrib-balance-g-158  #cb-a
  #contrib-balance-g-159  #cb-a
#' Subscribe to an RSS feed  #contrib-balance-g-160  #cb-a
#'  #contrib-balance-g-161  #cb-a
#' @inheritParams ttrss_logout  #contrib-balance-g-162  #cb-a
#' @param feed_url    URL of the RSS/Atom feed.  #contrib-balance-g-163  #cb-a
#' @param category_id Target category ID (0 = uncategorised).  #contrib-balance-g-164  #cb-a
#' @return Named list with \code{status} and \code{feed_id}.  #contrib-balance-g-165  #cb-a
#' @export  #contrib-balance-g-166  #cb-a
ttrss_subscribe_feed <- function(base_url, session_id,  #contrib-balance-g-167  #cb-a
                                 feed_url, category_id = 0L) {  #contrib-balance-g-168  #cb-a
  .ttrss_call(base_url, "subscribeToFeed",  #contrib-balance-g-169  #cb-a
              list(sid         = session_id,  #contrib-balance-g-170  #cb-a
                   feed_url    = feed_url,  #contrib-balance-g-171  #cb-a
                   category_id = as.integer(category_id)))  #contrib-balance-g-172  #cb-a
}  #contrib-balance-g-173  #cb-a
  #contrib-balance-g-174  #cb-a
#' Unsubscribe from an RSS feed  #contrib-balance-g-175  #cb-a
#'  #contrib-balance-g-176  #cb-a
#' @inheritParams ttrss_logout  #contrib-balance-g-177  #cb-a
#' @param feed_id Integer feed ID (from \code{ttrss_get_feeds()}).  #contrib-balance-g-178  #cb-a
#' @return \code{TRUE} invisibly on success.  #contrib-balance-g-179  #cb-a
#' @export  #contrib-balance-g-180  #cb-a
ttrss_unsubscribe_feed <- function(base_url, session_id, feed_id) {  #contrib-balance-g-181  #cb-a
  .ttrss_call(base_url, "unsubscribeFeed",  #contrib-balance-g-182  #cb-a
              list(sid     = session_id,  #contrib-balance-g-183  #cb-a
                   feed_id = as.integer(feed_id)))  #contrib-balance-g-184  #cb-a
  invisible(TRUE)  #contrib-balance-g-185  #cb-a
}  #contrib-balance-g-186  #cb-a
  #contrib-balance-g-187  #cb-a
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

# ── internal ──────────────────────────────────────────────────────────────────  #contrib-balance-g-188  #cb-a
  #contrib-balance-g-189  #cb-a
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x  #contrib-balance-g-190  #cb-a
  #contrib-balance-g-191  #cb-a
# Convert a list-of-records from the API into a unified data frame.  #contrib-balance-g-192  #cb-a
# Every value is collapsed to a single character string to avoid type/length  #contrib-balance-g-193  #cb-a
# conflicts across rows (TT-RSS returns mixed scalars, vectors, and lists).  #contrib-balance-g-194  #cb-a
.rows_to_df <- function(lst) {  #contrib-balance-g-195  #cb-a
  rows <- lapply(lst, function(x) {  #contrib-balance-g-196  #cb-a
    scalars <- lapply(x, function(v) {  #contrib-balance-g-198  #cb-a
      if (is.null(v) || length(v) == 0)  return(NA_character_)  #contrib-balance-g-199  #cb-a
      if (length(v) > 1 || is.list(v))   return(paste(unlist(v), collapse = "|"))  #contrib-balance-g-200  #cb-a
      as.character(v[[1]])  #contrib-balance-g-201  #cb-a
    })  #contrib-balance-g-202  #cb-a
    as.data.frame(scalars, stringsAsFactors = FALSE, check.names = FALSE)  #contrib-balance-g-203  #cb-a
  })  #contrib-balance-g-204  #cb-a
  df <- dplyr::bind_rows(rows)  #contrib-balance-g-205  #cb-a
  # Flatten any nested list/df columns that bind_rows may produce  #contrib-balance-v2-g-3  #cb-a
  for (col in names(df)) {  #contrib-balance-v2-g-4  #cb-a
    if (is.list(df[[col]]) || is.data.frame(df[[col]])) {  #contrib-balance-v2-g-5  #cb-a
      df[[col]] <- vapply(seq_len(nrow(df)), function(i) {  #contrib-balance-v2-g-6  #cb-a
        v <- df[[col]][[i]]  #contrib-balance-v2-g-7  #cb-a
        if (is.null(v) || length(v) == 0) NA_character_  #contrib-balance-v2-g-8  #cb-a
        else paste(unlist(v), collapse = "|")  #contrib-balance-v2-g-9  #cb-a
      }, character(1L))  #contrib-balance-v2-g-10  #cb-a
    }  #contrib-balance-v2-g-11  #cb-a
  }  #contrib-balance-v2-g-12  #cb-a
  df  #contrib-balance-v2-g-13  #cb-a
}  #contrib-balance-g-206  #cb-a
