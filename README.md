# news-ai-aggregator

`news-ai-aggregator` — R-based ETL/ML/NLP-пайплайн для сбора, тематической классификации и аналитики новостей по кибербезопасности.

Основной поток данных:

```text
TT-RSS -> нормализация -> topic classification -> ClickHouse -> Shiny + MCP
```

Проект собирает статьи из TT-RSS, нормализует их, присваивает каждой новости тему, сохраняет результат в ClickHouse, показывает аналитику в Shiny и отдает готовые выборки через MCP-инструменты.

---

## 1. Что делает проект

Проект предназначен для аналитики новостей по кибербезопасности:

- собирает RSS-новости через TT-RSS JSON API;
- нормализует статьи в R-пайплайне;
- классифицирует новости по фиксированной таксономии security-тем;
- сохраняет статьи, фиды и агрегаты в ClickHouse;
- показывает интерактивный Shiny-дашборд;
- предоставляет MCP JSON-RPC endpoint для AI-агентов;
- поддерживает периодический ingestion через `scheduler`.

Тематика данных:

- threat intelligence;
- инциденты информационной безопасности;
- уязвимости;
- malware;
- phishing;
- общие cybersecurity-новости.

---

## 2. Актуальная архитектура

```text
                  +----------------+
                  | RSS источники   |
                  +--------+-------+
                           |
                           v
                  +----------------+
                  |    TT-RSS      |
                  | UI + JSON API  |
                  +--------+-------+
                           |
                           v
                  +----------------+
                  | scheduler      |
                  | fetch_news.R   |
                  +--------+-------+
                           |
                           v
                  +----------------+
                  | R ETL / ML     |
                  | normalize      |
                  | classify       |
                  +--------+-------+
                           |
                           v
                  +----------------+
                  |  ClickHouse    |
                  | articles       |
                  | feeds          |
                  | topic_summary  |
                  +----+-------+---+
                       |       |
              +--------+       +---------+
              v                          v
       +--------------+           +--------------+
       | Shiny UI     |           | MCP endpoint |
       | dashboard    |           | JSON-RPC     |
       +--------------+           +--------------+
```

Ключевой принцип текущей версии: **основной ingestion-контур — `scheduler`, а не ручной запуск `source("data-raw/fetch_news.R")`**.

`scheduler` циклически:

1. запускает `Rscript data-raw/fetch_news.R`;
2. инициализирует схему ClickHouse через `ch_init_schema`;
3. записывает или обновляет данные через `ch_write_articles`;
4. ждет `SCHEDULER_INTERVAL_SECONDS`;
5. повторяет цикл.

Такой режим нужен, чтобы проект автоматически восстанавливался после сброса volume ClickHouse.

---

## 3. Docker-сервисы

TT-RSS запускается отдельным compose-проектом из `docker/ttrss/docker-compose.yml`.

Аналитический стек запускается из корня репозитория через основной `docker-compose.yml`.

| Сервис | Назначение |
|---|---|
| `clickhouse` | аналитическое хранилище |
| `scheduler` | периодический запуск `fetch_news.R`; основной ingestion path |
| `shiny` | UI-дашборд |
| `mcp` | JSON-RPC endpoint с MCP-инструментами |
| `ttrss` | TT-RSS web UI и API, отдельный compose-проект |
| `ttrss-db` | PostgreSQL для TT-RSS, отдельный compose-проект |

---

## 4. Service URLs

| Компонент | URL |
|---|---|
| TT-RSS UI | `http://localhost:8080` |
| TT-RSS API | `http://localhost:8080/api/` |
| Shiny dashboard | `http://localhost:3838/ttrss` |
| MCP endpoint | `http://localhost:8000/mcp` |
| MCP healthcheck | `http://localhost:8000/health` |
| ClickHouse HTTP | `http://localhost:8123` |

Логин и пароль TT-RSS по умолчанию, если они не изменены в `.env` или compose-файлах:

```text
admin / password
```

---

## 5. Технологии

