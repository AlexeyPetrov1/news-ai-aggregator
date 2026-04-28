# ttrssR — AI-агрегатор новостей по кибербезопасности

Полный конвейер: сбор RSS → хранение в ClickHouse → LDA-классификация → Shiny-дашборд → MCP-сервер для Claude Code.

## Архитектура

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Docker Compose Stack                         │
│                                                                     │
│  ┌──────────┐    ┌────────────────┐    ┌────────────────────────┐  │
│  │  TT-RSS  │───▶│    ttrssR      │───▶│      ClickHouse        │  │
│  │(RSS агг.)│    │  (R-пакет)     │    │  (колонч. БД)          │  │
│  │:8280     │    │  collect/LDA   │    │  :9000                 │  │
│  └──────────┘    └────────────────┘    └──────────┬─────────────┘  │
│                                                   │                │
│                         ┌─────────────────────────┤                │
│                         ▼                         ▼                │
│               ┌──────────────────┐   ┌────────────────────────┐   │
│               │  Shiny Dashboard │   │   MCP stdio Server     │   │
│               │  :3838           │   │   (Rscript процесс)    │   │
│               └──────────────────┘   └────────────┬───────────┘   │
└─────────────────────────────────────────────────┐─┘               │
                                                  ▼                  │
                                          Claude Code (LLM)          │
                                          работает с данными          │
                                          через MCP-инструменты       │
```

## Технологический стек

| Компонент | Технология | Версия |
|-----------|-----------|--------|
| Язык | R | 4.5.3 |
| RSS-агрегатор | TT-RSS | latest |
| Колоночная БД | ClickHouse | 24.x |
| Дашборд | Shiny + shinydashboard | CRAN |
| Визуализация | plotly | CRAN |
| Тематическое моделирование | topicmodels (LDA), tidytext, YandexGPT | CRAN / Yandex Cloud |
| MCP-протокол | JSON-RPC 2.0 stdio | — |
| Контейнеры | Docker Compose | — |
| Хостинг кода | GitHub | — |

---

## Этап 1 — Выбор ниши и RSS-источники

**Ниша:** APT / Threat Intelligence (атаки и угрозы в кибербезопасности).

Настроены 16 RSS-лент в 4 категориях (`data-raw/add_security_feeds.R`):

| Категория | Источники |
|-----------|-----------|
| Threat Research | Mandiant Blog, Securelist, Unit42, ESET WeLiveSecurity, Recorded Future |
| Attack News EN | BleepingComputer, The Hacker News, Krebs on Security, Dark Reading |
| CERT / Gov | US-CERT Alerts, CISA Advisories |
| APT / RU | BI.ZONE Blog, Positive Technologies, PT Expert Security Center, Kaspersky Threats |

Скрипт использует TT-RSS JSON API: логин → `subscribeToFeed` → `updateFeed` → проверка.

---

## Этап 2 — Сбор статей (R-пакет ttrssR)

Пакет `ttrssR` предоставляет функции:

```r
library(ttrssR)

# Авторизация
sid <- ttrss_login(host, user, password)

# Получение заголовков по категории
articles <- ttrss_get_headlines(sid, cat_id = -4, limit = 1000)

# Полный текст статей
full <- ttrss_get_article(sid, article_ids)
```

Результат — `data.frame` с полями: `article_id`, `title`, `content`, `content_text`, `link`, `feed_title`, `published_at`, `is_unread`, `is_starred`.

Собрано **340 статей** от 16 источников, сохранено в `data/news_raw.rds`.

---

## Этап 3 — Тематическое моделирование (LDA)

Файл: `R/classify.R` (функция `classify_news()`)

Алгоритм:
1. Токенизация заголовков + текстов (`tidytext::unnest_tokens`)
2. Удаление стоп-слов (английский + русский)
3. Построение матрицы документ-термин (`cast_dtm`)
4. LDA с **8 темами** (`topicmodels::LDA(k=8, method="Gibbs")`)
5. Присвоение каждой статье доминирующей темы (`topic_label`)

Полученные темы:
- Ransomware & Extortion
- APT Campaigns
- Vulnerability & Patch
- Data Breach
- Malware Analysis
- Phishing & Social Engineering
- CERT / Government Alerts
- Threat Intelligence

Результат записывается обратно в `data/news_raw.rds` с добавленными колонками `topic`, `topic_label`, `topic_prob`.

Дополнительно в `R/classify.R` реализованы альтернативные методы:
- `method = "kmeans"` — кластеризация TF-IDF;
- `method = "llm"` — классификация через Anthropic API;
- `method = "yandex_llm"` — классификация через Yandex Cloud Assistant API (`gpt://<folder>/<model>`).

Для `yandex_llm` добавлены практические улучшения:
- retry с exponential backoff для HTTP 429/5xx;
- session-cache ответов для повторяющихся текстов;
- persistent cache в `data/yandex_llm_cache.rds` между запусками;
- fallback в категорию `"Без категории"` при сетевой/API ошибке.

---

## Этап 4 — Хранение в ClickHouse

Файл: `R/db.R` — все функции для работы с ClickHouse.

### Схема таблицы

