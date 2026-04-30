# ttrssR: ETL + ML/NLP-пайплайн для новостей кибербезопасности

`ttrssR` — R-пакет и сервисный стек для полного цикла аналитики новостей:

RSS-сбор -> нормализация -> тематическая классификация (fixed taxonomy) -> хранение в ClickHouse -> визуализация в Shiny -> MCP-инструменты для AI-агентов.

## Что делает проект

- Тематика: threat intelligence, инциденты, уязвимости, вредоносное ПО, фишинг.
- Источник данных: TT-RSS (JSON API).
- Хранилище: ClickHouse.
- ML/NLP: `lda`, `kmeans`, `yandex_llm` (closed-set классификатор по фиксированной таксономии) + ненадзорные метрики качества.
- Интерфейсы: Shiny-дашборд и MCP-сервер (`stdio` + `HTTP`).

## Архитектура

1. TT-RSS агрегирует RSS-ленты.
2. `ttrssR` забирает и нормализует статьи.
3. Классификатор присваивает каждой статье одну тему из фиксированного списка (`DEFAULT_SECURITY_TOPICS`, включая `Other`).
4. Результаты сохраняются в ClickHouse.
5. Shiny показывает аналитику по уже классифицированным данным.
6. MCP отдает готовые выборки и агрегаты из ClickHouse (без ML-инференса в MCP-слое).

## Технологии

| Слой | Технология |
|---|---|
| Ядро | R (package-based architecture) |
| Сбор RSS | TT-RSS JSON API |
| ML / NLP | `topicmodels`, `tidytext`, Yandex GPT closed-set classifier |
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
│   ├── classify.R                    # lda/kmeans/yandex_llm + quality
│   ├── ground_truth.R                # optional validation utilities
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
│   ├── mini_ground_truth_workflow.R  # optional workflow, не основной контур
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

```bash
git clone https://github.com/AlexeyPetrov1/news-ai-aggregator.git
cd news-ai-aggregator
docker compose -p ttrss -f docker/ttrss/docker-compose.yml up -d
docker compose up -d --build
```

Далее:

1. Открыть `http://localhost:8080`.
2. Войти под `admin / password`.
3. Включить API-доступ (см. раздел "Включение TT-RSS API").
4. Выполнить `source("data-raw/add_security_feeds.R")`.
5. Выполнить `source("data-raw/fetch_news.R")`.
6. Проверить ClickHouse (см. раздел "Проверка ClickHouse").
7. Открыть `http://localhost:3838/ttrss`.

## Полный порядок запуска

### 1) Запуск TT-RSS

```bash
docker compose -p ttrss -f docker/ttrss/docker-compose.yml up -d
```

Проверка:

```bash
docker ps
docker network ls
```

TT-RSS должен быть доступен по адресу `http://localhost:8080`.
Логин/пароль по умолчанию: `admin / password`.

### 2) Запуск аналитического стека

```bash
docker compose up -d --build
```

Сервисы:

- Shiny: `http://localhost:3838/ttrss`
- MCP: `http://localhost:8000/mcp`
- ClickHouse HTTP: `http://localhost:8123`

Проверка:

```bash
docker ps
```

Ожидаемые контейнеры: `ttrss`, `ttrss-db`, `clickhouse`, `ttrss-shiny`, `ttrss-mcp`.

### 3) Добавление RSS-фидов

```r
source("data-raw/add_security_feeds.R")
```

Если появляется ошибка `API_DISABLED`, сначала включите API в TT-RSS (см. следующий раздел).

### 4) Сбор и классификация статей

```r
source("data-raw/fetch_news.R")
```

### 5) Открыть дашборд

Открой `http://localhost:3838/ttrss`.

## Включение TT-RSS API

Без включенного API скрипты работы с TT-RSS падают с ошибкой `API_DISABLED`.

### Через UI

1. Открыть `http://localhost:8080`.
2. Войти под `admin / password`.
3. Перейти в настройки пользователя.
4. Включить `Enable API access` / `Enable external API`.
5. Сохранить изменения.