| Слой | Технологии |
|---|---|
| Core | R, package-based структура |
| RSS ingestion | TT-RSS JSON API |
| ETL | R scripts в `R/` и `data-raw/` |
| ML / NLP | `lda`, `kmeans`, `yandex_llm` |
| LLM-классификация | Yandex GPT / Yandex AI Studio API |
| Storage | ClickHouse |
| Dashboard | Shiny, shinydashboard, plotly, DT |
| Agent API | MCP over JSON-RPC 2.0 |
| Runtime | Docker Compose |

---

## 6. Структура репозитория

```text
news-ai-aggregator/
├── R/
│   ├── api.R                         # клиент TT-RSS API
│   ├── etl.R                         # сбор и нормализация данных
│   ├── classify.R                    # lda / kmeans / yandex_llm + quality logic
│   ├── ground_truth.R                # optional validation utilities
│   ├── db.R                          # ClickHouse layer
│   └── app.R                         # run_dashboard() / run_mcp_server()
│
├── data-raw/
│   ├── add_security_feeds.R          # добавление security RSS-фидов
│   ├── replace_feeds_ru.R            # замена / настройка русскоязычных фидов
│   ├── fetch_news.R                  # основной ingestion script
│   ├── compare_methods.R             # сравнение методов классификации
│   ├── mini_ground_truth_workflow.R  # optional validation workflow
│   └── canonical_topic_mapping_template.csv
│
├── inst/
│   ├── shiny/                        # Shiny dashboard
│   └── mcp/                          # MCP server: stdio + HTTP
│
├── tests/testthat/
│   ├── test-api.R
│   ├── test-etl.R
│   ├── test-classify.R
│   └── test-ground-truth.R
│
├── docker/ttrss/
│   └── docker-compose.yml            # отдельный стек TT-RSS + PostgreSQL
│
├── docker-compose.yml                # analytics stack: CH + scheduler + Shiny + MCP
├── .env.example                      # шаблон переменных окружения
└── README.md
```

---

## 7. Переменные окружения

Используйте `.env.example` как шаблон.

Минимальный набор для стабильной работы `scheduler`:

```env
TTRSS_ADMIN_USER=admin
TTRSS_ADMIN_PASSWORD=password

CH_DB=ttrss
CH_USER=default
CH_PASSWORD=

MAX_ARTICLES=500
SCHEDULER_INTERVAL_SECONDS=3600

CLASSIFY_METHOD=lda
N_TOPICS=8
```

В Docker Compose `scheduler` должен обращаться к ClickHouse по имени сервиса:

```env
CH_HOST=clickhouse
CH_PORT=9000
```

Для локального ручного запуска с хост-машины обычно используется:

```env
CH_HOST=localhost
CH_PORT=9000
```

Если в старых скриптах используются переменные `TTRSS_URL`, `TTRSS_USER`, `TTRSS_PASSWORD`, проверьте фактический код и `.env.example`. В актуальном Docker-контуре основными считаются `TTRSS_ADMIN_USER` и `TTRSS_ADMIN_PASSWORD`.

---

## 8. Yandex LLM: настройка классификатора

`yandex_llm` используется как closed-set классификатор: модель должна выбрать ровно одну тему из фиксированного списка `DEFAULT_SECURITY_TOPICS`. Если ответ модели не совпадает с разрешенными метками, пайплайн должен fallback-нуться в `Other`.

Переменные окружения для Yandex-классификации:

```env
YANDEX_CLOUD_API_KEY=<secret API key service account или AI Studio API key>
YANDEX_CLOUD_FOLDER=<folder_id>
YANDEX_CLOUD_MODEL=yandexgpt-lite/rc
YANDEX_CLOUD_BASE_URL=https://rest-assistant.api.cloud.yandex.net/v1
YANDEX_CACHE_PATH=data/yandex_llm_cache.rds
```

Практическое правило:

