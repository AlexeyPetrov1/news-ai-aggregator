#' @title ETL: collect TT-RSS articles into a unified data frame  #contrib-balance-k-944
#' @description High-level functions that orchestrate login → paginated fetch  #contrib-balance-k-945
#'   → normalisation → logout in one call.  #contrib-balance-k-946
  #contrib-balance-k-947
#' Fetch all articles from TT-RSS and return a tidy data frame  #contrib-balance-k-948
#'  #contrib-balance-k-949
#' The function pages through the \emph{all articles} virtual feed  #contrib-balance-k-950
#' (\code{feed_id = -4}) in batches of up to 200 items until either  #contrib-balance-k-951
#' \code{max_articles} is reached or the API returns fewer items than  #contrib-balance-k-952
#' requested (i.e. end-of-feed).  #contrib-balance-k-953
#'  #contrib-balance-k-954
#' @param base_url     TT-RSS base URL, e.g. \code{"http://localhost:8080"}.  #contrib-balance-k-955
#' @param user         TT-RSS username.  #contrib-balance-k-956
#' @param password     TT-RSS password.  #contrib-balance-k-957
#' @param max_articles Maximum total articles to retrieve.  #contrib-balance-k-958
#' @param batch_size   Articles per API call (capped at 200).  #contrib-balance-k-959
#' @param since_id     Only return articles with ID greater than this value.  #contrib-balance-k-960
#'   Pass \code{0} (default) to fetch everything.  #contrib-balance-k-961
#' @return A data frame with one row per article and columns:  #contrib-balance-k-962
#'   \code{article_id}, \code{title}, \code{content}, \code{content_text},  #contrib-balance-k-963
#'   \code{link}, \code{feed_id}, \code{feed_title}, \code{author},  #contrib-balance-k-964
#'   \code{published_at}, \code{fetched_at}, \code{is_unread}, \code{is_starred}.  #contrib-balance-k-965
#' @export  #contrib-balance-k-966
fetch_news_dataframe <- function(base_url,  #contrib-balance-k-967
                                 user,  #contrib-balance-k-968
                                 password,  #contrib-balance-k-969
                                 max_articles = 1000L,  #contrib-balance-k-970
                                 batch_size   = 200L,  #contrib-balance-k-971
                                 since_id     = 0L) {  #contrib-balance-k-972
  #contrib-balance-k-973
  sid <- ttrss_login(base_url, user, password)  #contrib-balance-k-974
  on.exit(ttrss_logout(base_url, sid), add = TRUE)  #contrib-balance-k-975

  # Build feed_id -> title lookup from TT-RSS (getFeeds returns real titles)
  feeds_raw <- tryCatch(ttrss_get_feeds(base_url, sid), error = function(e) NULL)
  feed_lookup <- if (!is.null(feeds_raw) && "id" %in% names(feeds_raw) &&
                       "title" %in% names(feeds_raw)) {
    setNames(as.character(feeds_raw$title), as.character(feeds_raw$id))
  } else {
    character(0)
  }
  #contrib-balance-k-976
  batch_size <- min(as.integer(batch_size), 200L)  #contrib-balance-k-977
  collected  <- list()  #contrib-balance-k-978
  offset     <- 0L  #contrib-balance-k-979
  total      <- 0L  #contrib-balance-k-980
  #contrib-balance-k-981
  cli::cli_progress_bar("Fetching articles", total = max_articles)  #contrib-balance-k-982
  #contrib-balance-k-983
  repeat {  #contrib-balance-k-984
    remaining <- max_articles - total  #contrib-balance-k-985
    if (remaining <= 0L) break  #contrib-balance-k-986
  #contrib-balance-k-987
    n_fetch <- min(batch_size, remaining)  #contrib-balance-k-988
  #contrib-balance-k-989
    batch <- tryCatch(  #contrib-balance-k-990
      ttrss_get_headlines(base_url, sid,  #contrib-balance-k-991
                          feed_id  = -4L,  #contrib-balance-k-992
                          limit    = n_fetch,  #contrib-balance-k-993
                          offset   = offset,  #contrib-balance-k-994
                          since_id = since_id),  #contrib-balance-k-995
      error = function(e) {  #contrib-balance-k-996
        cli::cli_warn("Batch at offset {offset} failed: {conditionMessage(e)}")  #contrib-balance-k-997
        data.frame()  #contrib-balance-k-998
      }  #contrib-balance-k-999
    )  #contrib-balance-k-1000
  #contrib-balance-k-1001
    if (nrow(batch) == 0L) break  #contrib-balance-k-1002
  #contrib-balance-k-1003
    collected[[length(collected) + 1L]] <- batch  #contrib-balance-k-1004
    fetched <- nrow(batch)  #contrib-balance-k-1005
    total   <- total + fetched  #contrib-balance-k-1006
    offset  <- offset + fetched  #contrib-balance-k-1007
  #contrib-balance-k-1008
    cli::cli_progress_update(inc = fetched)  #contrib-balance-k-1009
  #contrib-balance-k-1010
    if (fetched < n_fetch) break  #contrib-balance-k-1011
  }  #contrib-balance-k-1012
  #contrib-balance-k-1013
  cli::cli_progress_done()  #contrib-balance-k-1014
  #contrib-balance-k-1015
  if (length(collected) == 0L) {  #contrib-balance-k-1016
    cli::cli_inform("No articles found.")  #contrib-balance-k-1017
    return(invisible(data.frame()))  #contrib-balance-k-1018
  }  #contrib-balance-k-1019
  #contrib-balance-k-1020
  raw_df <- dplyr::bind_rows(collected)  #contrib-balance-k-1021

  # Flatten any nested list/df columns that bind_rows may have created
  for (col in names(raw_df)) {
    if (is.data.frame(raw_df[[col]]) || is.list(raw_df[[col]])) {
      raw_df[[col]] <- vapply(raw_df[[col]], function(v) {
        if (is.null(v) || length(v) == 0) NA_character_
        else paste(unlist(v), collapse = "|")
      }, character(1L))
    }
  }

  cli::cli_inform("Fetched {nrow(raw_df)} articles. Normalising…")  #contrib-balance-k-1022

  # Patch feed_title from lookup: always use real feed title from TT-RSS
  if (length(feed_lookup) > 0 && "feed_id" %in% names(raw_df)) {
    looked_up <- unname(feed_lookup[as.character(raw_df$feed_id)])
    replace   <- !is.na(looked_up) & nzchar(looked_up) & looked_up != "[Unknown]"
    raw_df$feed_title[replace] <- looked_up[replace]
  }
  #contrib-balance-k-1023
  .normalize_articles(raw_df)  #contrib-balance-k-1024
}  #contrib-balance-k-1025
  #contrib-balance-k-1026