### Через PostgreSQL

Проверить пользователей:

```bash
docker exec -it ttrss-db psql -U ttrss -d ttrss -c "SELECT id, login FROM ttrss_users;"
```

Включить API для `admin`:

```bash
docker exec -it ttrss-db psql -U ttrss -d ttrss -c "
INSERT INTO ttrss_user_prefs2 (owner_uid, pref_name, value, profile)
SELECT id, 'ENABLE_API_ACCESS', 'true', NULL
FROM ttrss_users
WHERE login = 'admin'
ON CONFLICT DO NOTHING;
"
```

Если запись уже есть:

```bash
docker exec -it ttrss-db psql -U ttrss -d ttrss -c "
UPDATE ttrss_user_prefs2
SET value = 'true'
WHERE owner_uid = (SELECT id FROM ttrss_users WHERE login = 'admin')
  AND pref_name = 'ENABLE_API_ACCESS';
"
```

Перезапустить TT-RSS:

```bash
docker restart ttrss
```

Проверка API:

```bash
curl -X POST http://localhost:8080/api/ \
  -H "Content-Type: application/json" \
  -d '{"op":"login","user":"admin","password":"password"}'
```

Ожидается `status: 0` и `session_id` в ответе.

## Важно: Shiny и ClickHouse — разные источники данных

Shiny dashboard может показывать данные из `data/news_raw.rds` (или соответствующего файла внутри контейнера), даже если таблицы в ClickHouse пустые. Это нормальная ситуация.

ClickHouse заполняется только после успешной записи через:

```r
ch_init_schema(con)
ch_write_articles(con, df)
```

или после успешного выполнения `data-raw/fetch_news.R` с заданным `CH_HOST`.

## Проверка ClickHouse

Показать базы:

```bash
docker exec -it clickhouse clickhouse-client --query "SHOW DATABASES"
```

Показать таблицы в базе `ttrss`:

```bash
docker exec -it clickhouse clickhouse-client --database ttrss --query "SHOW TABLES"
```

Проверить количество статей:

```bash
docker exec -it clickhouse clickhouse-client --database ttrss --query "SELECT count() FROM articles FINAL"
```

Посмотреть последние статьи:

```bash
docker exec -it clickhouse clickhouse-client --database ttrss --query "
SELECT published_at, feed_title, topic_label, title
FROM articles FINAL
ORDER BY published_at DESC
LIMIT 10
"
```

Важно: без `--database ttrss` запрос может выполняться в `default` и возвращать ошибку `Unknown table expression identifier 'articles'`.

## Ручная запись данных из RDS в ClickHouse

Если `news_raw.rds` уже есть, но ClickHouse пуст:

```powershell
docker exec -it ttrss-shiny Rscript -e "source('/pkg/ttrssR/R/db.R'); con <- ch_connect(); ch_init_schema(con); df <- readRDS('/srv/shiny-server/ttrss/shiny/data/news_raw.rds'); ch_write_articles(con, df); DBI::dbDisconnect(con)"
```

Проверка:

```powershell
docker exec -it clickhouse clickhouse-client --database ttrss --query "SELECT count() FROM articles FINAL"
```

## Типовые ошибки записи в ClickHouse

### Ошибка: `cannot write NA into a non-nullable column`

Причина: `NA` в колонках, объявленных в ClickHouse как non-nullable.

Проверка:

```powershell
docker exec -it ttrss-shiny Rscript -e "df <- readRDS('/srv/shiny-server/ttrss/shiny/data/news_raw.rds'); print(colSums(is.na(df)))"
```

В текущем `ch_write_articles()` в `R/db.R` `NA` уже заменяются на дефолтные значения перед записью.

### Ошибка: `input has 16 columns, but table articles has 15`

Обычно возникает, когда row names уезжают в отдельную колонку.
В текущем `ch_write_articles()` уже используется `row.names = FALSE`.

### Ошибка: `there is no package called 'ttrssR'`

