# ttrssR: ML-пайплайн для анализа новостей по кибербезопасности

`ttrssR` — R-пакет и сервисный стек для полного цикла аналитики новостей:

RSS-сбор -> нормализация -> тематическая классификация -> хранение в ClickHouse -> визуализация в Shiny -> MCP-инструменты для AI-агентов.

## Что делает проект

- Тематика: threat intelligence, инциденты, уязвимости, вредоносное ПО, фишинг.
- Источник данных: TT-RSS (JSON API).
- Хранилище: ClickHouse.
- ML: `lda`, `kmeans`, `llm`, `yandex_llm` + метрики качества.
- Интерфейсы: Shiny-дашборд и MCP-сервер (`stdio` + `HTTP`).

## Архитектура

1. TT-RSS агрегирует RSS-ленты.
2. `ttrssR` забирает и нормализует статьи.
3. Статьи классифицируются выбранным ML-методом.
4. Результаты пишутся в ClickHouse.
5. Данные доступны через Shiny и MCP.

## Технологии

| Слой | Технология |
|---|---|
| Ядро | R (package-based architecture) |
| Сбор RSS | TT-RSS JSON API |
| ML / NLP | `topicmodels`, `tidytext`, LLM-backends |
| БД | ClickHouse |
| Визуализация | Shiny + shinydashboard + plotly + DT |
| Agent API | MCP (JSON-RPC 2.0) |
| Оркестрация | Docker Compose |

## Структура репозитория

```text
news-ai-aggregator/
├── R/
│   ├── api.R                         # клиент TT-RSS API
│   ├── etl.R                         # сбор и нормализация данных
│   ├── classify.R                    # lda/kmeans/llm/yandex_llm + quality
│   ├── ground_truth.R                # canonical mapping + supervised metrics
│   ├── db.R                          # слой ClickHouse
│   └── app.R                         # run_dashboard() / run_mcp_server()
├── inst/
│   ├── shiny/                        # Shiny-приложение
│   └── mcp/                          # MCP-серверы (stdio + HTTP)
├── data-raw/
│   ├── add_security_feeds.R
│   ├── replace_feeds_ru.R
│   ├── fetch_news.R
│   ├── compare_methods.R
│   ├── mini_ground_truth_workflow.R
│   └── canonical_topic_mapping_template.csv
├── tests/testthat/
│   ├── test-api.R
│   ├── test-etl.R
│   ├── test-classify.R
│   └── test-ground-truth.R
├── docker-compose.yml                # аналитический стек (CH + Shiny + MCP)
├── docker/ttrss/docker-compose.yml   # TT-RSS + PostgreSQL
└── README.md
```

## Быстрый старт

### Требования

- Docker Desktop
- R (рекомендуется 4.5+)

### 1) Запуск TT-RSS

```bash
docker compose -f docker/ttrss/docker-compose.yml up -d
```

URL TT-RSS: `http://localhost:8080`

### 2) Запуск аналитического стека

```bash
docker compose up -d --build
```

Сервисы:

- Shiny: `http://localhost:3838/ttrss`
- MCP: `http://localhost:8000/mcp`
- ClickHouse HTTP: `http://localhost:8123`

### 3) Сбор и классификация статей

```r
source("data-raw/fetch_news.R")
```

### 4) Открыть дашборд

Открой `http://localhost:3838/ttrss`.

## ML-этап: текущее состояние

### Поддерживаемые методы

- `lda`: тематическое моделирование (`topicmodels::LDA`);
- `kmeans`: baseline-кластеризация по TF-IDF;
- `llm`: универсальный backend для LLM-тегирования;
- `yandex_llm`: Yandex Assistant API (`gpt://<folder>/<model>`).

### Улучшения для `yandex_llm`

- retry + exponential backoff на `429/5xx`;
- session-cache для повторяющихся текстов;
- persistent cache (`data/yandex_llm_cache.rds`) между запусками;
- fallback в `"Без категории"` при сбоях API.

### Ненадзорные метрики качества

`evaluate_topic_quality()` возвращает:

- `label_coverage`;
- `dominant_topic_share`;
- `topic_balance_entropy`;
- `topic_distinctiveness`;
- распределение по темам (`per_topic`).

Пример:

```r
df <- classify_news(df, method = "lda", compute_quality = TRUE)
attr(df, "topic_quality")
```

## Бенчмарк методов

Запуск сравнения на одном датасете:

```r
source("data-raw/compare_methods.R")
```

Результаты:

- `data/method_comparison.csv`
- `data/method_comparison.rds`

## Mini ground-truth + canonical mapping

Этот workflow дает supervised-метрики для презентации: `accuracy`, `macro_f1`, confusion matrix.

Запуск:

```r
source("data-raw/mini_ground_truth_workflow.R")
```

### Последовательность

1. Скрипт создает `data/ground_truth_template.csv`.
2. Вручную заполняется колонка `topic_true`.
3. Файл сохраняется как `data/ground_truth_labeled.csv`.
4. Скрипт запускается повторно и считает метрики.

### Файлы

- шаблон mapping: `data-raw/canonical_topic_mapping_template.csv`
- сводка метрик: `data/ground_truth_metrics.csv`
- полный отчет: `data/ground_truth_metrics.rds`

### Переиспользуемые функции

- `create_ground_truth_sample()`
- `apply_canonical_label_mapping()`
- `evaluate_against_ground_truth()`

## Переменные окружения

Основные:

- `TTRSS_URL`, `TTRSS_USER`, `TTRSS_PASSWORD`
- `CH_HOST`, `CH_PORT`, `CH_DB`, `CH_USER`, `CH_PASSWORD`
- `CLASSIFY_METHOD`, `N_TOPICS`, `MAX_ARTICLES`

Для Yandex LLM:

- `YANDEX_CLOUD_API_KEY`
- `YANDEX_CLOUD_FOLDER`
- `YANDEX_CLOUD_MODEL` (по умолчанию `yandexgpt-lite/rc`)
- `YANDEX_CLOUD_BASE_URL` (по умолчанию `https://rest-assistant.api.cloud.yandex.net/v1`)
- `YANDEX_CACHE_PATH` (опционально, путь к cache-файлу)

## MCP-интеграция

В проекте есть:

- `inst/mcp/stdio_server.R` — локальный транспорт через stdin/stdout;
- `inst/mcp/server.R` — HTTP-вариант для Docker.

Доступные инструменты:

- `search_articles`
- `get_topic_summary`
- `get_recent_articles`
- `get_feed_stats`

## Тестирование

Покрытие тестами (`tests/testthat`):

- API-слой (`test-api.R`);
- ETL и нормализация (`test-etl.R`);
- классификация и quality-логика (`test-classify.R`);
- ground-truth/canonical mapping (`test-ground-truth.R`).

Запуск тестов (локально при установленном R):

```r
testthat::test_dir("tests/testthat")
```

## Репозиторий

https://github.com/AlexeyPetrov1/news-ai-aggregator
