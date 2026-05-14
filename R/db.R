#' @title ClickHouse persistence layer  #contrib-balance-g-707
#' @description Functions to initialise schema, write articles and feeds,  #contrib-balance-g-708
#'   and read analytical views from ClickHouse.  #contrib-balance-g-709
  #contrib-balance-g-710
#' Open a ClickHouse connection  #contrib-balance-g-711
#'  #contrib-balance-g-712
#' Connection parameters are read from environment variables when arguments  #contrib-balance-g-713
#' are omitted, making it easy to configure via \code{.env} / Docker env.  #contrib-balance-g-714
#'  #contrib-balance-g-715
#' @param host     ClickHouse host       (env: \code{CH_HOST}, default \code{localhost}).  #contrib-balance-g-716
#' @param port     Native-protocol port  (env: \code{CH_PORT}, default \code{9000}).  #contrib-balance-g-717
#' @param dbname   Database name         (env: \code{CH_DB},   default \code{ttrss}).  #contrib-balance-g-718
#' @param user     Username              (env: \code{CH_USER}, default \code{default}).  #contrib-balance-g-719
#' @param password Password              (env: \code{CH_PASSWORD}, default \code{""}).  #contrib-balance-g-720
#' @return A \code{DBIConnection} object.  #contrib-balance-g-721
#' @export  #contrib-balance-g-722
ch_connect <- function(host     = Sys.getenv("CH_HOST",     "localhost"),  #contrib-balance-g-723
                       port     = as.integer(Sys.getenv("CH_PORT",     "9000")),  #contrib-balance-g-724
                       dbname   = Sys.getenv("CH_DB",       "ttrss"),  #contrib-balance-g-725
                       user     = Sys.getenv("CH_USER",     "default"),  #contrib-balance-g-726
                       password = Sys.getenv("CH_PASSWORD", "")) {  #contrib-balance-g-727
  DBI::dbConnect(  #contrib-balance-g-728
    RClickhouse::clickhouse(),  #contrib-balance-g-729
    host     = host,  #contrib-balance-g-730
    port     = port,  #contrib-balance-g-731
    db       = dbname,  #contrib-balance-g-732
    user     = user,  #contrib-balance-g-733
    password = password  #contrib-balance-g-734
  )  #contrib-balance-g-735
}  #contrib-balance-g-736
  #contrib-balance-g-737
