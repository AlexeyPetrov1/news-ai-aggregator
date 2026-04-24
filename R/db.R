#' @title ClickHouse persistence layer
#' @description Functions to initialise schema, write articles and feeds,
#'   and read analytical views from ClickHouse.

#' Open a ClickHouse connection
#'
#' Connection parameters are read from environment variables when arguments
#' are omitted, making it easy to configure via \code{.env} / Docker env.
#'
#' @param host     ClickHouse host       (env: \code{CH_HOST}, default \code{localhost}).
#' @param port     Native-protocol port  (env: \code{CH_PORT}, default \code{9000}).
#' @param dbname   Database name         (env: \code{CH_DB},   default \code{ttrss}).
#' @param user     Username              (env: \code{CH_USER}, default \code{default}).
#' @param password Password              (env: \code{CH_PASSWORD}, default \code{""}).
#' @return A \code{DBIConnection} object.
#' @export
ch_connect <- function(host     = Sys.getenv("CH_HOST",     "localhost"),
                       port     = as.integer(Sys.getenv("CH_PORT",     "9000")),
                       dbname   = Sys.getenv("CH_DB",       "ttrss"),
                       user     = Sys.getenv("CH_USER",     "default"),
                       password = Sys.getenv("CH_PASSWORD", "")) {
  DBI::dbConnect(
    RClickhouse::clickhouse(),
    host     = host,
    port     = port,
    db       = dbname,
    user     = user,
    password = password
  )
}

#' Create ClickHouse tables if they do not exist
#'
#' @param con A \code{DBIConnection} from \code{\link{ch_connect}}.
#' @return \code{TRUE} invisibly.
#' @export
ch_init_schema <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS articles (
      article_id    UInt64        COMMENT 'TT-RSS article ID',
      title         String        COMMENT 'Article title',
      content       String        COMMENT 'Raw HTML content',
      content_text  String        COMMENT 'Plain text (stripped HTML)',
      link          String        COMMENT 'Source URL',
      feed_id       UInt32        COMMENT 'TT-RSS feed ID',
      feed_title    String        COMMENT 'Feed name',
      author        String,
      published_at  DateTime      COMMENT 'Original publication timestamp (UTC)',
      fetched_at    DateTime      COMMENT 'When we fetched it',
      is_unread     UInt8,
      is_starred    UInt8,
      topic         UInt32        DEFAULT 0,
      topic_label   String        DEFAULT '',
      topic_prob    Float32       DEFAULT 0
    ) ENGINE = ReplacingMergeTree(fetched_at)
    ORDER BY (published_at, article_id)
    PARTITION BY toYYYYMM(published_at)
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS feeds (
      feed_id    UInt32,
      title      String,
      feed_url   String,
      site_url   String,
      cat_id     UInt32  DEFAULT 0,
      cat_title  String  DEFAULT '',
      updated_at DateTime
    ) ENGINE = ReplacingMergeTree(updated_at)
    ORDER BY feed_id
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS topic_summary (
      topic       UInt32,
      topic_label String,
      n_articles  UInt64,
      as_of       DateTime
    ) ENGINE = ReplacingMergeTree(as_of)
    ORDER BY (as_of, topic)
  ")

  cli::cli_inform("ClickHouse schema ready.")
  invisible(TRUE)
}

#' Write articles data frame to ClickHouse
#'
#' @param con DBI connection.
#' @param df  Data frame produced by \code{\link{fetch_news_dataframe}} and
#'   optionally \code{\link{classify_news}}.
#' @return \code{df} invisibly.
#' @export
ch_write_articles <- function(con, df) {
  if (nrow(df) == 0L) {
    cli::cli_warn("Empty data frame — nothing written.")
    return(invisible(df))
  }

  # Ensure required columns exist with defaults
  defaults <- list(
    topic       = 0L,
    topic_label = "",
    topic_prob  = 0
  )
  for (col in names(defaults)) {
    if (!col %in% names(df)) df[[col]] <- defaults[[col]]
  }

  # ClickHouse expects integer 0/1 for UInt8
  for (col in c("is_unread", "is_starred")) {
    if (col %in% names(df)) df[[col]] <- as.integer(df[[col]])
  }

  # Only keep table columns
  table_cols <- c("article_id", "title", "content", "content_text", "link",
                  "feed_id", "feed_title", "author", "published_at",
                  "fetched_at", "is_unread", "is_starred",
                  "topic", "topic_label", "topic_prob")
  df <- df[, intersect(table_cols, names(df)), drop = FALSE]

  DBI::dbWriteTable(con, "articles", df, append = TRUE, overwrite = FALSE)
  cli::cli_inform("Wrote {nrow(df)} articles to ClickHouse.")
  invisible(df)
}

#' Read articles from ClickHouse
#'
#' @param con   DBI connection.
#' @param where Optional SQL WHERE expression, e.g.
#'   \code{"topic_label = 'Политика'"}.
#' @param limit Maximum rows.
#' @return Data frame.
#' @export
ch_read_articles <- function(con, where = NULL, limit = 10000L) {
  sql <- "SELECT * FROM articles FINAL"
  if (!is.null(where) && nzchar(where)) sql <- paste(sql, "WHERE", where)
  sql <- paste(sql, "ORDER BY published_at DESC LIMIT", as.integer(limit))
  DBI::dbGetQuery(con, sql)
}

#' Get aggregated topic statistics
#'
#' @param con DBI connection.
#' @return Data frame with columns \code{topic_label}, \code{n_articles},
#'   \code{first_article}, \code{last_article}.
#' @export
ch_topic_summary <- function(con) {
  DBI::dbGetQuery(con, "
    SELECT
      topic_label,
      count()            AS n_articles,
      min(published_at)  AS first_article,
      max(published_at)  AS last_article
    FROM articles FINAL
    WHERE topic_label != ''
    GROUP BY topic_label
    ORDER BY n_articles DESC
  ")
}
