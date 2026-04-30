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
  if (!is.data.frame(df)) {
    cli::cli_abort("{.arg df} must be a data frame.")
  }

  if (nrow(df) == 0L) {
    cli::cli_warn("Empty data frame — nothing written.")
    return(invisible(df))
  }

  if (!"article_id" %in% names(df)) {
    cli::cli_abort("Column {.field article_id} not found in {.arg df}.")
  }

  # article_id is the core entity id. Rows without it are invalid.
  df <- df[!is.na(df$article_id), , drop = FALSE]

  if (nrow(df) == 0L) {
    cli::cli_warn("No rows with non-missing article_id — nothing written.")
    return(invisible(df))
  }

  # ClickHouse table columns are non-nullable, so replace NA before insert.
  char_defaults <- c(
    title        = "",
    content      = "",
    content_text = "",
    link         = "",
    feed_title   = "",
    author       = "",
    topic_label  = ""
  )

  for (col in names(char_defaults)) {
    if (!col %in% names(df)) {
      df[[col]] <- char_defaults[[col]]
    }

    df[[col]] <- as.character(df[[col]])
    df[[col]][is.na(df[[col]])] <- char_defaults[[col]]
  }

  int_defaults <- c(
    article_id = 0L,
    feed_id    = 0L,
    topic      = 0L,
    is_unread  = 0L,
    is_starred = 0L
  )

  for (col in names(int_defaults)) {
    if (!col %in% names(df)) {
      df[[col]] <- int_defaults[[col]]
    }

    df[[col]][is.na(df[[col]])] <- int_defaults[[col]]
    df[[col]] <- as.integer(df[[col]])
  }

  if (!"topic_prob" %in% names(df)) {
    df$topic_prob <- 0
  }
  df$topic_prob[is.na(df$topic_prob)] <- 0
  df$topic_prob <- as.numeric(df$topic_prob)

  if (!"published_at" %in% names(df)) {
    df$published_at <- Sys.time()
  }
  df$published_at[is.na(df$published_at)] <- Sys.time()
  df$published_at <- as.POSIXct(df$published_at, tz = "UTC")

  if (!"fetched_at" %in% names(df)) {
    df$fetched_at <- Sys.time()
  }
  df$fetched_at[is.na(df$fetched_at)] <- Sys.time()
  df$fetched_at <- as.POSIXct(df$fetched_at, tz = "UTC")

  table_cols <- c(
    "article_id",
    "title",
    "content",
    "content_text",
    "link",
    "feed_id",
    "feed_title",
    "author",
    "published_at",
    "fetched_at",
    "is_unread",
    "is_starred",
    "topic",
    "topic_label",
    "topic_prob"
  )

  df <- df[, table_cols, drop = FALSE]

  DBI::dbWriteTable(
    con,
    "articles",
    df,
    append = TRUE,
    overwrite = FALSE,
    row.names = FALSE
  )

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
