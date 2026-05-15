library(shiny)  # cb-g
library(dplyr)  # cb-g
library(ggplot2)  # cb-g
library(plotly)  # cb-g
library(DT)  # cb-g
library(ttrssR)  # cb-g
  # cb-g
.drop_unknown_feeds <- function(df) {  #cb-g-178
  if (is.null(df) || !is.data.frame(df)) return(df)  #cb-g-179
  if (!"feed_title" %in% names(df)) return(df)  #cb-g-180
  df[is.na(df$feed_title) | df$feed_title != "[Unknown]", , drop = FALSE]  #cb-g-181
}  #cb-g-182
#
.initial_df <- local({  # cb-g
  candidates <- c(  # cb-g
    "data/news_raw.rds",  # cb-g
    "/srv/shiny-server/ttrss/shiny/data/news_raw.rds"  # cb-g
  )  # cb-g
  rds <- Find(file.exists, candidates)  # cb-g
  if (!is.null(rds)) {  # cb-g
    message("[APP] Loading: ", rds)  # cb-g
    df <- tryCatch(readRDS(rds), error = function(e) { message("[APP] Error: ", e$message); NULL })  #cb-g-183
    .drop_unknown_feeds(df)  #cb-g-184
  } else {  # cb-g
    message("[APP] No data file found")  # cb-g
    NULL  # cb-g
  }  # cb-g
})  # cb-g
if (!is.null(.initial_df)) message("[APP] Ready: ", nrow(.initial_df), " rows")  # cb-g
  # cb-g
