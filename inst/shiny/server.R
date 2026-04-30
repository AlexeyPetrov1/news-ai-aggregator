library(shiny)
library(dplyr)
library(ggplot2)
library(plotly)
library(DT)
library(ttrssR)

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

  observe({
    df <- rv$df
    req(df)
    topics <- c("Все", sort(unique(df$topic_label[!is.na(df$topic_label) & nzchar(df$topic_label)])))
    feeds  <- c("Все", sort(unique(df$feed_title[!is.na(df$feed_title)])))
    updateSelectInput(session, "art_topic", choices = topics, selected = "Все")
    updateSelectInput(session, "art_feed",  choices = feeds,  selected = "Все")
  })

  observeEvent(input$btn_refresh, {
    df <- rv$df
    req(df)
    topics <- c("Все", sort(unique(df$topic_label[!is.na(df$topic_label) & nzchar(df$topic_label)])))
    feeds  <- c("Все", sort(unique(df$feed_title[!is.na(df$feed_title)])))
    updateSelectInput(session, "art_topic", choices = topics, selected = "Все")
    updateSelectInput(session, "art_feed",  choices = feeds,  selected = "Все")
  })

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
  output$plot_topics <- renderPlotly({
    df <- rv$df
    req(df, "topic_label" %in% names(df))
    topic_stats <- df |>
      filter(!is.na(topic_label), nzchar(topic_label)) |>
      count(topic_label, sort = TRUE) |>
      mutate(
        share = round(100 * n / sum(n), 1),
        topic_label = if_else(topic_label == "Other",
                              paste0(topic_label, " (fallback)"),
                              topic_label)
      )
    req(nrow(topic_stats) > 0)
    plot_ly(topic_stats,
            x = ~n,
            y = ~reorder(topic_label, n),
            type = "bar", orientation = "h",
            text = ~paste0(share, "%"),
            textposition = "outside",
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
    plot_ly(fc,
            x = ~reorder(feed_title, n),
            y = ~n,
            type = "bar",
            marker = list(color = "#f39c12")) |>
      layout(xaxis = list(title = "", tickangle = -35),
             yaxis = list(title = "Статей"),
             margin = list(l = 40, r = 20, t = 10, b = 130))
  })

  output$plot_topic_trend <- renderPlotly({
    df <- rv$df
    req(df, "published_at" %in% names(df), "topic_label" %in% names(df))

    top_topics <- df |>
      filter(!is.na(topic_label), nzchar(topic_label)) |>
      count(topic_label, sort = TRUE) |>
      slice_head(n = 6) |>
      pull(topic_label)

    trend <- df |>
      mutate(day = as.Date(as.character(published_at))) |>
      filter(!is.na(day), !is.na(topic_label), nzchar(topic_label)) |>
      mutate(topic_group = if_else(topic_label %in% top_topics, topic_label, "Other topics")) |>
      count(day, topic_group) |>
      arrange(day)

    req(nrow(trend) > 0)
    plot_ly(
      trend,
      x = ~day,
      y = ~n,
      color = ~topic_group,
      colors = "Set2",
      type = "scatter",
      mode = "lines+markers"
    ) |>
      layout(
        xaxis = list(title = ""),
        yaxis = list(title = "Статей в день"),
        legend = list(orientation = "h", y = -0.2),
        margin = list(l = 60, r = 20, t = 10, b = 70)
      )
  })

  output$plot_rare_topics <- renderPlotly({
    df <- rv$df
    req(df, "topic_label" %in% names(df))

    rare <- df |>
      filter(!is.na(topic_label), nzchar(topic_label)) |>
      count(topic_label, sort = TRUE) |>
      arrange(n) |>
      slice_head(n = 8)

    req(nrow(rare) > 0)
    plot_ly(rare,
            x = ~reorder(topic_label, n),
            y = ~n,
            type = "bar",
            marker = list(color = "#00c0ef")) |>
      layout(
        xaxis = list(title = "", tickangle = -30),
        yaxis = list(title = "Статей"),
        margin = list(l = 50, r = 20, t = 10, b = 90)
      )
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
