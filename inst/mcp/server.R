## ============================================================
## MCP Server для TT-RSS Analytics
## Реализует Model Context Protocol (JSON-RPC 2.0) поверх HTTP
## через пакет plumber.
##
## Транспорт: HTTP POST /mcp  (streamable HTTP)
## Порт:      8000 (по умолчанию)
## ============================================================

library(plumber)
library(jsonlite)
library(DBI)
source("/pkg/ttrssR/R/db.R")

# ── Подключение к ClickHouse (единожды при старте) ────────────────────────────
.con <- local({
  tryCatch(
    ch_connect(),
    error = function(e) {
      message("ClickHouse недоступен: ", conditionMessage(e))
      NULL
    }
  )
})

# ── Вспомогательные функции ───────────────────────────────────────────────────

.mcp_ok <- function(id, result) {
  list(jsonrpc = "2.0", id = id, result = result)
}

.mcp_err <- function(id, code, message) {
  list(jsonrpc  = "2.0",
       id       = id,
       error    = list(code = code, message = message))
}

.require_con <- function(id) {
  if (is.null(.con)) {
    stop(.mcp_err(id, -32000L, "ClickHouse недоступен"))
  }
}

.cap_limit <- function(x, default = 10L, max_limit = 100L) {
  lim <- suppressWarnings(as.integer(x %||% default))
  if (is.na(lim) || lim <= 0L) return(default)
  min(lim, max_limit)
}

.quote_sql <- function(value) {
  as.character(DBI::dbQuoteString(.con, as.character(value)))
}

.escape_like <- function(value) {
  gsub("([%_\\\\])", "\\\\\\1", as.character(value), perl = TRUE)
}

.date_or_null <- function(value) {
  if (is.null(value) || !nzchar(value)) return(NULL)
  d <- suppressWarnings(as.Date(as.character(value)))
  if (is.na(d)) return(NULL)
  as.character(d)
}

# ── Список инструментов ───────────────────────────────────────────────────────

.tools <- list(
  list(
    name        = "search_articles",
    description = "Поиск новостных статей по ключевым словам и/или теме.",
    inputSchema = list(
      type       = "object",
      properties = list(
        query    = list(type = "string",
                        description = "Поисковый запрос (подстрока в заголовке или тексте)"),
        topic    = list(type = "string",
                        description = "Фильтр по метке темы (необязательно)"),
        feed_title = list(type = "string",
                          description = "Фильтр по названию источника (необязательно)"),
        date_from = list(type = "string",
                         description = "Нижняя граница даты (YYYY-MM-DD, необязательно)"),
        date_to = list(type = "string",
                       description = "Верхняя граница даты (YYYY-MM-DD, необязательно)"),
        limit    = list(type = "integer",
                        description = "Максимум результатов (по умолч. 10, max 100)", default = 10L)
      ),
      required = list("query")
    )
  ),
  list(
    name        = "get_topic_summary",
    description = "Статистика по тематическим кластерам: кол-во статей на тему.",
    inputSchema = list(
      type       = "object",
      properties = list(
        top_n = list(type = "integer",
                     description = "Вернуть top-N тем (по умолч. 20)", default = 20L)
      )
    )
  ),
  list(
    name        = "get_recent_articles",
    description = "Возвращает последние N статей, опционально фильтруя по теме.",
    inputSchema = list(
      type       = "object",
      properties = list(
        topic = list(type = "string",
                     description = "Фильтр по теме (необязательно)"),
        limit = list(type = "integer",
                     description = "Кол-во статей (по умолч. 10, max 100)", default = 10L)
      )
    )
  ),
  list(
    name        = "get_feed_stats",
    description = "Статистика по источникам (RSS-лентам): кол-во статей на источник.",
    inputSchema = list(type = "object", properties = list())
  )
)

# ── Список ресурсов ───────────────────────────────────────────────────────────

.resources <- list(
  list(
    uri         = "ttrss://articles",
    name        = "Articles",
    description = "Все собранные и классифицированные статьи в ClickHouse.",
    mimeType    = "application/json"
  ),
  list(
    uri         = "ttrss://topics",
    name        = "Topics",
    description = "Сводная таблица тем с количеством статей.",
    mimeType    = "application/json"
  )
)

# ── Обработчики MCP-методов ───────────────────────────────────────────────────

