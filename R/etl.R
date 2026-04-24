#' @title ETL: collect TT-RSS articles into a unified data frame
#' @description High-level functions that orchestrate login → paginated fetch
#'   → normalisation → logout in one call.

#' Fetch all articles from TT-RSS and return a tidy data frame
#'
#' The function pages through the \emph{all articles} virtual feed
#' (\code{feed_id = -4}) in batches of up to 200 items until either
#' \code{max_articles} is reached or the API returns fewer items than
#' requested (i.e. end-of-feed).
#'
#' @param base_url     TT-RSS base URL, e.g. \code{"http://localhost:8080"}.
#' @param user         TT-RSS username.
#' @param password     TT-RSS password.
#' @param max_articles Maximum total articles to retrieve.
#' @param batch_size   Articles per API call (capped at 200).
#' @param since_id     Only return articles with ID greater than this value.
#'   Pass \code{0} (default) to fetch everything.
#' @return A data frame with one row per article and columns:
#'   \code{article_id}, \code{title}, \code{content}, \code{content_text},
#'   \code{link}, \code{feed_id}, \code{feed_title}, \code{author},
#'   \code{published_at}, \code{fetched_at}, \code{is_unread}, \code{is_starred}.
#' @export
fetch_news_dataframe <- function(base_url,
                                 user,
                                 password,
                                 max_articles = 1000L,
                                 batch_size   = 200L,
                                 since_id     = 0L) {

  sid <- ttrss_login(base_url, user, password)
  on.exit(ttrss_logout(base_url, sid), add = TRUE)

  batch_size <- min(as.integer(batch_size), 200L)
  collected  <- list()
  offset     <- 0L
  total      <- 0L

  cli::cli_progress_bar("Fetching articles", total = max_articles)

  repeat {
    remaining <- max_articles - total
    if (remaining <= 0L) break

    n_fetch <- min(batch_size, remaining)

    batch <- tryCatch(
      ttrss_get_headlines(base_url, sid,
                          feed_id  = -4L,
                          limit    = n_fetch,
                          offset   = offset,
                          since_id = since_id),
      error = function(e) {
        cli::cli_warn("Batch at offset {offset} failed: {conditionMessage(e)}")
        data.frame()
      }
    )

    if (nrow(batch) == 0L) break

    collected[[length(collected) + 1L]] <- batch
    fetched <- nrow(batch)
    total   <- total + fetched
    offset  <- offset + fetched

    cli::cli_progress_update(inc = fetched)

    if (fetched < n_fetch) break
  }

  cli::cli_progress_done()

  if (length(collected) == 0L) {
    cli::cli_inform("No articles found.")
    return(invisible(data.frame()))
  }

  raw_df <- dplyr::bind_rows(collected)
  cli::cli_inform("Fetched {nrow(raw_df)} articles. Normalising…")

  .normalize_articles(raw_df)
}

# ── internal helpers ──────────────────────────────────────────────────────────

#' Normalise the raw API data frame
#' @noRd
.normalize_articles <- function(df) {

  rename_map <- c(
    article_id   = "id",
    title        = "title",
    content      = "content",
    link         = "link",
    feed_id      = "feed_id",
    feed_title   = "feed_title",
    author       = "author",
    published_at = "updated",
    is_unread    = "unread",
    is_starred   = "marked",
    tags         = "tags"
  )

  keep <- intersect(rename_map, names(df))
  df   <- df[, keep, drop = FALSE]
  names(df) <- names(rename_map)[match(keep, rename_map)]

  # Unix timestamp → POSIXct
  if ("published_at" %in% names(df)) {
    df$published_at <- as.POSIXct(
      as.numeric(df$published_at), origin = "1970-01-01", tz = "UTC"
    )
  }

  # Plain text from HTML
  if ("content" %in% names(df)) {
    df$content_text <- .strip_html(df$content)
  }

  # Logical flags
  for (col in c("is_unread", "is_starred")) {
    if (col %in% names(df)) df[[col]] <- as.logical(df[[col]])
  }

  df$article_id <- as.integer(df$article_id)
  df$feed_id    <- as.integer(df$feed_id)
  df$fetched_at <- Sys.time()

  # Drop exact duplicates
  df <- df[!duplicated(df$article_id), ]

  df
}

#' Remove HTML tags and decode common entities (incl. numeric &#NNNN;)
#' @noRd
.strip_html <- function(html) {
  html <- .decode_numeric_entities(html)
  html <- gsub("<[^>]+>",  " ", html)
  html <- gsub("&nbsp;",   " ", html, fixed = TRUE)
  html <- gsub("&amp;",    "&", html, fixed = TRUE)
  html <- gsub("&lt;",     "<", html, fixed = TRUE)
  html <- gsub("&gt;",     ">", html, fixed = TRUE)
  html <- gsub("&quot;",  '"',  html, fixed = TRUE)
  html <- gsub("&apos;",  "'",  html, fixed = TRUE)
  html <- gsub("&#39;",   "'",  html, fixed = TRUE)
  html <- gsub("\\s+",     " ", html)
  trimws(html)
}

#' Decode numeric HTML entities &#NNNN; → UTF-8 character
#' @noRd
.decode_numeric_entities <- function(x) {
  vapply(x, function(s) {
    if (is.na(s) || !nzchar(s)) return(s)
    m   <- gregexpr("&#[0-9]+;", s)
    ent <- regmatches(s, m)[[1]]
    if (length(ent) == 0L) return(s)
    for (e in unique(ent)) {
      code <- as.integer(substring(e, 3L, nchar(e) - 1L))
      ch   <- tryCatch(intToUtf8(code), error = function(e) "")
      s    <- gsub(e, ch, s, fixed = TRUE)
    }
    s
  }, character(1L), USE.NAMES = FALSE)
}