В контейнере можно временно использовать прямой `source()`:

```powershell
docker exec -it ttrss-shiny Rscript -e "source('/pkg/ttrssR/R/db.R'); con <- ch_connect(); ch_init_schema(con); df <- readRDS('/srv/shiny-server/ttrss/shiny/data/news_raw.rds'); ch_write_articles(con, df); DBI::dbDisconnect(con)"
```

Проверить наличие исходников пакета:

```powershell
docker exec -it ttrss-shiny ls /pkg/ttrssR
```

## PowerShell: корректный quoting для `Rscript -e`

В PowerShell лучше использовать двойные кавычки вокруг всего выражения `Rscript -e`, а путь в R — в одинарных.

Правильно:

```powershell
docker exec -it ttrss-shiny Rscript -e "df <- readRDS('/srv/shiny-server/ttrss/shiny/data/news_raw.rds'); print(nrow(df))"
```

Неправильно:

```powershell
docker exec -it ttrss-shiny Rscript -e 'df <- readRDS("/srv/shiny-server/ttrss/shiny/data/news_raw.rds"); print(nrow(df))'
```

## Как применить изменения кода в Docker

Изменения локального файла (например, `R/db.R`) не всегда автоматически попадают в уже собранный контейнер.

Быстро скопировать файл в контейнер:

```powershell
docker cp R/db.R ttrss-shiny:/pkg/ttrssR/R/db.R
```

Проверка синтаксиса:

```powershell
docker exec -it ttrss-shiny Rscript -e "parse('/pkg/ttrssR/R/db.R'); cat('OK\n')"
```

Либо пересобрать сервис:

```powershell
docker compose up -d --build shiny
```

## Проверка MCP

Healthcheck:

```powershell
curl http://localhost:8000/health
```

Список инструментов:

```powershell
$r = Invoke-RestMethod -Method POST `
  -Uri "http://localhost:8000/mcp" `
  -ContentType "application/json" `
  -Body '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'

$r.result.tools | Format-Table name, description
```

PowerShell может показывать вложенные поля как `System.Object[]`. Это не ошибка. Для раскрытия:

```powershell
$r | ConvertTo-Json -Depth 20
```

Проверка последних статей:

```powershell
$r = Invoke-RestMethod -Method POST `
  -Uri "http://localhost:8000/mcp" `
  -ContentType "application/json" `
  -Body '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_recent_articles","arguments":{"limit":5}}}'

$r.result.content[0].text | ConvertFrom-Json | Format-Table
```

Проверка источников:

```powershell
$r = Invoke-RestMethod -Method POST `
  -Uri "http://localhost:8000/mcp" `
  -ContentType "application/json" `
  -Body '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_feed_stats","arguments":{}}}'

$r.result.content[0].text | ConvertFrom-Json | Format-Table
```

## Откуда вызывать MCP

С хост-машины: `http://localhost:8000/mcp`.
Из Docker-сети: `http://mcp:8000/mcp`.

Обычно для ручной проверки используется вызов с хоста:

```powershell
Invoke-RestMethod -Method POST `
  -Uri "http://localhost:8000/mcp" `
  -ContentType "application/json" `
  -Body '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

## Контрольные проверки после запуска

### 1) Сколько строк в RDS

```powershell
docker exec -it ttrss-shiny Rscript -e "df <- readRDS('/srv/shiny-server/ttrss/shiny/data/news_raw.rds'); cat(nrow(df), '\n')"
```

### 2) Сколько строк в ClickHouse

```powershell
docker exec -it clickhouse clickhouse-client --database ttrss --query "SELECT count() FROM articles FINAL"
```

### 3) Есть ли критичные пустые поля

```powershell
docker exec -it clickhouse clickhouse-client --database ttrss --query "
SELECT
    count() AS total,
    countIf(article_id = 0) AS bad_article_id,
    countIf(title = '') AS empty_title,
    countIf(content_text = '') AS empty_content_text,
    countIf(feed_id = 0) AS empty_feed_id,
    countIf(topic_label = '') AS empty_topic_label
FROM articles FINAL
"
```