- для заголовка `Authorization: Api-Key <...>` нужен именно **секрет API key**, а не OAuth/IAM token и не ID ключа;
- API key должен быть связан с сервисным аккаунтом или создан через AI Studio;
- folder id должен соответствовать каталогу, где доступна модель;
- секреты нельзя коммитить в репозиторий;
- значения нужно хранить в `.env`, переменных окружения или secrets-хранилище.

Пример `.env` для режима `yandex_llm`:

```env
CLASSIFY_METHOD=yandex_llm
N_TOPICS=8
MAX_ARTICLES=500

YANDEX_CLOUD_API_KEY=***
YANDEX_CLOUD_FOLDER=b1gxxxxxxxxxxxxxxx
YANDEX_CLOUD_MODEL=yandexgpt-lite/rc
YANDEX_CLOUD_BASE_URL=https://rest-assistant.api.cloud.yandex.net/v1
YANDEX_CACHE_PATH=data/yandex_llm_cache.rds
```

Инварианты `yandex_llm`-классификации:

- fixed taxonomy;
- обязательная тема `Other`;
- выбор ровно одной метки;
- post-validation ответа модели;
- fallback в `Other` для неизвестных меток;
- retry + exponential backoff для `429` и `5xx`;
- session-cache для повторяющихся текстов;
- persistent cache между запусками.

---

## 9. Быстрый старт

### 9.1. Требования

- Docker Desktop;
- Docker Compose v2;
- R локально нужен только для ручного запуска и разработки;
- активный доступ к Yandex Cloud / AI Studio нужен только для `CLASSIFY_METHOD=yandex_llm`.

### 9.2. Клонирование

```bash
git clone https://github.com/AlexeyPetrov1/news-ai-aggregator.git
cd news-ai-aggregator
```

### 9.3. Подготовка `.env`

```bash
cp .env.example .env
```

Проверьте значения:

```bash
cat .env
```

Минимально проверьте:

- `TTRSS_ADMIN_USER`;
- `TTRSS_ADMIN_PASSWORD`;
- `CH_DB`;
- `CH_USER`;
- `CH_PASSWORD`;
- `MAX_ARTICLES`;
- `SCHEDULER_INTERVAL_SECONDS`;
- `CLASSIFY_METHOD`;
- `N_TOPICS`.

---

## 10. Clean start: рекомендуемый запуск

Из корня репозитория:

```bash
# 1. Запустить TT-RSS stack
docker compose -p ttrss -f docker/ttrss/docker-compose.yml up -d
```
### ОБЯЗАТЕЛЬНО:
---

### Первый запуск TT-RSS

Откройте:

```text
http://localhost:8080
```

Войдите под админским пользователем.

Если используются дефолтные значения:

```text
admin / password
```

Далее нужно включить API-доступ.

### Включение API через UI

1. Открыть `http://localhost:8080`.
2. Войти под admin-пользователем.
3. Перейти в user settings.
4. Включить `Enable API access` / `Enable external API`.
5. Сохранить изменения.

Если API не включен, ingestion падает с ошибкой:

```text
API_DISABLED
```

### Включение оставшихся контейнеров:
```bash
# 2. Запустить основной ingestion-контур
docker compose up -d --build
# ЛИБО Если не нужны dashboard и MCP endpoint:
#docker compose up -d --build scheduler
```

Проверка контейнеров:

```bash
docker compose ps
docker ps
```

Ожидаемо должны быть запущены:

- TT-RSS stack: `ttrss`, `ttrss-db`;
- analytics stack: `clickhouse`, `scheduler`, опционально `shiny`, `mcp`.


---

## 11. Добавление RSS-фидов
### Данный этап необходим только в случае, если за 5 минут у вас не подтянулись новости

Если фиды еще не добавлены, можно выполнить соответствующий script.

Локально, при настроенном R-окружении:

```r
source("data-raw/add_security_feeds.R")
```

Или внутри контейнера, если в нем доступны исходники проекта и R-зависимости:

```bash
docker exec -it ttrss-scheduler Rscript data-raw/add_security_feeds.R
```

