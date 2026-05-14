library(shiny)
library(shinydashboard)
library(DT)
library(plotly)

ui <- dashboardPage(
  skin = "blue",

  dashboardHeader(title = "TT-RSS Analytics"),

  dashboardSidebar(
    sidebarMenu(
      menuItem("Обзор",     tabName = "overview",  icon = icon("chart-bar")),
      menuItem("Новости",   tabName = "articles",  icon = icon("newspaper")),
      menuItem("Источники", tabName = "feeds",     icon = icon("rss")),
      menuItem("Настройки", tabName = "settings",  icon = icon("cog"))
    )
  ),

  dashboardBody(
    tabItems(

      # ── Обзор ──────────────────────────────────────────────────────────────
      tabItem(tabName = "overview",
        fluidRow(
          valueBoxOutput("box_total",  width = 3),
          valueBoxOutput("box_today",  width = 3),
          valueBoxOutput("box_topics", width = 3),
          valueBoxOutput("box_feeds",  width = 3)
        ),
        fluidRow(
          box(title = "Темы публикаций", width = 6,
              status = "info", solidHeader = TRUE,
              plotlyOutput("plot_topics", height = "300px")),
          box(title = "Статьи по источникам", width = 6,
              status = "warning", solidHeader = TRUE,
              plotlyOutput("plot_feeds_pie", height = "300px"))
        ),
        fluidRow(
          box(title = "Динамика тем по неделям (топ-5)", width = 7,
              status = "primary", solidHeader = TRUE,
              plotlyOutput("plot_topic_trend", height = "340px")),
          box(title = "Малые темы (наименее популярные)", width = 5,
              status = "success", solidHeader = TRUE,
              plotlyOutput("plot_rare_topics", height = "340px"))
        )
      ),

      # ── Новости ────────────────────────────────────────────────────────────
      tabItem(tabName = "articles",
        fluidRow(
          box(width = 12, status = "primary",
              fluidRow(
                column(4, selectInput("art_topic", "Тема:", choices = NULL)),
                column(4, selectInput("art_feed",  "Источник:", choices = NULL)),
                column(4, br(),
                       actionButton("btn_refresh", "Сбросить фильтры",
                                    icon = icon("sync"), class = "btn-default"))
              )
          )
        ),
        fluidRow(
          box(width = 12,
              DT::dataTableOutput("tbl_articles"))
        )
      ),

      # ── Источники ──────────────────────────────────────────────────────────
      tabItem(tabName = "feeds",
        fluidRow(
          box(width = 12, title = "Список источников", status = "info",
              solidHeader = TRUE,
              DT::dataTableOutput("tbl_feeds"))
        )
      ),

      # ── Настройки ──────────────────────────────────────────────────────────
      tabItem(tabName = "settings",
        fluidRow(
          box(width = 6, title = "Подключение к TT-RSS", status = "warning",
              solidHeader = TRUE,
              textInput("cfg_ttrss_url",  "URL TT-RSS",
                        value = Sys.getenv("TTRSS_URL", "http://localhost:8080")),
              textInput("cfg_ttrss_user", "Пользователь",
                        value = Sys.getenv("TTRSS_USER", "admin")),
              passwordInput("cfg_ttrss_pass", "Пароль",
                            value = Sys.getenv("TTRSS_PASSWORD", "")),
              numericInput("cfg_max_articles", "Макс. статей",
                           value = 500, min = 10, max = 5000, step = 10),
              actionButton("btn_fetch", "Собрать новости",
                           icon = icon("download"), class = "btn-warning btn-block")
          ),
          box(width = 6, title = "Классификация", status = "info",
              solidHeader = TRUE,
              selectInput("cfg_method", "Метод",
                          choices = c(
                            "LDA" = "lda",
                            "K-Means" = "kmeans",
                            "Yandex GPT" = "yandex_llm",
                            "LLM (любой провайдер)" = "llm"
                          )),
              numericInput("cfg_n_topics", "Количество тем (LDA / K-Means)",
                           value = 8, min = 2, max = 30),
              tags$hr(),
              tags$strong("LLM — универсальные настройки (метод «LLM»)"),
              tags$br(), tags$br(),
              selectInput("cfg_llm_provider", "Провайдер",
                          choices = c(
                            "OpenAI / OpenAI-совместимый (DeepSeek, Groq, …)" = "openai",
                            "Anthropic Claude" = "anthropic",
                            "Google Gemini" = "gemini",
                            "Ollama (local)" = "ollama"
                          )),
              passwordInput("cfg_llm_api_key", "API Key",
                            value = Sys.getenv("LLM_API_KEY", "")),
              textInput("cfg_llm_model", "Модель (любое название)",
                        value = "",
                        placeholder = "deepseek-v4-flash  /  gpt-4o-mini  /  llama3.2  …"),
              textInput("cfg_llm_base_url", "Base URL",
                        value = "",
                        placeholder = "пусто = OpenAI  |  DeepSeek: https://api.deepseek.com"),
              helpText(
                tags$b("OpenAI:"), "оставьте Base URL пустым.", tags$br(),
                tags$b("DeepSeek:"), tags$code("https://api.deepseek.com"),
                "— /v1 добавляется автоматически.",
                "Модели: deepseek-v4-flash / deepseek-v4-pro.", tags$br(),
                tags$b("Groq:"), tags$code("https://api.groq.com/openai/v1"), tags$br(),
                tags$b("Ollama:"), "Base URL = http://localhost:11434."
              ),
              tags$hr(),
              tags$strong("Yandex GPT — настройки (метод «Yandex GPT»)"),
              tags$br(), tags$br(),
              passwordInput("cfg_yandex_api_key", "Yandex API key",
                            value = Sys.getenv("YANDEX_CLOUD_API_KEY", "")),
              textInput("cfg_yandex_folder", "Yandex folder id",
                        value = Sys.getenv("YANDEX_CLOUD_FOLDER", "")),
              textInput("cfg_yandex_model", "Yandex model",
                        value = Sys.getenv("YANDEX_CLOUD_MODEL", "yandexgpt-5-lite/latest")),
              textInput("cfg_yandex_base_url", "Yandex base URL",
                        value = Sys.getenv("YANDEX_CLOUD_BASE_URL", "https://ai.api.cloud.yandex.net/v1")),
              actionButton("btn_classify", "Классифицировать",
                           icon = icon("tags"), class = "btn-info btn-block"),
              hr(),
              verbatimTextOutput("log_output")
          )
        )
      )
    )
  )
)