.handle <- function(method, params, id) {

  switch(method,

    # Handshake
    "initialize" = .mcp_ok(id, list(
      protocolVersion = "2024-11-05",
      capabilities    = list(
        tools     = list(listChanged = FALSE),
        resources = list(listChanged = FALSE)
      ),
      serverInfo = list(name = "ttrssR-mcp", version = "0.1.0")
    )),

    "notifications/initialized" = NULL,   # fire-and-forget

    # Tools
    "tools/list" = .mcp_ok(id, list(tools = .tools)),

    "tools/call" = {
      tool_name <- params$name
      args      <- params$arguments %||% list()

      result <- tryCatch({
        .require_con(id)

        switch(tool_name,

          "search_articles" = {
            q     <- args$query %||% ""
            topic <- args$topic %||% NULL
            feed_title <- args$feed_title %||% NULL
            date_from <- .date_or_null(args$date_from %||% NULL)
            date_to <- .date_or_null(args$date_to %||% NULL)
            lim   <- .cap_limit(args$limit %||% 10L)

            q_pattern <- .quote_sql(paste0("%", .escape_like(q), "%"))
            filters <- c(
              sprintf(
                "(lower(title) LIKE lower(%s) ESCAPE '\\\\' OR lower(content_text) LIKE lower(%s) ESCAPE '\\\\')",
                q_pattern, q_pattern
              )
            )
            if (!is.null(topic) && nzchar(topic)) {
              filters <- c(filters, sprintf("topic_label = %s", .quote_sql(topic)))
            }
            if (!is.null(feed_title) && nzchar(feed_title)) {
              filters <- c(filters, sprintf("feed_title = %s", .quote_sql(feed_title)))
            }
            if (!is.null(date_from)) {
              filters <- c(filters, sprintf("published_at >= toDateTime(%s)", .quote_sql(date_from)))
            }
            if (!is.null(date_to)) {
              filters <- c(filters, sprintf("published_at < toDateTime(%s) + INTERVAL 1 DAY", .quote_sql(date_to)))
            }
            where <- paste(filters, collapse = " AND ")
            df <- ch_read_articles(.con, where = where, limit = lim)
            df <- df[, intersect(c("article_id","title","feed_title",
                                    "topic_label","link","published_at"), names(df))]
            toJSON(df, auto_unbox = TRUE, dataframe = "rows")
          },

          "get_topic_summary" = {
            top_n <- as.integer(args$top_n %||% 20L)
            df <- ch_topic_summary(.con)
            df <- head(df, top_n)
            toJSON(df, auto_unbox = TRUE, dataframe = "rows")
          },

          "get_recent_articles" = {
            topic <- args$topic %||% NULL
            lim   <- .cap_limit(args$limit %||% 10L)
            where <- if (!is.null(topic) && nzchar(topic)) {
              sprintf("topic_label = %s", .quote_sql(topic))
            } else NULL
            df <- ch_read_articles(.con, where = where, limit = lim)
            df <- df[, intersect(c("article_id","title","feed_title",
                                    "topic_label","link","published_at"), names(df))]
            toJSON(df, auto_unbox = TRUE, dataframe = "rows")
          },

          "get_feed_stats" = {
            df <- DBI::dbGetQuery(.con, "
              SELECT feed_title, count() AS n_articles
              FROM articles FINAL
              GROUP BY feed_title
              ORDER BY n_articles DESC
              LIMIT 50
            ")
            toJSON(df, auto_unbox = TRUE, dataframe = "rows")
          },

          stop(sprintf("Unknown tool: %s", tool_name))
        )
      }, error = function(e) conditionMessage(e))

      if (inherits(result, "list") && !is.null(result$error)) return(result)

      .mcp_ok(id, list(
        content = list(list(type = "text", text = result))
      ))
    },

    # Resources
    "resources/list" = .mcp_ok(id, list(resources = .resources)),

    "resources/read" = {
      uri <- params$uri %||% ""
      tryCatch({
        .require_con(id)
        text <- switch(uri,
          "ttrss://articles" = {
            df <- ch_read_articles(.con, limit = 100L)
            toJSON(df, auto_unbox = TRUE, dataframe = "rows")
          },
          "ttrss://topics" = {
            df <- ch_topic_summary(.con)
            toJSON(df, auto_unbox = TRUE, dataframe = "rows")
          },
          stop(sprintf("Unknown resource URI: %s", uri))
        )
        .mcp_ok(id, list(
          contents = list(list(uri = uri, mimeType = "application/json", text = text))
        ))
      }, error = function(e) .mcp_err(id, -32000L, conditionMessage(e)))
    },

    # Default
    .mcp_err(id, -32601L, paste("Method not found:", method))
  )
}

# ── Plumber endpoint ──────────────────────────────────────────────────────────

#* @post /mcp
#* @serializer unboxedJSON
function(req, res) {
  body <- tryCatch(
    fromJSON(req$postBody, simplifyVector = FALSE),
    error = function(e) NULL
  )

  if (is.null(body)) {
    return(.mcp_err(NULL, -32700L, "Parse error"))
  }

  id     <- body$id     %||% NULL
  method <- body$method %||% ""
  params <- body$params %||% list()

  result <- .handle(method, params, id)
  if (is.null(result)) return(invisible(NULL))   # notifications

  # Streamable HTTP: ответ либо JSON, либо SSE
  accept <- req$HTTP_ACCEPT %||% ""
  if (grepl("text/event-stream", accept, fixed = TRUE)) {
    res$setHeader("Content-Type", "text/event-stream")
    res$setHeader("Cache-Control", "no-cache")
    json_str <- toJSON(result, auto_unbox = TRUE)
    return(paste0("event: message\ndata: ", json_str, "\n\n"))
  }
  result
}

#* @get /mcp
#* MCP Streamable HTTP — SSE channel (server-to-client, not used in this impl)
function(req, res) {
  res$setHeader("Content-Type", "text/event-stream")
  res$setHeader("Cache-Control", "no-cache")
  res$setHeader("Connection", "keep-alive")
  res$setHeader("Access-Control-Allow-Origin", "*")
  # Отправляем endpoint event согласно MCP Streamable HTTP spec
  "event: endpoint\ndata: /mcp\n\n"
}

#* @get /health
function() list(status = "ok", server = "ttrssR-mcp")

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