Если появляется `API_DISABLED`, сначала включите TT-RSS API.

---

## 12. Scheduler-first workflow

`scheduler` — основной способ регулярного обновления данных.

Запуск только scheduler:

```bash
docker compose up -d --build scheduler
```

Логи:

```bash
docker logs -f ttrss-scheduler
```

Ожидаемое поведение:

- повторяющиеся циклы `fetch_news`;
- отсутствие fatal errors;
- создание таблиц в ClickHouse;
- рост количества строк в `articles` при появлении новых статей.

Проверить, что scheduler жив:

```bash
docker compose ps
```

---

## 13. Проверка ClickHouse

Показать базы:

```bash
docker exec -it clickhouse clickhouse-client --query "SHOW DATABASES"
```

Показать таблицы в базе `ttrss`:

```bash
docker exec -it clickhouse clickhouse-client --database ttrss --query "SHOW TABLES"
```

Ожидаемые таблицы:

```text
articles
feeds
topic_summary
```

Проверить количество статей:

```bash
docker exec -it clickhouse clickhouse-client --database ttrss --query "SELECT count() FROM articles FINAL"
```

Ожидаемо:

```text
count() > 0
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

Проверить распределение тем:

```bash
docker exec -it clickhouse clickhouse-client --database ttrss --query "
SELECT topic_label, count() AS n
FROM articles FINAL
GROUP BY topic_label
ORDER BY n DESC
"
```

Проверить свежесть данных:

```bash
docker exec -it clickhouse clickhouse-client --database ttrss --query "
SELECT
    min(published_at) AS first_article,
    max(published_at) AS last_article,
    max(fetched_at) AS last_fetch
FROM articles FINAL
"
```

Важно: для SQL-запросов указывайте `--database ttrss`. Без этого `clickhouse-client` может использовать базу `default`, и запрос к `articles` завершится ошибкой.

---

## 14. Контроль качества данных

Проверить критичные пустые поля:

```bash
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

Интерпретация:

- `bad_article_id > 0` — проблема с идентификаторами;
- `empty_title > 0` — часть новостей пришла без заголовков;
- `empty_content_text > 0` — возможно, RSS содержит только title/summary;
- `empty_topic_label > 0` — проблема на этапе классификации или fallback-логики.

---

## 15. Shiny dashboard

Запуск полного стека:

```bash
docker compose up -d --build
```

Открыть dashboard:

```text
http://localhost:3838/ttrss
```

Важное ограничение: Shiny может показывать локальный cache/RDS-файл, даже если ClickHouse пуст. Поэтому состояние пайплайна нужно валидировать через ClickHouse:

```bash
docker exec -it clickhouse clickhouse-client --database ttrss --query "SELECT count() FROM articles FINAL"
```

Если dashboard показывает данные, а `articles` пустой — это не доказательство успешной записи в ClickHouse.

---

## 16. MCP-интеграция

MCP endpoint:

```text
http://localhost:8000/mcp
```

Healthcheck:

```bash
curl http://localhost:8000/health
```

Список инструментов:

```bash
curl -X POST http://localhost:8000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

Роль MCP:

- MCP не выполняет ML-инференс;
- MCP не классифицирует новые статьи;
- MCP читает уже подготовленные данные и агрегаты из ClickHouse;
- MCP нужен как интерфейс для AI-агентов и внешних клиентов.

Доступные инструменты:

| Tool | Назначение |
|---|---|
| `search_articles` | поиск статей |
| `get_topic_summary` | агрегаты по темам |
| `get_recent_articles` | последние статьи |
| `get_feed_stats` | статистика по источникам |

Доступные ресурсы:

```text
ttrss://articles
ttrss://topics
```

### 16.1. Проверка последних статей через MCP

Bash/cURL:

```bash
curl -X POST http://localhost:8000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_recent_articles","arguments":{"limit":5}}}'
```

PowerShell:

```powershell
$r = Invoke-RestMethod -Method POST `
  -Uri "http://localhost:8000/mcp" `
  -ContentType "application/json" `
  -Body '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_recent_articles","arguments":{"limit":5}}}'

$r.result.content[0].text | ConvertFrom-Json | Format-Table
```