### 4) Распределение тем

```powershell
docker exec -it clickhouse clickhouse-client --database ttrss --query "
SELECT topic_label, count() AS n
FROM articles FINAL
GROUP BY topic_label
ORDER BY n DESC
"
```

### 5) Свежесть данных

```powershell
docker exec -it clickhouse clickhouse-client --database ttrss --query "
SELECT
    min(published_at) AS first_article,
    max(published_at) AS last_article,
    max(fetched_at) AS last_fetch
FROM articles FINAL
"
```

### 6) MCP возвращает статьи

```powershell
$r = Invoke-RestMethod -Method POST `
  -Uri "http://localhost:8000/mcp" `
  -ContentType "application/json" `
  -Body '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_recent_articles","arguments":{"limit":5}}}'

$r.result.content[0].text | ConvertFrom-Json | Format-Table
```

## Известные проблемы текущей версии

1. Shiny dashboard может читать `news_raw.rds`, поэтому может показывать данные даже при пустом ClickHouse.
2. Для ClickHouse-запросов важно указывать корректную базу (`--database ttrss`).
3. После изменения R-кода локально может потребоваться `docker cp` или пересборка контейнера.
4. В PowerShell нужно аккуратное quoting для `Rscript -e`.

## ML-этап: текущее состояние

### Поддерживаемые методы

- `lda`: тематическое моделирование (`topicmodels::LDA`);
- `kmeans`: baseline-кластеризация по TF-IDF;
- `yandex_llm`: Yandex Assistant API (`gpt://<folder>/<model>`) в режиме closed-set классификации.

### Closed-set инварианты для `yandex_llm`

- retry + exponential backoff на `429/5xx`;
- session-cache для повторяющихся текстов;
- persistent cache (`data/yandex_llm_cache.rds`) между запусками;
- fixed taxonomy (`DEFAULT_SECURITY_TOPICS`) c обязательным `Other`;
- prompt с выбором ровно одной метки из разрешенного списка;
- post-validation ответа и fallback в `Other` для невалидных/неизвестных меток.

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

## Optional validation: mini ground-truth

`mini_ground_truth_workflow.R` остается как опциональная проверка, но не является основным публичным контуром оценки модели.

## Переменные окружения

Основные:

- `TTRSS_URL`, `TTRSS_USER`, `TTRSS_PASSWORD`
- `CH_HOST`, `CH_PORT`, `CH_DB`, `CH_USER`, `CH_PASSWORD`
- `CLASSIFY_METHOD`, `N_TOPICS`, `MAX_ARTICLES`

Пример для PowerShell:

```powershell
$env:TTRSS_URL="http://localhost:8080"
$env:TTRSS_USER="admin"
$env:TTRSS_PASSWORD="password"
$env:MAX_ARTICLES="500"
$env:CLASSIFY_METHOD="lda"
$env:N_TOPICS="8"

$env:CH_HOST="localhost"
$env:CH_PORT="9000"
$env:CH_DB="ttrss"
$env:CH_USER="default"
$env:CH_PASSWORD=""
```

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

Роль MCP:

- MCP не выполняет ML-классификацию.
- MCP читает уже классифицированные данные и агрегаты из ClickHouse.

Доступные инструменты (`tools`):

- `search_articles`
- `get_topic_summary`
- `get_recent_articles`
- `get_feed_stats`

Доступные ресурсы (`resources`):

- `ttrss://articles`
- `ttrss://topics`

## Формулировка для презентации

Корректная формулировка:

- реализован ETL + ML/NLP-пайплайн тематической классификации новостей;
- классификация: `lda` / `kmeans` / `yandex_llm` (fixed-taxonomy closed-set);
- результаты сервируются через ClickHouse, Shiny и MCP.

Нежелательная формулировка:

- "обучил ML-модель" (не отражает фактическую архитектуру проекта).

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