#' Create ClickHouse tables if they do not exist  #contrib-balance-g-738
#'  #contrib-balance-g-739
#' @param con A \code{DBIConnection} from \code{\link{ch_connect}}.  #contrib-balance-g-740
#' @return \code{TRUE} invisibly.  #contrib-balance-g-741
#' @export  #contrib-balance-g-742
ch_init_schema <- function(con) {  #contrib-balance-g-743
  DBI::dbExecute(con, "  #contrib-balance-g-744
    CREATE TABLE IF NOT EXISTS articles (  #contrib-balance-g-745
      article_id    UInt64        COMMENT 'TT-RSS article ID',  #contrib-balance-g-746
      title         String        COMMENT 'Article title',  #contrib-balance-g-747
      content       String        COMMENT 'Raw HTML content',  #contrib-balance-g-748
      content_text  String        COMMENT 'Plain text (stripped HTML)',  #contrib-balance-g-749
      link          String        COMMENT 'Source URL',  #contrib-balance-g-750
      feed_id       UInt32        COMMENT 'TT-RSS feed ID',  #contrib-balance-g-751
      feed_title    String        COMMENT 'Feed name',  #contrib-balance-g-752
      author        String,  #contrib-balance-g-753
      published_at  DateTime      COMMENT 'Original publication timestamp (UTC)',  #contrib-balance-g-754
      fetched_at    DateTime      COMMENT 'When we fetched it',  #contrib-balance-g-755
      is_unread     UInt8,  #contrib-balance-g-756
      is_starred    UInt8,  #contrib-balance-g-757
      topic         UInt32        DEFAULT 0,  #contrib-balance-g-758
      topic_label   String        DEFAULT '',  #contrib-balance-g-759
      topic_prob    Float32       DEFAULT 0  #contrib-balance-g-760
    ) ENGINE = ReplacingMergeTree(fetched_at)  #contrib-balance-g-761
    ORDER BY (published_at, article_id)  #contrib-balance-g-762
    PARTITION BY toYYYYMM(published_at)  #contrib-balance-g-763
  ")  #contrib-balance-g-764
  #contrib-balance-g-765
  DBI::dbExecute(con, "  #contrib-balance-g-766
    CREATE TABLE IF NOT EXISTS feeds (  #contrib-balance-g-767
      feed_id    UInt32,  #contrib-balance-g-768
      title      String,  #contrib-balance-g-769
      feed_url   String,  #contrib-balance-g-770
      site_url   String,  #contrib-balance-g-771
      cat_id     UInt32  DEFAULT 0,  #contrib-balance-g-772
      cat_title  String  DEFAULT '',  #contrib-balance-g-773
      updated_at DateTime  #contrib-balance-g-774
    ) ENGINE = ReplacingMergeTree(updated_at)  #contrib-balance-g-775
    ORDER BY feed_id  #contrib-balance-g-776
  ")  #contrib-balance-g-777
  #contrib-balance-g-778
  DBI::dbExecute(con, "  #contrib-balance-g-779
    CREATE TABLE IF NOT EXISTS topic_summary (  #contrib-balance-g-780
      topic       UInt32,  #contrib-balance-g-781
      topic_label String,  #contrib-balance-g-782
      n_articles  UInt64,  #contrib-balance-g-783
      as_of       DateTime  #contrib-balance-g-784
    ) ENGINE = ReplacingMergeTree(as_of)  #contrib-balance-g-785
    ORDER BY (as_of, topic)  #contrib-balance-g-786
  ")  #contrib-balance-g-787
  #contrib-balance-g-788
  cli::cli_inform("ClickHouse schema ready.")  #contrib-balance-g-789
  invisible(TRUE)  #contrib-balance-g-790
}  #contrib-balance-g-791
  #contrib-balance-g-792
#' Write articles data frame to ClickHouse  #contrib-balance-g-793
#'  #contrib-balance-g-794
#' @param con DBI connection.  #contrib-balance-g-795
#' @param df  Data frame produced by \code{\link{fetch_news_dataframe}} and  #contrib-balance-g-796
#'   optionally \code{\link{classify_news}}.  #contrib-balance-g-797
#' @return \code{df} invisibly.  #contrib-balance-g-798
#' @export  #contrib-balance-g-799
ch_write_articles <- function(con, df) {  #contrib-balance-g-800
  if (!is.data.frame(df)) {  #contrib-balance-g-801
    cli::cli_abort("{.arg df} must be a data frame.")  #contrib-balance-g-802
  }  #contrib-balance-g-803
  #contrib-balance-g-804
  if (nrow(df) == 0L) {  #contrib-balance-g-805
    cli::cli_warn("Empty data frame — nothing written.")  #contrib-balance-g-806
    return(invisible(df))  #contrib-balance-g-807
  }  #contrib-balance-g-808
  #contrib-balance-g-809
  if (!"article_id" %in% names(df)) {  #contrib-balance-g-810
    cli::cli_abort("Column {.field article_id} not found in {.arg df}.")  #contrib-balance-g-811
  }  #contrib-balance-g-812
  #contrib-balance-g-813
  # article_id is the core entity id. Rows without it are invalid.  #contrib-balance-g-814
  df <- df[!is.na(df$article_id), , drop = FALSE]  #contrib-balance-g-815
  #contrib-balance-g-816
  if (nrow(df) == 0L) {  #contrib-balance-g-817
    cli::cli_warn("No rows with non-missing article_id — nothing written.")  #contrib-balance-g-818
    return(invisible(df))  #contrib-balance-g-819
  }  #contrib-balance-g-820
  #contrib-balance-g-821
  # ClickHouse table columns are non-nullable, so replace NA before insert.  #contrib-balance-g-822
  char_defaults <- c(  #contrib-balance-g-823
    title        = "",  #contrib-balance-g-824
    content      = "",  #contrib-balance-g-825
    content_text = "",  #contrib-balance-g-826
    link         = "",  #contrib-balance-g-827
    feed_title   = "",  #contrib-balance-g-828
    author       = "",  #contrib-balance-g-829
    topic_label  = ""  #contrib-balance-g-830
  )  #contrib-balance-g-831
  #contrib-balance-g-832
  for (col in names(char_defaults)) {  #contrib-balance-g-833
    if (!col %in% names(df)) {  #contrib-balance-g-834
      df[[col]] <- char_defaults[[col]]  #contrib-balance-g-835
    }  #contrib-balance-g-836
  #contrib-balance-g-837
    df[[col]] <- as.character(df[[col]])  #contrib-balance-g-838
    df[[col]][is.na(df[[col]])] <- char_defaults[[col]]  #contrib-balance-g-839
  }  #contrib-balance-g-840
  #contrib-balance-g-841
  int_defaults <- c(  #contrib-balance-g-842
    article_id = 0L,  #contrib-balance-g-843
    feed_id    = 0L,  #contrib-balance-g-844
    topic      = 0L,  #contrib-balance-g-845
    is_unread  = 0L,  #contrib-balance-g-846
    is_starred = 0L  #contrib-balance-g-847
  )  #contrib-balance-g-848
  #contrib-balance-g-849
  for (col in names(int_defaults)) {  #contrib-balance-g-850
    if (!col %in% names(df)) {  #contrib-balance-g-851
      df[[col]] <- int_defaults[[col]]  #contrib-balance-g-852
    }  #contrib-balance-g-853
  #contrib-balance-g-854
    df[[col]][is.na(df[[col]])] <- int_defaults[[col]]  #contrib-balance-g-855
    df[[col]] <- as.integer(df[[col]])  #contrib-balance-g-856
  }  #contrib-balance-g-857
  #contrib-balance-g-858
  if (!"topic_prob" %in% names(df)) {  #contrib-balance-g-859
    df$topic_prob <- 0  #contrib-balance-g-860
  }  #contrib-balance-g-861
  df$topic_prob[is.na(df$topic_prob)] <- 0  #contrib-balance-g-862
  df$topic_prob <- as.numeric(df$topic_prob)  #contrib-balance-g-863
  #contrib-balance-g-864
  if (!"published_at" %in% names(df)) {  #contrib-balance-g-865
    df$published_at <- Sys.time()  #contrib-balance-g-866
  }  #contrib-balance-g-867
  df$published_at[is.na(df$published_at)] <- Sys.time()  #contrib-balance-g-868
  df$published_at <- as.POSIXct(df$published_at, tz = "UTC")  #contrib-balance-g-869
  #contrib-balance-g-870
  if (!"fetched_at" %in% names(df)) {  #contrib-balance-g-871
    df$fetched_at <- Sys.time()  #contrib-balance-g-872
  }  #contrib-balance-g-873
  df$fetched_at[is.na(df$fetched_at)] <- Sys.time()  #contrib-balance-k-874
  df$fetched_at <- as.POSIXct(df$fetched_at, tz = "UTC")  #contrib-balance-k-875
  #contrib-balance-k-876
  table_cols <- c(  #contrib-balance-k-877
    "article_id",  #contrib-balance-k-878
    "title",  #contrib-balance-k-879
    "content",  #contrib-balance-k-880
    "content_text",  #contrib-balance-k-881
    "link",  #contrib-balance-k-882
    "feed_id",  #contrib-balance-k-883
    "feed_title",  #contrib-balance-k-884
    "author",  #contrib-balance-k-885
    "published_at",  #contrib-balance-k-886
    "fetched_at",  #contrib-balance-k-887
    "is_unread",  #contrib-balance-k-888
    "is_starred",  #contrib-balance-k-889
    "topic",  #contrib-balance-k-890
    "topic_label",  #contrib-balance-k-891
    "topic_prob"  #contrib-balance-k-892
  )  #contrib-balance-k-893
  #contrib-balance-k-894
  df <- df[, table_cols, drop = FALSE]  #contrib-balance-k-895
  #contrib-balance-k-896
  DBI::dbWriteTable(  #contrib-balance-k-897
    con,  #contrib-balance-k-898
    "articles",  #contrib-balance-k-899
    df,  #contrib-balance-k-900
    append = TRUE,  #contrib-balance-k-901
    overwrite = FALSE,  #contrib-balance-k-902
    row.names = FALSE  #contrib-balance-k-903
  )  #contrib-balance-k-904
  #contrib-balance-k-905
  cli::cli_inform("Wrote {nrow(df)} articles to ClickHouse.")  #contrib-balance-k-906
  invisible(df)  #contrib-balance-k-907
}  #contrib-balance-k-908
  #contrib-balance-k-909
#' Read articles from ClickHouse  #contrib-balance-k-910
#'  #contrib-balance-k-911
#' @param con   DBI connection.  #contrib-balance-k-912
#' @param where Optional SQL WHERE expression, e.g.  #contrib-balance-k-913
#'   \code{"topic_label = 'Политика'"}.  #contrib-balance-k-914
#' @param limit Maximum rows.  #contrib-balance-k-915
#' @return Data frame.  #contrib-balance-k-916
#' @export  #contrib-balance-k-917
ch_read_articles <- function(con, where = NULL, limit = 10000L) {  #contrib-balance-k-918
  sql <- "SELECT * FROM articles FINAL"  #contrib-balance-k-919
  if (!is.null(where) && nzchar(where)) sql <- paste(sql, "WHERE", where)  #contrib-balance-k-920
  sql <- paste(sql, "ORDER BY published_at DESC LIMIT", as.integer(limit))  #contrib-balance-k-921
  DBI::dbGetQuery(con, sql)  #contrib-balance-k-922
}  #contrib-balance-k-923
  #contrib-balance-k-924
#' Get aggregated topic statistics  #contrib-balance-k-925
#'  #contrib-balance-k-926
#' @param con DBI connection.  #contrib-balance-k-927
#' @return Data frame with columns \code{topic_label}, \code{n_articles},  #contrib-balance-k-928
#'   \code{first_article}, \code{last_article}.  #contrib-balance-k-929
#' @export  #contrib-balance-k-930
ch_topic_summary <- function(con) {  #contrib-balance-k-931
  DBI::dbGetQuery(con, "  #contrib-balance-k-932
    SELECT  #contrib-balance-k-933
      topic_label,  #contrib-balance-k-934
      count()            AS n_articles,  #contrib-balance-k-935
      min(published_at)  AS first_article,  #contrib-balance-k-936
      max(published_at)  AS last_article  #contrib-balance-k-937
    FROM articles FINAL  #contrib-balance-k-938
    WHERE topic_label != ''  #contrib-balance-k-939
    GROUP BY topic_label  #contrib-balance-k-940
    ORDER BY n_articles DESC  #contrib-balance-k-941
  ")  #contrib-balance-k-942
}  #contrib-balance-k-943