```sql
CREATE TABLE IF NOT EXISTS articles (
    article_id   UInt32,
    title        String,
    content      String,
    content_text String,
    link         String,
    feed_title   String,
    author       String,
    published_at DateTime,
    is_unread    UInt8 DEFAULT 0,
    is_starred   UInt8 DEFAULT 0,
    feed_id      UInt32 DEFAULT 0,
    topic        UInt32 DEFAULT 0,
    topic_label  String DEFAULT '',
    topic_prob   Float32 DEFAULT 0.0
)
ENGINE = ReplacingMergeTree(article_id)
ORDER BY article_id;
```

### Ключевые функции

```r
con <- ch_connect(host, port, dbname, user, password)
ch_init_schema(con)          # Создание таблицы
ch_write_articles(con, df)   # Запись статей
ch_read_articles(con, where, limit)   # Чтение с фильтром
ch_topic_summary(con)        # Статистика по темам
```

### Загрузка данных

```r
# data-raw/_load_to_clickhouse.R
df <- readRDS("data/news_raw.rds")
# NA → 0 для числовых, NA → "" для строк
ch_write_articles(con, df)
```

---

## Этап 5 — Shiny-дашборд

Файлы: `inst/shiny/ui.R`, `inst/shiny/server.R`

### Структура дашборда (4 вкладки)

| Вкладка | Содержимое |
|---------|-----------|
| Обзор | Value boxes (всего статей, тем, источников), график по дням, топ-10 тем (бар), доля источников (pie) |
| Статьи | Фильтруемая таблица с поиском и фильтром по теме |
| Источники | Таблица: источник → количество статей |
| Настройки | Кнопка обновления из ClickHouse |

### Ключевое решение: загрузка данных вне reactive-контекста

```r
# Загружаем данные ДО создания server-функции
.initial_df <- local({
  rds <- Find(file.exists, c("data/news_raw.rds",
              "/srv/shiny-server/ttrss/shiny/data/news_raw.rds"))
  if (!is.null(rds)) tryCatch(readRDS(rds), error = function(e) NULL)
})

server <- function(input, output, session) {
  rv <- reactiveValues(df = .initial_df)
  # ...
}
```

Это устранило проблему пустого дашборда: данные доступны сразу при запуске без ожидания асинхронного `observe()`.

---

## Этап 6 — Docker Compose

Файл: `docker-compose.yml`

```yaml
services:
  clickhouse:     # ClickHouse :9000/:8123
  ttrss-db:       # PostgreSQL для TT-RSS
  ttrss:          # TT-RSS :8280
  shiny:          # Shiny-дашборд :3838
  mcp:            # HTTP MCP-сервер (plumber) :8000
```

### Важные зависимости в Dockerfile (Shiny)

```dockerfile
RUN apt-get install -y \
    libsodium-dev \    # нужен для plumber/sodium
    libssl-dev \
    libcurl4-openssl-dev
```

### Решение проблемы кеша Docker BuildKit

При сломанном слое, который BuildKit кешировал, помогает `ARG CACHE_BUST`:

```dockerfile
ARG CACHE_BUST=4
RUN echo "cache bust: $CACHE_BUST" && \
    Rscript -e "install.packages(c('plumber','jsonlite',...))"
```

Изменение значения `CACHE_BUST` принудительно пересобирает слой.

---

## Этап 7 — MCP-сервер для Claude Code

### Транспорт: stdio (JSON-RPC 2.0)

Файл: `inst/mcp/stdio_server.R`

Claude Code запускает Rscript как дочерний процесс и общается через stdin/stdout. Каждое сообщение — JSON-строка, завершённая `\n`.

```r
con_in <- file("stdin", "r")
repeat {
  line <- readLines(con_in, n = 1L, warn = FALSE)
  if (is.null(line) || length(line) == 0) break
  msg  <- fromJSON(line, simplifyVector = FALSE)
  resp <- .handle(msg$method, msg$params, msg$id)
  if (!is.null(resp)) {
    cat(toJSON(resp, auto_unbox = TRUE), "\n", sep = "")
    flush(stdout())
  }
}
```

### Доступные инструменты (tools)

| Инструмент | Описание | Параметры |
|-----------|---------|-----------|
| `search_articles` | Поиск по ключевому слову | `query` (обяз.), `topic`, `limit` |
| `get_topic_summary` | Статистика по темам | `top_n` |
| `get_recent_articles` | Последние N статей | `topic`, `limit` |
| `get_feed_stats` | Статистика по источникам | — |

### Конфигурация в Claude Code

```json
{
  "mcpServers": {
    "ttrssR": {
      "command": "C:\\Program Files\\R\\R-4.5.3\\bin\\Rscript.exe",
      "args": ["D:\\prpject_R\\ttrssR\\inst\\mcp\\stdio_server.R"],
      "env": {
        "CH_HOST": "localhost",
        "CH_PORT": "9000",
        "CH_DB": "ttrss",
        "CH_USER": "default",
        "CH_PASSWORD": ""
      }
    }
  }
}
```

Добавить через CLI: `claude mcp add ttrssR ...`

---

## Этап 8 — Структура пакета