### 16.2. Проверка источников через MCP

```powershell
$r = Invoke-RestMethod -Method POST `
  -Uri "http://localhost:8000/mcp" `
  -ContentType "application/json" `
  -Body '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_feed_stats","arguments":{}}}'

$r.result.content[0].text | ConvertFrom-Json | Format-Table
```

PowerShell может отображать вложенные поля как `System.Object[]`. Для раскрытия JSON используйте:

```powershell
$r | ConvertTo-Json -Depth 20
```

---

## 17. Manual one-time run

Ручной запуск не является основным production-flow. Он полезен для отладки.

Локально:

```r
source("data-raw/fetch_news.R")
```

Через Rscript:

```bash
Rscript data-raw/fetch_news.R
```

Перед ручным запуском проверьте переменные окружения. Для локального запуска чаще нужен `CH_HOST=localhost`, а не `CH_HOST=clickhouse`.

---

## 18. Reset and re-validate

Используйте этот сценарий, когда нужно проверить восстановление с нуля после удаления ClickHouse volume.

```bash
# Остановить analytics stack и удалить volumes

docker compose down -v --remove-orphans

# Запустить scheduler заново

docker compose up -d --build scheduler
```

После этого повторить проверки:

```bash
docker logs -f ttrss-scheduler
```

```bash
docker exec -it clickhouse clickhouse-client --database ttrss --query "SHOW TABLES"
```

```bash
docker exec -it clickhouse clickhouse-client --database ttrss --query "SELECT count() FROM articles FINAL"
```

Важно: команда выше сбрасывает volume основного analytics stack. TT-RSS находится в отдельном compose-проекте `ttrss`, поэтому его данные не должны удаляться этим вызовом из корня репозитория. Для сброса TT-RSS нужно отдельно выполнять команды с `-p ttrss -f docker/ttrss/docker-compose.yml`.

---

## 19. ML-этап

Поддерживаемые методы классификации:

| Method | Описание |
|---|---|
| `lda` | тематическое моделирование через `topicmodels::LDA` |
| `kmeans` | baseline-кластеризация по TF-IDF |
| `yandex_llm` | closed-set классификация через Yandex GPT |

`yandex_llm` лучше использовать, если нужна интерпретируемая классификация в фиксированную бизнес-таксономию.

`lda` и `kmeans` полезны как baseline и как способ быстро проверить структуру корпуса без LLM.

### 19.1. Ненадзорные метрики качества

`evaluate_topic_quality()` возвращает:

- `label_coverage`;
- `dominant_topic_share`;
- `topic_balance_entropy`;
- `topic_distinctiveness`;
- `per_topic` распределение.

Пример:

```r
df <- classify_news(df, method = "lda", compute_quality = TRUE)
attr(df, "topic_quality")
```

### 19.2. Бенчмарк методов

```r
source("data-raw/compare_methods.R")
```

Артефакты сравнения:

```text
data/method_comparison.csv
data/method_comparison.rds
```

### 19.3. Optional mini ground-truth

`mini_ground_truth_workflow.R` остается опциональным validation workflow. Это не основной публичный контур оценки модели.

---

## 20. Артефакты проекта

Основные runtime-артефакты:

| Артефакт | Где находится | Когда появляется |
|---|---|---|
| `articles` | ClickHouse, база `ttrss` | после успешного `fetch_news.R` |
| `feeds` | ClickHouse, база `ttrss` | после инициализации схемы / записи данных |
| `topic_summary` | ClickHouse, база `ttrss` | после агрегации тем |
| `data/yandex_llm_cache.rds` | filesystem | после классификации через `yandex_llm` |
| `data/method_comparison.csv` | filesystem | после `compare_methods.R` |
| `data/method_comparison.rds` | filesystem | после `compare_methods.R` |
| `data/news_raw.rds` | filesystem / Shiny data dir | legacy/local cache для dashboard |

Операционные endpoints:

| Endpoint | Назначение |
|---|---|
| `http://localhost:8080` | TT-RSS UI |
| `http://localhost:8080/api/` | TT-RSS JSON API |
| `http://localhost:3838/ttrss` | Shiny dashboard |
| `http://localhost:8000/mcp` | MCP JSON-RPC endpoint |
| `http://localhost:8000/health` | MCP healthcheck |
| `http://localhost:8123` | ClickHouse HTTP |