server <- function(input, output, session) {  # cb-g
  # cb-g
  rv <- reactiveValues(  # cb-g
    df  = .initial_df,  # cb-g
    log = character(0)  # cb-g
  )  # cb-g
  # cb-g
  # Сокращает LDA-метки "Тема N: слово1, слово2, ..." → "#N слово1 · слово2"  # cb-g
  # Остальные метки обрезает до 28 символов с "…" если длиннее  # cb-g
  shorten_lda_label <- function(lbl) {  # cb-g
    # HTML-сущности которые не несут смысла в метках тем  # cb-g
    html_junk <- c("mdash","ndash","laquo","raquo","rsquo","lsquo",  # cb-g
                   "ldquo","rdquo","nbsp","amp","quot","apos","hellip",  # cb-g
                   "images","photos","said","also","that","this","with",  # cb-g
                   "from","have","been","they","their","were","will")  # cb-g
    is_lda <- grepl("^Тема \\d+: ", lbl, perl = TRUE)  # cb-g
    out    <- lbl  # cb-g
    if (any(is_lda)) {  # cb-g
      nums  <- regmatches(lbl[is_lda], regexpr("\\d+", lbl[is_lda]))  # cb-g
      tstr  <- sub("^Тема \\d+: ", "", lbl[is_lda])  # cb-g
      terms <- lapply(strsplit(tstr, ",\\s*"), function(x) {  # cb-g
        words <- trimws(x)  # cb-g
        words <- words[!tolower(words) %in% html_junk & nchar(words) > 2]  # cb-g
        head(words, 3)  # cb-g
      })  # cb-g
      labels <- vapply(terms, function(w) {  # cb-g
        if (length(w) == 0) return("—")  # cb-g
        paste(w, collapse = " · ")  # cb-g
      }, character(1))  # cb-g
      out[is_lda] <- paste0("#", nums, ": ", labels)  # cb-g
    }  # cb-g
    long <- !is_lda & nchar(out) > 30  # cb-g
    out[long] <- paste0(substr(out[long], 1, 27), "…")  # cb-g
    out  # cb-g
  }  # cb-g
  # cb-g
  .log <- function(...) {  # cb-g
    msg    <- paste0("[", format(Sys.time(), "%H:%M:%S"), "] ", ...)  # cb-g
    rv$log <- c(rv$log, msg)  # cb-g
  }  # cb-g
  # cb-g
  observe({  # cb-g
    df <- rv$df  # cb-g
    req(df)  # cb-g
    topics <- c("Все", sort(unique(df$topic_label[!is.na(df$topic_label) & nzchar(df$topic_label)])))  # cb-g
    feeds  <- c("Все", sort(unique(df$feed_title[!is.na(df$feed_title) & df$feed_title != "[Unknown]"])))  #cb-g-185
    updateSelectInput(session, "art_topic", choices = topics, selected = "Все")  # cb-g
    updateSelectInput(session, "art_feed",  choices = feeds,  selected = "Все")  # cb-g
  })  # cb-g
  # cb-g
  observeEvent(input$btn_refresh, {  # cb-g
    df <- rv$df  # cb-g
    req(df)  # cb-g
    topics <- c("Все", sort(unique(df$topic_label[!is.na(df$topic_label) & nzchar(df$topic_label)])))  # cb-g
    feeds  <- c("Все", sort(unique(df$feed_title[!is.na(df$feed_title) & df$feed_title != "[Unknown]"])))  #cb-g-186
    updateSelectInput(session, "art_topic", choices = topics, selected = "Все")  # cb-g
    updateSelectInput(session, "art_feed",  choices = feeds,  selected = "Все")  # cb-g
  })  # cb-g
  # cb-g
  observeEvent(input$btn_fetch, {  # cb-g
    .log("Запуск сбора…")  # cb-g
    withProgress(message = "Сбор новостей…", {  # cb-g
      tryCatch({  # cb-g
        ttrss_url <- if (nzchar(Sys.getenv("TTRSS_URL"))) Sys.getenv("TTRSS_URL") else input$cfg_ttrss_url  #cb-g-187
        ttrss_user <- if (nzchar(Sys.getenv("TTRSS_USER"))) Sys.getenv("TTRSS_USER") else input$cfg_ttrss_user  #cb-g-188
        ttrss_pass <- if (nzchar(Sys.getenv("TTRSS_PASSWORD"))) Sys.getenv("TTRSS_PASSWORD") else input$cfg_ttrss_pass  #cb-g-189
        df <- fetch_news_dataframe(  # cb-g
          base_url     = ttrss_url,  #cb-g-190
          user         = ttrss_user,  #cb-g-191
          password     = ttrss_pass,  #cb-g-192
          max_articles = input$cfg_max_articles  # cb-g
        )  # cb-g
        rv$df <- .drop_unknown_feeds(df)  #cb-g-193
        .log("Собрано: ", nrow(rv$df), " статей")  #cb-g-194
      }, error = function(e) .log("Ошибка: ", conditionMessage(e)))  # cb-g
    })  # cb-g
  })  # cb-g
  # cb-g
  observeEvent(input$btn_classify, {  # cb-g
    req(rv$df)  # cb-g
    .log("Классификация (", input$cfg_method, ")…")  # cb-g
    withProgress(message = "Классификация…", {  # cb-g
      tryCatch({  # cb-g
        yandex_api_key  <- trimws(if (is.null(input$cfg_yandex_api_key)) "" else input$cfg_yandex_api_key)  # cb-g
        yandex_folder   <- trimws(if (is.null(input$cfg_yandex_folder)) "" else input$cfg_yandex_folder)  # cb-g
        yandex_model    <- trimws(if (is.null(input$cfg_yandex_model)) "" else input$cfg_yandex_model)  # cb-g
        yandex_base_url <- trimws(if (is.null(input$cfg_yandex_base_url)) "" else input$cfg_yandex_base_url)  # cb-g
        llm_api_key     <- trimws(if (is.null(input$cfg_llm_api_key)) "" else input$cfg_llm_api_key)  # cb-g
        llm_model       <- trimws(if (is.null(input$cfg_llm_model)) "" else input$cfg_llm_model)  # cb-g
        llm_base_url    <- trimws(if (is.null(input$cfg_llm_base_url)) "" else input$cfg_llm_base_url)  # cb-g
        llm_provider    <- if (is.null(input$cfg_llm_provider)) "openai" else input$cfg_llm_provider  # cb-g

        if (identical(input$cfg_method, "yandex_llm")) {  # cb-g
          if (!nzchar(yandex_api_key)) {  # cb-g
            .log("Ошибка: не задан Yandex API key.")  # cb-g
            return(invisible(NULL))  # cb-g
          }  # cb-g
          if (!nzchar(yandex_folder)) {  # cb-g
            .log("Ошибка: не задан Yandex folder id.")  # cb-g
            return(invisible(NULL))  # cb-g
          }
        }  # cb-g

        if (identical(input$cfg_method, "llm")) {  # cb-g
          needs_key <- llm_provider %in% c("openai", "anthropic", "gemini")  # cb-g
          if (needs_key && !nzchar(llm_api_key) &&  # cb-g
              !nzchar(Sys.getenv("LLM_API_KEY", ""))) {  # cb-g
            .log("Ошибка: не задан API Key (поле «API Key» или переменная LLM_API_KEY).")  # cb-g
            return(invisible(NULL))  # cb-g
          }
        }  # cb-g

        rv$df <- classify_news(  # cb-g
          rv$df,  # cb-g
          n_topics         = input$cfg_n_topics,  # cb-g
          method           = input$cfg_method,  # cb-g
          yandex_api_key   = if (nzchar(yandex_api_key)) yandex_api_key else NULL,  # cb-g
          yandex_folder_id = if (nzchar(yandex_folder)) yandex_folder else NULL,  # cb-g
          yandex_model     = if (nzchar(yandex_model)) yandex_model  # cb-g
                             else Sys.getenv("YANDEX_CLOUD_MODEL", "yandexgpt-5-lite/latest"),  # cb-g
          yandex_base_url  = if (nzchar(yandex_base_url)) yandex_base_url  # cb-g
                             else Sys.getenv("YANDEX_CLOUD_BASE_URL", "https://ai.api.cloud.yandex.net/v1"),  # cb-g
          llm_provider     = llm_provider,  # cb-g
          llm_api_key      = if (nzchar(llm_api_key)) llm_api_key else NULL,  # cb-g
          llm_model        = if (nzchar(llm_model)) llm_model else NULL,  # cb-g
          llm_base_url     = if (nzchar(llm_base_url)) llm_base_url else NULL  # cb-g
        )  # cb-g
        warn_msg <- getOption("ttrssR.last_llm_warning")  # cb-g
        if (!is.null(warn_msg)) {  # cb-g
          .log("! ", warn_msg)  # cb-g
          options(ttrssR.last_llm_warning = NULL)  # cb-g
        }  # cb-g
        .log("Готово. Тем: ", length(unique(rv$df$topic_label[!is.na(rv$df$topic_label) & nzchar(rv$df$topic_label)])))  #cb-g-195
      }, error = function(e) .log("Ошибка: ", conditionMessage(e)))  # cb-g
    })  # cb-g
  })  # cb-g
  # cb-g
  filtered_df <- reactive({  # cb-g
    df <- rv$df  # cb-g
    req(df)  # cb-g
    df <- .drop_unknown_feeds(df)  #cb-g-196
    if (!is.null(input$art_topic) && !("Все" %in% input$art_topic) && length(input$art_topic) > 0)  # cb-g
      df <- filter(df, topic_label %in% input$art_topic)  # cb-g
    if (!is.null(input$art_feed) && !("Все" %in% input$art_feed) && length(input$art_feed) > 0)  # cb-g
      df <- filter(df, feed_title %in% input$art_feed)  # cb-g
    df  # cb-g
  })  # cb-g
  # cb-g
  # ── Value boxes ──────────────────────────────────────────────────────────  # cb-g
  output$box_total <- renderValueBox({  # cb-g
    n <- if (is.null(rv$df)) 0L else nrow(rv$df)  # cb-g
    valueBox(n, "Всего статей", icon = icon("newspaper"), color = "blue")  # cb-g
  })  # cb-g
  # cb-g
  output$box_today <- renderValueBox({  # cb-g
    n <- tryCatch({  # cb-g
      if (is.null(rv$df)) 0L  # cb-g
      else sum(as.Date(as.character(rv$df$published_at)) == Sys.Date(), na.rm = TRUE)  # cb-g
    }, error = function(e) 0L)  # cb-g
    valueBox(n, "Сегодня", icon = icon("calendar"), color = "green")  # cb-g
  })  # cb-g
  # cb-g
  output$box_topics <- renderValueBox({  # cb-g
    n <- tryCatch({  # cb-g
      if (is.null(rv$df) || !"topic_label" %in% names(rv$df)) 0L  # cb-g
      else length(unique(rv$df$topic_label[!is.na(rv$df$topic_label)]))  # cb-g
    }, error = function(e) 0L)  # cb-g
    valueBox(n, "Тем", icon = icon("tags"), color = "purple")  # cb-g
  })  # cb-g
  # cb-g
  output$box_feeds <- renderValueBox({  # cb-g
    n <- tryCatch({  # cb-g
      if (is.null(rv$df)) 0L  # cb-g
      else length(unique(rv$df$feed_title[!is.na(rv$df$feed_title)]))  # cb-g
    }, error = function(e) 0L)  # cb-g
    valueBox(n, "Источников", icon = icon("rss"), color = "orange")  # cb-g
  })  # cb-g
  # cb-g
  # ── Графики ───────────────────────────────────────────────────────────────  # cb-g
  output$plot_topics <- renderPlotly({  # cb-g
    df <- rv$df  # cb-g
    req(df, "topic_label" %in% names(df))  # cb-g
    topic_stats <- df |>
      filter(!is.na(topic_label), nzchar(topic_label), topic_label != "Other") |>  # cb-g
      count(topic_label, sort = TRUE) |>  # cb-g
      mutate(share = round(100 * n / sum(n), 1),  # cb-g
             label_short = shorten_lda_label(topic_label))  # cb-g
    req(nrow(topic_stats) > 0)
    plot_ly(topic_stats,
            x = ~n,  # cb-g
            y = ~reorder(label_short, n),  # cb-g
            type = "bar", orientation = "h",  # cb-g
            text = ~paste0(share, "%"),
            textposition = "outside",
            marker = list(color = "#00a65a")) |>  # cb-g
      layout(xaxis = list(title = "Статей"),  # cb-g
             yaxis = list(title = ""),  # cb-g
             margin = list(l = 200, r = 20, t = 10, b = 40))  # cb-g
  })  # cb-g
  # cb-g
  output$plot_feeds_pie <- renderPlotly({  # cb-g
    df <- rv$df  # cb-g
    req(df, "feed_title" %in% names(df))  # cb-g
    fc <- df |>  # cb-g
      filter(!is.na(feed_title), feed_title != "[Unknown]") |>  #cb-g-197
      count(feed_title, sort = TRUE) |>  # cb-g
      head(12)  # cb-g
    req(nrow(fc) > 0)  # cb-g
    plot_ly(fc,  # cb-g
            x = ~reorder(feed_title, n),  # cb-g
            y = ~n,  # cb-g
            type = "bar",  # cb-g
            marker = list(color = "#f39c12")) |>  # cb-g
      layout(xaxis = list(title = "", tickangle = -35),  # cb-g
             yaxis = list(title = "Статей"),  # cb-g
             margin = list(l = 40, r = 20, t = 10, b = 130))  # cb-g
  })  # cb-g
  # cb-g
  output$plot_daily <- renderPlotly({  # cb-g
    df <- rv$df  # cb-g
    req(df, "published_at" %in% names(df), "topic_label" %in% names(df))

    daily <- df |>  # cb-g
      mutate(day = as.Date(as.character(published_at))) |>  # cb-g
      filter(!is.na(day), !is.na(topic_label), nzchar(topic_label), topic_label != "Other") |>  # cb-g
      mutate(label = shorten_lda_label(topic_label)) |>  # cb-g
      count(day, label) |>  # cb-g
      arrange(day)  # cb-g

    req(nrow(daily) > 0)  # cb-g
    plot_ly(
      daily,  # cb-g
      x             = ~day,  # cb-g
      y             = ~n,  # cb-g
      color         = ~label,  # cb-g
      colors        = "Set2",  # cb-g
      type          = "bar",  # cb-g
      hovertemplate = "<b>%{fullData.name}</b><br>%{x|%d %b %Y}: %{y} ст.<extra></extra>"  # cb-g
    ) |>
      layout(
        barmode = "stack",  # cb-g
        xaxis   = list(title = ""),  # cb-g
        yaxis   = list(title = "Статей за день"),  # cb-g
        legend  = list(  # cb-g
          orientation = "v", x = 1.02, y = 0.5,  # cb-g
          xanchor = "left", font = list(size = 11)  # cb-g
        ),  # cb-g
        margin  = list(l = 50, r = 160, t = 10, b = 40)  # cb-g
      )
  })  # cb-g
  # cb-g
  # ── Таблицы ───────────────────────────────────────────────────────────────  # cb-g
  output$tbl_articles <- DT::renderDataTable({  # cb-g
    df <- filtered_df()  # cb-g
    req(df, nrow(df) > 0)  # cb-g
    cols <- intersect(
      c("published_at", "feed_title", "topic_label", "title", "author"),
      names(df)
    )
    df <- df[, cols, drop = FALSE]  # cb-g
    DT::datatable(df,  # cb-g
      selection = "multiple",
      options = list(pageLength = 20, scrollX = TRUE,  # cb-g
                     order = list(list(0, "desc"))),  # cb-g
      rownames = FALSE)  # cb-g
  })  # cb-g
  # cb-g
  output$tbl_feeds <- DT::renderDataTable({  # cb-g
    df <- rv$df  # cb-g
    req(df)  # cb-g
    df |>  # cb-g
      filter(!is.na(feed_title), feed_title != "[Unknown]") |>  #cb-g-198
      count(feed_title, name = "Статей") |>  # cb-g
      arrange(desc(Статей)) |>  # cb-g
      rename(Источник = feed_title) |>  # cb-g
      DT::datatable(options = list(pageLength = 20), rownames = FALSE)  # cb-g
  })  # cb-g
  # cb-g
  output$log_output <- renderText({  # cb-g
    paste(tail(rv$log, 20), collapse = "\n")  # cb-g
  })  # cb-g
}  # cb-g