```
ttrssR/
├── R/
│   ├── db.R              # ClickHouse: connect, read, write, schema
│   ├── api.R             # TT-RSS JSON API: login, headlines, articles
│   ├── etl.R             # ETL: сбор и нормализация статей
│   ├── classify.R        # ML: LDA / KMeans / LLM-классификация
│   └── app.R             # Запуск Shiny и MCP
├── inst/
│   ├── shiny/
│   │   ├── ui.R          # Shiny UI (shinydashboard)
│   │   └── server.R      # Shiny Server (реактивная логика)
│   └── mcp/
│       ├── stdio_server.R  # MCP stdio транспорт (для Claude Code)
│       └── server.R        # MCP HTTP транспорт (plumber, для Docker)
├── data-raw/
│   ├── add_security_feeds.R    # Добавление RSS-лент в TT-RSS
│   └── fetch_news.R            # Сбор + классификация + сохранение
├── data/
│   └── news_raw.rds      # Собранные и классифицированные статьи
├── docker-compose.yml
├── Dockerfile            # Shiny-образ
├── DESCRIPTION
└── README.md
```

---

## Быстрый старт

### Предварительные требования

- Docker Desktop
- R 4.5.x
- Claude Code CLI

### 1. Запуск стека

```bash
# Запустить TT-RSS (отдельный compose)
docker compose -f docker/ttrss/docker-compose.yml up -d

# Запустить аналитический стек (ClickHouse + Shiny + MCP)
docker compose up -d --build
```

Сервисы:
- TT-RSS: http://localhost:8080 (admin / password)
- Shiny: http://localhost:3838/ttrss
- MCP: http://localhost:8000/mcp
- ClickHouse HTTP: http://localhost:8123

### 2. Добавление RSS-лент

```r
source("data-raw/add_security_feeds.R")
```

### 3. Сбор и классификация статей

```r
library(ttrssR)
# Сбор статей из TT-RSS
df <- fetch_news_dataframe(
  base_url = "http://localhost:8080",
  user = "admin",
  password = "password",
  max_articles = 500
)
# Классификация (LDA / kmeans / llm / yandex_llm)
df <- classify_news(df, n_topics = 8, method = "lda")
saveRDS(df, "data/news_raw.rds")
```

Пример для YandexGPT:

```r
Sys.setenv(
  YANDEX_CLOUD_FOLDER = "<folder_id>",
  YANDEX_CLOUD_API_KEY = "<api_key>",
  YANDEX_CLOUD_MODEL = "yandexgpt-lite/rc"
)

df <- classify_news(df, method = "yandex_llm")
```

Оценка качества тем:

```r
# После любой классификации (LDA/KMeans/LLM)
metrics <- evaluate_topic_quality(df)
print(metrics$label_coverage)
print(metrics$topic_distinctiveness)
print(metrics$per_topic)

# Либо сразу через classify_news:
df <- classify_news(df, method = "lda", compute_quality = TRUE)
attr(df, "topic_quality")
```

### 4. Автоматизированный сценарий (рекомендуется)

```r
source("data-raw/fetch_news.R")
```

### 4.1 Сравнение методов классификации

```r
source("data-raw/compare_methods.R")
```

Скрипт запускает `lda`, `kmeans` и (если заданы Yandex env) `yandex_llm` на одном датасете
и сохраняет метрики качества в:
- `data/method_comparison.csv`
- `data/method_comparison.rds`

### 5. Открыть дашборд

Перейти на http://localhost:3838/ttrss

### 6. Подключить MCP к Claude Code

```bash
claude mcp add ttrssR \
  "C:\Program Files\R\R-4.5.3\bin\Rscript.exe" \
  "D:\path\to\news-ai-aggregator\inst\mcp\stdio_server.R" \
  --env CH_HOST=localhost --env CH_PORT=9000 \
  --env CH_DB=ttrss --env CH_USER=default --env CH_PASSWORD=
```

После этого Claude Code может использовать инструменты `ttrssR` для анализа данных.

---

## Решённые технические проблемы

| Проблема | Причина | Решение |
|---------|--------|---------|
| `plumber` не устанавливается в Docker | Нет `libsodium-dev` в apt | Добавить `libsodium-dev` в Dockerfile |
| Docker кешировал сломанный слой | BuildKit сохранил слой с тихой ошибкой | `ARG CACHE_BUST=N` перед RUN |
| Shiny показывает пустой дашборд | Данные грузились в `observe()` асинхронно | Загрузка в `local({})` вне server-функции |
| MCP отвечает 405 на GET /mcp | plumber ожидал только POST | Переход на stdio-транспорт |
| `ttrssR` не ставится в MCP-контейнер | Зависимости shiny/ggplot2/plotly не нужны | `source("R/db.R")` вместо `library(ttrssR)` |
| NA в ClickHouse (UInt32, Float32) | RDS содержал NA в числовых колонках | Замена NA→0 для числовых, NA→"" для строк |
| `claude mcp list` не видит сервер | Claude Code читает `~/.claude.json`, не `settings.json` | Использовать `claude mcp add` команду |

---

## Репозиторий

https://github.com/AlexeyPetrov1/news-ai-aggregator