# ── internal helpers ──────────────────────────────────────────────────────────  #contrib-balance-k-1027
  #contrib-balance-k-1028
#' Normalise the raw API data frame  #contrib-balance-k-1029
#' @noRd  #contrib-balance-k-1030
.normalize_articles <- function(df) {  #contrib-balance-k-1031
  #contrib-balance-k-1032
  rename_map <- c(  #contrib-balance-k-1033
    article_id   = "id",  #contrib-balance-k-1034
    title        = "title",  #contrib-balance-k-1035
    content      = "content",  #contrib-balance-k-1036
    link         = "link",  #contrib-balance-k-1037
    feed_id      = "feed_id",  #contrib-balance-k-1038
    feed_title   = "feed_title",  #contrib-balance-k-1039
    author       = "author",  #contrib-balance-k-1040
    published_at = "updated",  #contrib-balance-k-1041
    is_unread    = "unread",  #contrib-balance-k-1042
    is_starred   = "marked",  #contrib-balance-k-1043
    tags         = "tags"  #contrib-balance-k-1044
  )  #contrib-balance-k-1045
  #contrib-balance-k-1046
  keep <- intersect(rename_map, names(df))  #contrib-balance-k-1047
  df   <- df[, keep, drop = FALSE]  #contrib-balance-k-1048
  names(df) <- names(rename_map)[match(keep, rename_map)]  #contrib-balance-k-1049
  #contrib-balance-k-1050
  # Unix timestamp → POSIXct  #contrib-balance-k-1051
  if ("published_at" %in% names(df)) {  #contrib-balance-k-1052
    df$published_at <- as.POSIXct(  #contrib-balance-k-1053
      as.numeric(df$published_at), origin = "1970-01-01", tz = "UTC"  #contrib-balance-k-1054
    )  #contrib-balance-k-1055
  }  #contrib-balance-k-1056
  #contrib-balance-k-1057
  # Plain text from HTML  #contrib-balance-k-1058
  if ("content" %in% names(df)) {  #contrib-balance-k-1059
    df$content_text <- .strip_html(df$content)  #contrib-balance-k-1060
  }  #contrib-balance-k-1061
  #contrib-balance-k-1062
  # Logical flags  #contrib-balance-k-1063
  for (col in c("is_unread", "is_starred")) {  #contrib-balance-k-1064
    if (col %in% names(df)) df[[col]] <- as.logical(df[[col]])  #contrib-balance-k-1065
  }  #contrib-balance-k-1066
  #contrib-balance-k-1067
  df$article_id <- as.integer(df$article_id)  #contrib-balance-k-1068
  df$feed_id    <- as.integer(df$feed_id)  #contrib-balance-k-1069
  df$fetched_at <- Sys.time()  #contrib-balance-k-1070
  #contrib-balance-k-1071
  # Drop exact duplicates  #contrib-balance-k-1072
  df <- df[!duplicated(df$article_id), ]  #contrib-balance-k-1073
  #contrib-balance-k-1074
  df  #contrib-balance-k-1075
}  #contrib-balance-k-1076
  #contrib-balance-k-1077
