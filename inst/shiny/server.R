library(shiny)
library(dplyr)
library(ggplot2)
library(plotly)
library(DT)
library(ttrssR)

# Загружаем данные один раз при старте (вне реактивного контекста)
.initial_df <- local({
  candidates <- c(
    "data/news_raw.rds",
    "/srv/shiny-server/ttrss/shiny/data/news_raw.rds"
  )
  rds <- Find(file.exists, candidates)
  if (!is.null(rds)) {
    message("[APP] Loading: ", rds)
    tryCatch(readRDS(rds), error = function(e) { message("[APP] Error: ", e$message); NULL })
  } else {
    message("[APP] No data file found")
    NULL
  }
})
if (!is.null(.initial_df)) message("[APP] Ready: ", nrow(.initial_df), " rows")

server <- function(input, output, session) {

  rv <- reactiveValues(
    df  = .initial_df,
    log = character(0)
  )

  .log <- function(...) {
    msg    <- paste0("[", format(Sys.time(), "%H:%M:%S"), "] ", ...)
    rv$log <- c(rv$log, msg)
  }

  # Обновляем селекторы когда данные появились
  observe({
    df <- rv$df
    req(df)
    topics <- c("Все", sort(unique(df$topic_label[!is.na(df$topic_label) & nzchar(df$topic_label)])))
    feeds  <- c("Все", sort(unique(df$feed_title[!is.na(df$feed_title)])))
    updateSelectInput(session, "art_topic", choices = topics, selected = "Все")
    updateSelectInput(session, "art_feed",  choices = feeds,  selected = "Все")
  })

  # Кнопка сбросить фильтры
  observeEvent(input$btn_refresh, {
    df <- rv$df
    req(df)
    topics <- c("Все", sort(unique(df$topic_label[!is.na(df$topic_label) & nzchar(df$topic_label)])))
    feeds  <- c("Все", sort(unique(df$feed_title[!is.na(df$feed_title)])))
    updateSelectInput(session, "art_topic", choices = topics, selected = "Все")
    updateSelectInput(session, "art_feed",  choices = feeds,  selected = "Все")
  })

  # Кнопка: собрать новости
  observeEvent(input$btn_fetch, {
    .log("Запуск сбора…")
    withProgress(message = "Сбор новостей…", {
      tryCatch({
        df <- fetch_news_dataframe(
          base_url     = input$cfg_ttrss_url,
          user         = input$cfg_ttrss_user,
          password     = input$cfg_ttrss_pass,
          max_articles = input$cfg_max_articles
        )
        rv$df <- df
        .log("Собрано: ", nrow(df), " статей")
      }, error = function(e) .log("Ошибка: ", conditionMessage(e)))
    })
  })

  # Кнопка: классифицировать
  observeEvent(input$btn_classify, {
    req(rv$df)
    .log("Классификация (", input$cfg_method, ")…")
    withProgress(message = "Классификация…", {
      tryCatch({
        rv$df <- classify_news(rv$df, n_topics = input$cfg_n_topics,
                               method = input$cfg_method)
        .log("Готово. Тем: ", length(unique(rv$df$topic_label)))
      }, error = function(e) .log("Ошибка: ", conditionMessage(e)))
    })
  })

  # Фильтрованные данные
  filtered_df <- reactive({
    df <- rv$df
    req(df)
    if (!is.null(input$art_topic) && !("Все" %in% input$art_topic) && length(input$art_topic) > 0)
      df <- filter(df, topic_label %in% input$art_topic)
    if (!is.null(input$art_feed) && !("Все" %in% input$art_feed) && length(input$art_feed) > 0)
      df <- filter(df, feed_title %in% input$art_feed)
    df
  })

  # ── Value boxes ──────────────────────────────────────────────────────────
  output$box_total <- renderValueBox({
    n <- if (is.null(rv$df)) 0L else nrow(rv$df)
    valueBox(n, "Всего статей", icon = icon("newspaper"), color = "blue")
  })

  output$box_today <- renderValueBox({
    n <- tryCatch({
      if (is.null(rv$df)) 0L
      else sum(as.Date(as.character(rv$df$published_at)) == Sys.Date(), na.rm = TRUE)
    }, error = function(e) 0L)
    valueBox(n, "Сегодня", icon = icon("calendar"), color = "green")
  })

  output$box_topics <- renderValueBox({
    n <- tryCatch({
      if (is.null(rv$df) || !"topic_label" %in% names(rv$df)) 0L
      else length(unique(rv$df$topic_label[!is.na(rv$df$topic_label)]))
    }, error = function(e) 0L)
    valueBox(n, "Тем", icon = icon("tags"), color = "purple")
  })

  output$box_feeds <- renderValueBox({
    n <- tryCatch({
      if (is.null(rv$df)) 0L
      else length(unique(rv$df$feed_title[!is.na(rv$df$feed_title)]))
    }, error = function(e) 0L)
    valueBox(n, "Источников", icon = icon("rss"), color = "orange")
  })

  # ── Графики ───────────────────────────────────────────────────────────────
  output$plot_timeline <- renderPlotly({
    df <- rv$df
    req(df, nrow(df) > 0)
    daily <- df |>
      mutate(date = as.Date(as.character(published_at))) |>
      filter(!is.na(date)) |>
      count(date) |>
      arrange(date)
    req(nrow(daily) > 0)
    plot_ly(daily, x = ~date, y = ~n, type = "bar",
            marker = list(color = "#3c8dbc")) |>
      layout(xaxis = list(title = ""),
             yaxis = list(title = "Статей"),
             margin = list(l = 50, r = 20, t = 10, b = 50))
  })

  output$plot_topics <- renderPlotly({
    df <- rv$df
    req(df, "topic_label" %in% names(df))
    top <- df |>
      filter(!is.na(topic_label), nzchar(topic_label)) |>
      count(topic_label, sort = TRUE) |>
      head(10)
    req(nrow(top) > 0)
    plot_ly(top,
            x = ~n,
            y = ~reorder(topic_label, n),
            type = "bar", orientation = "h",
            marker = list(color = "#00a65a")) |>
      layout(xaxis = list(title = "Статей"),
             yaxis = list(title = ""),
             margin = list(l = 200, r = 20, t = 10, b = 40))
  })

  output$plot_feeds_pie <- renderPlotly({
    df <- rv$df
    req(df, "feed_title" %in% names(df))
    fc <- df |>
      filter(!is.na(feed_title)) |>
      count(feed_title, sort = TRUE) |>
      head(12)
    req(nrow(fc) > 0)
    plot_ly(fc, labels = ~feed_title, values = ~n, type = "pie",
            hole = 0.3,
            textposition = "inside",
            textinfo = "percent") |>
      layout(showlegend = TRUE,
             legend = list(orientation = "v", x = 1, y = 0.5),
             margin = list(l = 0, r = 120, t = 10, b = 10))
  })

  # ── Таблицы ───────────────────────────────────────────────────────────────
  output$tbl_articles <- DT::renderDataTable({
    df <- filtered_df()
    req(df, nrow(df) > 0)
    cols <- intersect(c("published_at", "feed_title", "topic_label", "title", "author"), names(df))
    df <- df[, cols, drop = FALSE]
    DT::datatable(df,
      options = list(pageLength = 20, scrollX = TRUE,
                     order = list(list(0, "desc"))),
      rownames = FALSE)
  })

  output$tbl_feeds <- DT::renderDataTable({
    df <- rv$df
    req(df)
    df |>
      filter(!is.na(feed_title)) |>
      count(feed_title, name = "Статей") |>
      arrange(desc(Статей)) |>
      rename(Источник = feed_title) |>
      DT::datatable(options = list(pageLength = 20), rownames = FALSE)
  })

  output$log_output <- renderText({
    paste(tail(rv$log, 20), collapse = "\n")
  })
}