---

## 21. Типовые проблемы и диагностика

### 21.1. `API_DISABLED`

Причина: в TT-RSS не включен API-доступ.

Что сделать:

1. Открыть `http://localhost:8080`.
2. Войти под admin-пользователем.
3. Включить `API access` / `external API` в настройках.
4. Повторить запуск scheduler.

Проверка:

```bash
curl -X POST http://localhost:8080/api/ \
  -H "Content-Type: application/json" \
  -d '{"op":"login","user":"admin","password":"password"}'
```

---

### 21.2. `articles` table missing

Возможные причины:

- scheduler не стартовал;
- ClickHouse не готов;
- `fetch_news.R` упал до `ch_init_schema`;
- неверные переменные окружения ClickHouse.

Проверки:

```bash
docker compose ps
docker logs -f ttrss-scheduler
docker exec -it clickhouse clickhouse-client --database ttrss --query "SHOW TABLES"
```

---

### 21.3. `count()` не растет

Возможные причины:

- нет активных RSS-фидов;
- в TT-RSS нет новых entries;
- scheduler не работает;
- классификация падает до записи;
- ClickHouse пишет в другую базу.

Проверки:

```bash
docker logs -f ttrss-scheduler
docker compose ps
docker exec -it clickhouse clickhouse-client --database ttrss --query "SELECT count() FROM articles FINAL"
```

---

### 21.4. Dashboard показывает данные, но ClickHouse пустой

Это известная особенность: Shiny может читать cached/local RDS-данные. Источником истины для backend-пайплайна считается ClickHouse.

Проверка:

```bash
docker exec -it clickhouse clickhouse-client --database ttrss --query "SELECT count() FROM articles FINAL"
```

---

### 21.5. `Unknown table expression identifier 'articles'`

Чаще всего запрос выполняется не в базе `ttrss`, а в `default`.

Правильно:

```bash
docker exec -it clickhouse clickhouse-client --database ttrss --query "SELECT count() FROM articles FINAL"
```

---

### 21.6. `cannot write NA into a non-nullable column`

Причина: попытка записать `NA` в ClickHouse-колонку, объявленную как non-nullable.

Проверка RDS/cache-данных:

```powershell
docker exec -it ttrss-shiny Rscript -e "df <- readRDS('/srv/shiny-server/ttrss/shiny/data/news_raw.rds'); print(colSums(is.na(df)))"
```

Ожидаемое поведение актуального `ch_write_articles()`: заменить `NA` на дефолтные значения перед записью.

---

### 21.7. `input has 16 columns, but table articles has 15`

Типичная причина: row names записываются как отдельная колонка.

Ожидаемое поведение актуального `ch_write_articles()`: запись с `row.names = FALSE`.

---

### 21.8. `there is no package called 'ttrssR'`

Если пакет не установлен внутри контейнера, можно временно использовать прямой `source()` нужных R-файлов.

Пример:

```powershell
docker exec -it ttrss-shiny Rscript -e "source('/pkg/ttrssR/R/db.R'); con <- ch_connect(); ch_init_schema(con); df <- readRDS('/srv/shiny-server/ttrss/shiny/data/news_raw.rds'); ch_write_articles(con, df); DBI::dbDisconnect(con)"
```

Проверить исходники:

```powershell
docker exec -it ttrss-shiny ls /pkg/ttrssR
```

---