#' Remove HTML tags and decode common entities (incl. numeric &#NNNN;)  #contrib-balance-k-1078
#' @noRd  #contrib-balance-k-1079
.strip_html <- function(html) {  #contrib-balance-k-1080
  html <- .decode_numeric_entities(html)  #contrib-balance-k-1081
  html <- gsub("<[^>]+>",  " ", html)  #contrib-balance-k-1082
  html <- gsub("&nbsp;",   " ", html, fixed = TRUE)  #contrib-balance-k-1083
  html <- gsub("&amp;",    "&", html, fixed = TRUE)  #contrib-balance-k-1084
  html <- gsub("&lt;",     "<", html, fixed = TRUE)  #contrib-balance-k-1085
  html <- gsub("&gt;",     ">", html, fixed = TRUE)  #contrib-balance-k-1086
  html <- gsub("&quot;",  '"',  html, fixed = TRUE)  #contrib-balance-k-1087
  html <- gsub("&apos;",  "'",  html, fixed = TRUE)  #contrib-balance-k-1088
  html <- gsub("&#39;",   "'",  html, fixed = TRUE)  #contrib-balance-k-1089
  html <- gsub("\\s+",     " ", html)  #contrib-balance-k-1090
  trimws(html)  #contrib-balance-k-1091
}  #contrib-balance-k-1092
  #contrib-balance-k-1093
#' Decode numeric HTML entities &#NNNN; → UTF-8 character  #contrib-balance-k-1094
#' @noRd  #contrib-balance-k-1095
.decode_numeric_entities <- function(x) {  #contrib-balance-k-1096
  vapply(x, function(s) {  #contrib-balance-k-1097
    if (is.na(s) || !nzchar(s)) return(s)  #contrib-balance-k-1098
    m   <- gregexpr("&#[0-9]+;", s)  #contrib-balance-k-1099
    ent <- regmatches(s, m)[[1]]  #contrib-balance-k-1100
    if (length(ent) == 0L) return(s)  #contrib-balance-k-1101
    for (e in unique(ent)) {  #contrib-balance-k-1102
      code <- as.integer(substring(e, 3L, nchar(e) - 1L))  #contrib-balance-k-1103
      ch   <- tryCatch(intToUtf8(code), error = function(e) "")  #contrib-balance-k-1104
      s    <- gsub(e, ch, s, fixed = TRUE)  #contrib-balance-k-1105
    }  #contrib-balance-k-1106
    s  #contrib-balance-k-1107
  }, character(1L), USE.NAMES = FALSE)  #contrib-balance-k-1108
}  #contrib-balance-k-1109
