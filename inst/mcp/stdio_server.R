## MCP stdio server для Claude Code
## Claude Code запускает этот скрипт как процесс,
## общается через stdin/stdout в формате JSON-RPC 2.0 (по одному объекту на строку).

suppressPackageStartupMessages({
  library(jsonlite)
  library(DBI)
})

source(file.path(Sys.getenv("TTRSSR_PKG", "D:/prpject_R/ttrssR"), "R/db.R"))

# ── ClickHouse ────────────────────────────────────────────────────────────────
.con <- tryCatch(
  ch_connect(
    host     = Sys.getenv("CH_HOST",     "localhost"),
    port     = as.integer(Sys.getenv("CH_PORT", "9000")),
    dbname   = Sys.getenv("CH_DB",       "ttrss"),
    user     = Sys.getenv("CH_USER",     "default"),
    password = Sys.getenv("CH_PASSWORD", "")
  ),
  error = function(e) { message("[MCP] ClickHouse недоступен: ", e$message); NULL }
)

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

.ok  <- function(id, result) list(jsonrpc = "2.0", id = id, result = result)
.err <- function(id, code, msg) list(jsonrpc = "2.0", id = id,
                                     error = list(code = code, message = msg))

.tools <- list(
  list(name = "search_articles",
       description = "Search cybersecurity articles by keyword and/or topic.",
       inputSchema = list(type = "object",
         properties = list(
           query = list(type = "string", description = "Search term (substring in title or text)"),
           topic = list(type = "string", description = "Filter by topic label (optional)"),
           limit = list(type = "integer", description = "Max results (default 10)", default = 10L)
         ), required = list("query"))),
  list(name = "get_topic_summary",
       description = "Get statistics by topic clusters: article counts per topic.",
       inputSchema = list(type = "object",
         properties = list(
           top_n = list(type = "integer", description = "Top-N topics (default 20)", default = 20L)
         ))),
  list(name = "get_recent_articles",
       description = "Get the most recent N articles, optionally filtered by topic.",
       inputSchema = list(type = "object",
         properties = list(
           topic = list(type = "string", description = "Filter by topic (optional)"),
           limit = list(type = "integer", description = "Number of articles (default 10)", default = 10L)
         ))),
  list(name = "get_feed_stats",
       description = "Statistics by RSS feed sources: article counts per source.",
       inputSchema = list(type = "object", properties = list()))
)

.handle <- function(method, params, id) {
  switch(method,
    "initialize" = .ok(id, list(
      protocolVersion = "2024-11-05",
      capabilities    = list(tools = list(listChanged = FALSE)),
      serverInfo      = list(name = "ttrssR-mcp", version = "0.1.0")
    )),
    "notifications/initialized" = NULL,
    "tools/list" = .ok(id, list(tools = .tools)),
    "tools/call" = {
      if (is.null(.con)) return(.err(id, -32000L, "ClickHouse unavailable"))
      name <- params$name %||% ""
      args <- params$arguments %||% list()
      result <- tryCatch(switch(name,
        "search_articles" = {
          q   <- args$query %||% ""
          lim <- as.integer(args$limit %||% 10L)
          w   <- sprintf("(lower(title) LIKE lower('%%%s%%') OR lower(content_text) LIKE lower('%%%s%%'))", q, q)
          if (!is.null(args$topic) && nzchar(args$topic))
            w <- paste(w, sprintf("AND topic_label = '%s'", args$topic))
          df <- ch_read_articles(.con, where = w, limit = lim)
          df <- df[, intersect(c("article_id","title","feed_title","topic_label","link","published_at"), names(df))]
          toJSON(df, auto_unbox = TRUE, dataframe = "rows")
        },
        "get_topic_summary" = {
          df <- ch_topic_summary(.con)
          toJSON(head(df, as.integer(args$top_n %||% 20L)), auto_unbox = TRUE, dataframe = "rows")
        },
        "get_recent_articles" = {
          lim <- as.integer(args$limit %||% 10L)
          w   <- if (!is.null(args$topic) && nzchar(args$topic %||% ""))
                   sprintf("topic_label = '%s'", args$topic) else NULL
          df <- ch_read_articles(.con, where = w, limit = lim)
          df <- df[, intersect(c("article_id","title","feed_title","topic_label","link","published_at"), names(df))]
          toJSON(df, auto_unbox = TRUE, dataframe = "rows")
        },
        "get_feed_stats" = {
          df <- DBI::dbGetQuery(.con,
            "SELECT feed_title, count() AS n_articles FROM articles FINAL
             GROUP BY feed_title ORDER BY n_articles DESC LIMIT 50")
          toJSON(df, auto_unbox = TRUE, dataframe = "rows")
        },
        stop(paste("Unknown tool:", name))
      ), error = function(e) conditionMessage(e))
      .ok(id, list(content = list(list(type = "text", text = result))))
    },
    .err(id, -32601L, paste("Method not found:", method))
  )
}

# ── Основной цикл stdin/stdout ────────────────────────────────────────────────
con_in <- file("stdin", "r")
repeat {
  line <- tryCatch(readLines(con_in, n = 1L, warn = FALSE), error = function(e) NULL)
  if (is.null(line) || length(line) == 0) break
  if (!nzchar(trimws(line))) next

  msg <- tryCatch(fromJSON(line, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(msg)) next

  resp <- tryCatch(
    .handle(msg$method %||% "", msg$params %||% list(), msg$id %||% NULL),
    error = function(e) .err(msg$id %||% NULL, -32603L, conditionMessage(e))
  )

  if (!is.null(resp)) {
    cat(toJSON(resp, auto_unbox = TRUE), "\n", sep = "")
    flush(stdout())
  }
}