### 21.9. MCP не отвечает

Проверки:

```bash
docker compose ps
curl http://localhost:8000/health
docker logs -f ttrss-mcp
```

Если endpoint недоступен, убедитесь, что полный стек запущен:

```bash
docker compose up -d --build
```

---

## 22. PowerShell: quoting для `Rscript -e`

В PowerShell удобнее использовать двойные кавычки вокруг всего выражения `Rscript -e`, а строки внутри R писать в одинарных кавычках.

Правильно:

```powershell
docker exec -it ttrss-shiny Rscript -e "df <- readRDS('/srv/shiny-server/ttrss/shiny/data/news_raw.rds'); print(nrow(df))"
```

Проблемный вариант:

```powershell
docker exec -it ttrss-shiny Rscript -e 'df <- readRDS("/srv/shiny-server/ttrss/shiny/data/news_raw.rds"); print(nrow(df))'
```

---

## 23. Как применить изменения кода в Docker

Если вы изменили локальный R-файл, он не всегда сразу попадает в уже собранный контейнер.

Быстро скопировать файл:

```powershell
docker cp R/db.R ttrss-shiny:/pkg/ttrssR/R/db.R
```

Проверить синтаксис:

```powershell
docker exec -it ttrss-shiny Rscript -e "parse('/pkg/ttrssR/R/db.R'); cat('OK\n')"
```

Более надежный вариант — пересобрать сервис:

```bash
docker compose up -d --build shiny
```

Для изменений ingestion-логики чаще пересобирайте `scheduler`:

```bash
docker compose up -d --build scheduler
```

---

## 24. Тестирование

Покрытие тестами:

- API-слой;
- ETL и нормализация;
- классификация и quality-логика;
- ground-truth / canonical mapping.

Запуск тестов локально:

```r
testthat::test_dir("tests/testthat")
```

Если зависимости проекта оформлены как R-пакет, предпочтительно запускать тесты из корня репозитория в настроенном R-окружении.

---

## 25. Рекомендованная формулировка для презентации

Корректно:

```text
Реализован ETL + ML/NLP-пайплайн тематической классификации новостей по кибербезопасности.
Данные собираются из TT-RSS, нормализуются, классифицируются методами lda / kmeans / yandex_llm,
сохраняются в ClickHouse и доступны через Shiny dashboard и MCP JSON-RPC endpoint.
```

Не очень корректно:

```text
Я обучил ML-модель для классификации новостей.
```

Почему: в текущей архитектуре важнее не обучение одной модели, а полный production-like pipeline: ingestion, нормализация, классификация, storage, dashboard, MCP и scheduler.

---

## 26. Минимальный чеклист после запуска

```bash
# 1. TT-RSS доступен
curl -I http://localhost:8080

# 2. MCP healthcheck работает
curl http://localhost:8000/health

# 3. Scheduler пишет логи

docker logs -f ttrss-scheduler

# 4. Таблицы созданы

docker exec -it clickhouse clickhouse-client --database ttrss --query "SHOW TABLES"

# 5. Статьи записаны

docker exec -it clickhouse clickhouse-client --database ttrss --query "SELECT count() FROM articles FINAL"

# 6. Последние статьи читаются

docker exec -it clickhouse clickhouse-client --database ttrss --query "
SELECT published_at, feed_title, topic_label, title
FROM articles FINAL
ORDER BY published_at DESC
LIMIT 10
"
```

---

## 27. Репозиторий

```text
https://github.com/AlexeyPetrov1/news-ai-aggregator
```

---

## 28. Что считать источником истины

Для текущей версии проекта:

1. **Ingestion**: `scheduler`.
2. **Storage**: ClickHouse, база `ttrss`.
3. **Проверка данных**: SQL-запросы к ClickHouse.
4. **Dashboard**: Shiny, но не источник истины по состоянию ClickHouse.
5. **Agent interface**: MCP, читает готовые данные из ClickHouse.
6. **Manual R scripts**: только для отладки и разработки.
