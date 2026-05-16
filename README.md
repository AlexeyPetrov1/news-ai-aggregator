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
 
Все сервисы запускаются из единого `docker-compose.yml` в корне репозитория.
 
| Сервис | Назначение | 
|---|---|
| `ttrss-db` | PostgreSQL для TT-RSS |
| `ttrss` | TT-RSS web UI и API |
| `ttrss-init` | one-shot: включает API-доступ для admin |
| `clickhouse` | аналитическое хранилище | 
| `scheduler` | периодический запуск `fetch_news.R`; основной ingestion path | 
| `shiny` | UI-дашборд (вкладки: Обзор, Новости, Источники, Настройки) |
| `mcp` | JSON-RPC endpoint с MCP-инструментами | 

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
 
### TT-RSS: порты и URL

| Где обращаемся | URL | Пояснение |
|---|---|---|
| Браузер на вашем компьютере | `http://localhost:8080` | Порт **8080** на хосте проброшен в контейнер `ttrss` (внутри контейнера веб-сервер слушает **80**) |
| R-скрипты внутри Docker Compose | `http://ttrss/` | Имя сервиса в сети compose; **без** `:8080` — в `docker-compose.yml` уже задано так для `scheduler` и `shiny` |
| R-скрипты на хосте (вне Docker) | `http://localhost:8080` | Когда TT-RSS запущен через compose, а R — локально |

Переменная `TTRSS_PORT` в `.env` меняет только внешний порт на хосте (по умолчанию `8080`). Внутри Docker-сети TT-RSS всегда доступен по порту **80**.

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
| ML / NLP | `lda`, `kmeans`, `yandex_llm`, `llm` |
| LLM-классификация | Yandex GPT; универсальный `llm` (OpenAI-совместимые, Anthropic, Gemini, Ollama через `ellmer`) |
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
│   ├── labels.R                      # управление метками TT-RSS (R API, не вкладка Shiny)
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
├── docker/
│   └── shiny-server.conf              # конфигурация Shiny Server
│ 
├── docker-compose.yml                  # весь стек: TT-RSS + PostgreSQL + ClickHouse + Shiny + MCP + scheduler
├── .env.example                        # шаблон переменных окружения
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

Для TT-RSS в Docker Compose в `docker-compose.yml` уже задано `TTRSS_URL=http://ttrss/` (порт **80** внутри сети). Менять на `http://ttrss:8080` не нужно — с хоста TT-RSS открывается как `http://localhost:8080`, это другой контекст.

Для ручного запуска R на хосте используйте `TTRSS_URL=http://localhost:8080`, `TTRSS_USER`, `TTRSS_PASSWORD`. Учётные данные совпадают с `TTRSS_ADMIN_USER` / `TTRSS_ADMIN_PASSWORD`, если вы их не меняли.
 
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

### Шаг 1 — Установить Docker Desktop

Скачать с официального сайта: https://www.docker.com/products/docker-desktop/

- **Windows**: скачать `.exe`, установить, перезагрузить компьютер. После запуска Docker Desktop в трее появится иконка кита.
- **macOS**: скачать `.dmg`, перетащить в Applications, запустить.
- **Linux**: установить Docker Engine + Docker Compose v2 по инструкции для вашего дистрибутива.

> Убедитесь, что Docker запущен — иконка в трее активна, а команда `docker ps` выполняется без ошибок.

---

### Шаг 2 — Создать папку для проекта

**Linux / macOS:**
```bash
mkdir news-ai-aggregator
cd news-ai-aggregator
```

**Windows (PowerShell):**
```powershell
mkdir news-ai-aggregator
cd news-ai-aggregator
```

---

### Шаг 3 — Скачать docker-compose.yml

**Linux / macOS:**
```bash
curl -O https://raw.githubusercontent.com/AlexeyPetrov1/news-ai-aggregator/main/docker-compose.yml
```

**Windows (PowerShell):**
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/AlexeyPetrov1/news-ai-aggregator/main/docker-compose.yml" -OutFile "docker-compose.yml"
```

Это единственный файл, который нужен. Репозиторий клонировать не нужно.

---

### Шаг 4 — Запустить проект

```bash
docker compose up -d
```

Эта команда:
1. Скачает все образы с `ghcr.io` и Docker Hub (первый раз ~5-10 минут в зависимости от интернета)
2. Создаст и запустит 6 контейнеров
3. Вернёт управление в терминал (`-d` = detached, фоновый режим)

---

### Шаг 5 — Проверить, что всё запустилось

```bash
docker compose ps
```

Ожидаемый результат:

```
NAME              STATUS
clickhouse        Up (healthy)
ttrss             Up (healthy)
ttrss-db          Up (healthy)
ttrss-init        Exited (0)      ← это нормально, one-shot задача
ttrss-mcp         Up
ttrss-scheduler   Up
ttrss-shiny       Up
```

Если какой-то контейнер не поднялся — смотреть логи:
```bash
docker logs ttrss-scheduler
```

---

### Шаг 6 — Открыть интерфейсы

| Что | Адрес | Логин / пароль |
|-----|-------|----------------|
| TT-RSS (новостной ридер) | http://localhost:8080 | admin / password |
| Shiny дашборд | http://localhost:3838/ttrss | — |
| MCP healthcheck | http://localhost:8000/health | — |

---

### Шаг 7 — Дождаться первых данных

Scheduler автоматически:
1. Добавит RSS-ленты по кибербезопасности (~30 источников)
2. Скачает статьи из TT-RSS
3. Классифицирует их по темам (метод LDA по умолчанию)
4. Запишет в ClickHouse

Следить за процессом:
```bash
docker logs -f ttrss-scheduler
```

Первые данные появятся через **5-10 минут**. Затем scheduler обновляет данные каждый час.

Проверить что данные записались:
```bash
docker exec -it clickhouse clickhouse-client --database ttrss --query "SELECT count() FROM articles FINAL"
```

Если число больше 0 — всё работает.

---

### Шаг 8 — Остановка и повторный запуск

```bash
# Остановить (данные сохраняются)
docker compose down

# Запустить снова
docker compose up -d

# Остановить и удалить все данные (полный сброс)
docker compose down -v
```

---

### Шаг 9 — Если нужно изменить настройки

Скачать шаблон конфига:

**Linux / macOS:**
```bash
curl -O https://raw.githubusercontent.com/AlexeyPetrov1/news-ai-aggregator/main/.env.example
cp .env.example .env
```

**Windows (PowerShell):**
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/AlexeyPetrov1/news-ai-aggregator/main/.env.example" -OutFile ".env.example"
Copy-Item .env.example .env
```

Открыть `.env` в любом редакторе и изменить нужные параметры. Затем перезапустить:
```bash
docker compose up -d
```

Основные параметры в `.env`:

| Параметр | По умолчанию | Что делает |
|----------|-------------|------------|
| `TTRSS_PORT` | `8080` | Порт TT-RSS в браузере |
| `TTRSS_ADMIN_PASSWORD` | `password` | Пароль от TT-RSS |
| `SCHEDULER_INTERVAL_SECONDS` | `3600` | Как часто собирать новости (секунды) |
| `CLASSIFY_METHOD` | `lda` | Метод классификации тем |
| `MAX_ARTICLES` | `500` | Сколько статей обрабатывать за цикл |

Полная документация по каждой переменной — в **[разделе 9.4](#94-подробная-инструкция-по-созданию-env)**.

---

### Типовые проблемы

**Порт уже занят** — если `8080` или другой порт занят, создайте `.env` и измените:
```env
TTRSS_PORT=8181
```

**Дашборд показывает пустой экран** — данные ещё не загрузились, подождите 10 минут и проверьте логи scheduler.

**`docker compose` не найден** — убедитесь что установлен Docker Desktop (не просто Docker Engine), или обновите до версии с встроенным Compose v2.

---

### 9.4. Подробная инструкция по созданию `.env`

#### Шаг 1. Создать `.env` из шаблона

```bash
cp .env.example .env
```

(Windows: `Copy-Item .env.example .env`)

Файл `.env.example` в репозитории содержит минимальный набор для `docker compose up` с методом `lda`. Секреты (API keys) добавляйте только в `.env`, не в `.env.example`.

---

#### Шаг 2. TT-RSS

```env
# URL TT-RSS API (для R-скриптов на хосте, когда compose уже запущен)
TTRSS_URL=http://localhost:8080

# Учётные данные пользователя TT-RSS (R-скрипты, scheduler, shiny)
TTRSS_USER=admin
TTRSS_PASSWORD=password

# Учётные данные администратора (конфигурация сервиса)
TTRSS_ADMIN_USER=admin
TTRSS_ADMIN_PASSWORD=password
```

> **Внутри Docker Compose** `scheduler` и `shiny` получают `TTRSS_URL=http://ttrss/` из `docker-compose.yml` (порт **80** в сети контейнеров). В `.env` для compose **не** указывайте `http://ttrss:8080` — этот адрес сработает только с вашего компьютера, не из контейнера.

Если при первом входе в TT-RSS вы изменили пароль администратора — укажите актуальные значения в `TTRSS_USER` / `TTRSS_PASSWORD` (и при необходимости в `TTRSS_ADMIN_*`).

---

#### Шаг 3. ClickHouse

```env
# Хост ClickHouse
# При запуске через Docker Compose: CH_HOST=clickhouse (имя сервиса в compose-сети)
# При ручном локальном запуске R-скриптов: CH_HOST=localhost
CH_HOST=clickhouse

# Порт нативного протокола ClickHouse (используется R-клиентом)
CH_PORT=9000

# Порт HTTP-интерфейса ClickHouse (используется для healthcheck)
CH_HTTP_PORT=8123

# База данных
CH_DB=ttrss

# Пользователь и пароль (по умолчанию пароль пустой)
CH_USER=default
CH_PASSWORD=
```

---

#### Шаг 4. Параметры сбора данных

```env
# Максимальное количество статей, которое пайплайн обрабатывает за один цикл
MAX_ARTICLES=500

# Интервал между циклами сбора в секундах
# 3600 = 1 час, 300 = 5 минут
SCHEDULER_INTERVAL_SECONDS=3600
```

---

#### Шаг 5. Метод классификации

Поддерживаются четыре метода. Выберите один в зависимости от ваших потребностей:

**Вариант A — `lda` (по умолчанию, не требует внешних сервисов):**

```env
CLASSIFY_METHOD=lda
N_TOPICS=8
```

**Вариант B — `kmeans` (baseline-кластеризация, не требует внешних сервисов):**

```env
CLASSIFY_METHOD=kmeans
N_TOPICS=8
```

**Вариант C — `yandex_llm` (LLM-классификация, требует Yandex Cloud API key):**

```env
CLASSIFY_METHOD=yandex_llm
N_TOPICS=8

# Секрет API key сервисного аккаунта или AI Studio API key
# Важно: это именно секрет ключа, а не его ID
YANDEX_CLOUD_API_KEY=<ваш-api-key>

# ID каталога в Yandex Cloud, в котором доступна модель
YANDEX_CLOUD_FOLDER=<folder_id>

# Модель
YANDEX_CLOUD_MODEL=yandexgpt-5-lite/latest

# Базовый URL API
YANDEX_CLOUD_BASE_URL=https://ai.api.cloud.yandex.net/v1

# Путь к файлу кеша ответов модели (экономит запросы при повторных текстах)
YANDEX_CACHE_PATH=data/yandex_llm_cache.rds
```

Как получить Yandex Cloud credentials:

1. Войдите в консоль Yandex Cloud.
2. Выберите нужный каталог — его ID будет в адресной строке и в разделе «Обзор каталога». Это `YANDEX_CLOUD_FOLDER`.
3. Перейдите в **IAM → Сервисные аккаунты**, создайте сервисный аккаунт и назначьте ему роль `ai.languageModels.user`.
4. В настройках сервисного аккаунта создайте **API-ключ** и скопируйте **Секрет** — это `YANDEX_CLOUD_API_KEY`.

**Вариант D — `llm` (универсальная LLM-классификация через `ellmer`):**

Подходит для OpenAI, OpenAI-совместимых API (DeepSeek, Groq и др.), Anthropic Claude, Google Gemini и локального Ollama. Требуется API key (кроме Ollama).

```env
CLASSIFY_METHOD=llm
N_TOPICS=8

# Провайдер: openai | anthropic | gemini | ollama
LLM_PROVIDER=openai

# API key (для ollama можно оставить пустым)
LLM_API_KEY=<ваш-api-key>

# Модель (примеры: gpt-4o-mini, deepseek-chat, claude-3-5-haiku-latest, gemini-2.0-flash)
LLM_MODEL=gpt-4o-mini

# Base URL: пусто = OpenAI; DeepSeek: https://api.deepseek.com; Ollama: http://host.docker.internal:11434
LLM_BASE_URL=
```

В Shiny те же параметры задаются на вкладке **Настройки** (метод «LLM (любой провайдер)»). Для `scheduler` в Docker добавьте переменные в `.env`, если классификация должна идти через `llm` в автоматическом цикле (по умолчанию в compose — `lda`).

---

#### Шаг 6. Параметры поведения scheduler (опционально)

Эти переменные управляют инициализацией RSS-фидов при старте контейнера. Значения по умолчанию подходят для большинства случаев.

```env
# Запускать инициализацию фидов при старте контейнера
INIT_FEEDS_ON_START=true

# Максимальное количество попыток инициализации фидов
INIT_FEEDS_RETRY_MAX=5

# Задержка между попытками инициализации в секундах
INIT_FEEDS_RETRY_DELAY_SECONDS=30

# Продолжать работу scheduler, если инициализация фидов не удалась
CONTINUE_ON_FEEDS_INIT_ERROR=true

# Повторять добавление фидов в каждом цикле (не нужно в обычном режиме)
RUN_ADD_FEEDS_EACH_CYCLE=false
```

---

#### Итоговый минимальный `.env`

Содержимое совпадает с **`.env.example`** в корне репозитория. После `cp .env.example .env` дополнительно править файл не обязательно для первого запуска с `lda`.

> Файл **`.env`** содержит локальные секреты и не коммитится (см. `.gitignore`). Шаблон **`.env.example`** в git можно менять только без реальных ключей.

---

## 10. Запуск Docker-образа
 
Убедитесь, что **Docker Desktop** установлен и запущен, затем:
 
```bash 
docker compose up -d
``` 

Эта команда запускает весь стек: TT-RSS, PostgreSQL, ClickHouse, scheduler, Shiny и MCP. Образы подтянутся с `ghcr.io` автоматически.

### Проверка контейнеров
 
```bash
docker compose ps
```
 
Ожидаемо — 7 контейнеров (6 сервисов + one-shot `ttrss-init`):

```text 
ttrss-db          Up (healthy)
ttrss             Up (healthy)
ttrss-init        Exited (0)   ← API включён автоматически
clickhouse        Up (healthy)
ttrss-shiny       Up
ttrss-mcp         Up
ttrss-scheduler   Up
```

### Первый запуск TT-RSS

Откройте `http://localhost:8080` и войдите под admin-пользователем.

Если в `.env` не меняли учётные данные:

```text 
admin / password 
``` 
 
**API-доступ включается автоматически** сервисом `ttrss-init`. Ручное включение через UI не требуется.
 
### Остановка и пересборка
 
```bash<!-- cb-k-1 -->
# остановить без удаления данных
docker compose down

# пересобрать после изменений кода
docker compose up -d
```


---<!-- cb-k-2 -->

## 11. Добавление RSS-фидов<!-- cb-k-3 -->
### Данный этап необходим только в случае, если за 5 минут у вас не подтянулись новости<!-- cb-k-4 -->

Если фиды еще не добавлены, можно выполнить соответствующий script.<!-- cb-k-5 -->

Локально, при настроенном R-окружении:<!-- cb-k-6 -->

```r<!-- cb-k-7 -->
source("data-raw/add_security_feeds.R")<!-- cb-k-8 -->
```<!-- cb-k-9 -->

Или внутри контейнера, если в нем доступны исходники проекта и R-зависимости:<!-- cb-k-10 -->

```bash<!-- cb-k-11 -->
docker exec -it ttrss-scheduler Rscript data-raw/add_security_feeds.R<!-- cb-k-12 -->
```<!-- cb-k-13 -->

Если появляется `API_DISABLED`, сначала включите TT-RSS API.<!-- cb-k-14 -->

---<!-- cb-k-15 -->

## 12. Scheduler-first workflow<!-- cb-k-16 -->

`scheduler` — основной способ регулярного обновления данных.<!-- cb-k-17 -->

Запуск только scheduler:<!-- cb-k-18 -->

```bash<!-- cb-k-19 -->
docker compose up -d --build scheduler<!-- cb-k-20 -->
```<!-- cb-k-21 -->

Логи:<!-- cb-k-22 -->

```bash<!-- cb-k-23 -->
docker logs -f ttrss-scheduler<!-- cb-k-24 -->
```<!-- cb-k-25 -->

Ожидаемое поведение:<!-- cb-k-26 -->

- повторяющиеся циклы `fetch_news`;<!-- cb-k-27 -->
- отсутствие fatal errors;<!-- cb-k-28 -->
- создание таблиц в ClickHouse;<!-- cb-k-29 -->
- рост количества строк в `articles` при появлении новых статей.<!-- cb-k-30 -->

Проверить, что scheduler жив:<!-- cb-k-31 -->

```bash<!-- cb-k-32 -->
docker compose ps<!-- cb-k-33 -->
```<!-- cb-k-34 -->

---<!-- cb-k-35 -->

## 13. Проверка ClickHouse<!-- cb-k-36 -->

Показать базы:<!-- cb-k-37 -->

```bash<!-- cb-k-38 -->
docker exec -it clickhouse clickhouse-client --query "SHOW DATABASES"<!-- cb-k-39 -->
```<!-- cb-k-40 -->

Показать таблицы в базе `ttrss`:<!-- cb-k-41 -->

```bash<!-- cb-k-42 -->
docker exec -it clickhouse clickhouse-client --database ttrss --query "SHOW TABLES"<!-- cb-k-43 -->
```<!-- cb-k-44 -->

Ожидаемые таблицы:<!-- cb-k-45 -->

```text<!-- cb-k-46 -->
articles<!-- cb-k-47 -->
feeds<!-- cb-k-48 -->
topic_summary<!-- cb-k-49 -->
```<!-- cb-k-50 -->

Проверить количество статей:<!-- cb-k-51 -->

```bash<!-- cb-k-52 -->
docker exec -it clickhouse clickhouse-client --database ttrss --query "SELECT count() FROM articles FINAL"<!-- cb-k-53 -->
```<!-- cb-k-54 -->

Ожидаемо:<!-- cb-k-55 -->

```text<!-- cb-k-56 -->
count() > 0<!-- cb-k-57 -->
```<!-- cb-k-58 -->

Посмотреть последние статьи:<!-- cb-k-59 -->

```bash<!-- cb-k-60 -->
docker exec -it clickhouse clickhouse-client --database ttrss --query "<!-- cb-k-61 -->
SELECT published_at, feed_title, topic_label, title<!-- cb-k-62 -->
FROM articles FINAL<!-- cb-k-63 -->
ORDER BY published_at DESC<!-- cb-k-64 -->
LIMIT 10<!-- cb-k-65 -->
"<!-- cb-k-66 -->
```<!-- cb-k-67 -->

Проверить распределение тем:<!-- cb-k-68 -->

```bash<!-- cb-k-69 -->
docker exec -it clickhouse clickhouse-client --database ttrss --query "<!-- cb-k-70 -->
SELECT topic_label, count() AS n<!-- cb-k-71 -->
FROM articles FINAL<!-- cb-k-72 -->
GROUP BY topic_label<!-- cb-k-73 -->
ORDER BY n DESC<!-- cb-k-74 -->
"<!-- cb-k-75 -->
```<!-- cb-k-76 -->

Проверить свежесть данных:<!-- cb-k-77 -->

```bash<!-- cb-k-78 -->
docker exec -it clickhouse clickhouse-client --database ttrss --query "<!-- cb-k-79 -->
SELECT<!-- cb-k-80 -->
    min(published_at) AS first_article,<!-- cb-k-81 -->
    max(published_at) AS last_article,<!-- cb-k-82 -->
    max(fetched_at) AS last_fetch<!-- cb-k-83 -->
FROM articles FINAL<!-- cb-k-84 -->
"<!-- cb-k-85 -->
```<!-- cb-k-86 -->

Важно: для SQL-запросов указывайте `--database ttrss`. Без этого `clickhouse-client` может использовать базу `default`, и запрос к `articles` завершится ошибкой.<!-- cb-k-87 -->

---<!-- cb-k-88 -->

## 14. Контроль качества данных<!-- cb-k-89 -->

Проверить критичные пустые поля:<!-- cb-k-90 -->

```bash<!-- cb-k-91 -->
docker exec -it clickhouse clickhouse-client --database ttrss --query "<!-- cb-k-92 -->
SELECT<!-- cb-k-93 -->
    count() AS total,<!-- cb-k-94 -->
    countIf(article_id = 0) AS bad_article_id,<!-- cb-k-95 -->
    countIf(title = '') AS empty_title,<!-- cb-k-96 -->
    countIf(content_text = '') AS empty_content_text,<!-- cb-k-97 -->
    countIf(feed_id = 0) AS empty_feed_id,<!-- cb-k-98 -->
    countIf(topic_label = '') AS empty_topic_label<!-- cb-k-99 -->
FROM articles FINAL<!-- cb-k-100 -->
"<!-- cb-k-101 -->
```<!-- cb-k-102 -->

Интерпретация:<!-- cb-k-103 -->

- `bad_article_id > 0` — проблема с идентификаторами;<!-- cb-k-104 -->
- `empty_title > 0` — часть новостей пришла без заголовков;<!-- cb-k-105 -->
- `empty_content_text > 0` — возможно, RSS содержит только title/summary;<!-- cb-k-106 -->
- `empty_topic_label > 0` — проблема на этапе классификации или fallback-логики.<!-- cb-k-107 -->

---<!-- cb-k-108 -->

## 15. Shiny dashboard<!-- cb-k-109 -->

Запуск полного стека:<!-- cb-k-110 -->

```bash<!-- cb-k-111 -->
docker compose up -d<!-- cb-k-112 -->
```<!-- cb-k-113 -->

Открыть dashboard:<!-- cb-k-114 -->

```text<!-- cb-k-115 -->
http://localhost:3838/ttrss<!-- cb-k-116 -->
```<!-- cb-k-117 -->

Важное ограничение: Shiny может показывать локальный cache/RDS-файл, даже если ClickHouse пуст. Поэтому состояние пайплайна нужно валидировать через ClickHouse:<!-- cb-k-118 -->

```bash<!-- cb-k-119 -->
docker exec -it clickhouse clickhouse-client --database ttrss --query "SELECT count() FROM articles FINAL"<!-- cb-k-120 -->
```<!-- cb-k-121 -->

Если dashboard показывает данные, а `articles` пустой — это не доказательство успешной записи в ClickHouse.<!-- cb-k-122 -->

---<!-- cb-k-123 -->

## 16. MCP-интеграция<!-- cb-k-124 -->

MCP endpoint:<!-- cb-k-125 -->

```text<!-- cb-k-126 -->
http://localhost:8000/mcp<!-- cb-k-127 -->
```<!-- cb-k-128 -->

Healthcheck:<!-- cb-k-129 -->

```bash<!-- cb-k-130 -->
curl http://localhost:8000/health<!-- cb-k-131 -->
```<!-- cb-k-132 -->

Список инструментов:<!-- cb-k-133 -->

```bash<!-- cb-k-134 -->
curl -X POST http://localhost:8000/mcp \<!-- cb-k-135 -->
  -H "Content-Type: application/json" \<!-- cb-k-136 -->
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'<!-- cb-k-137 -->
```<!-- cb-k-138 -->

Роль MCP:<!-- cb-k-139 -->

- MCP не выполняет ML-инференс;<!-- cb-k-140 -->
- MCP не классифицирует новые статьи;<!-- cb-k-141 -->
- MCP читает уже подготовленные данные и агрегаты из ClickHouse;<!-- cb-k-142 -->
- MCP нужен как интерфейс для AI-агентов и внешних клиентов.<!-- cb-k-143 -->

Доступные инструменты:<!-- cb-k-144 -->

| Tool | Назначение |<!-- cb-k-145 -->
|---|---|<!-- cb-k-146 -->
| `search_articles` | поиск статей |<!-- cb-k-147 -->
| `get_topic_summary` | агрегаты по темам |<!-- cb-k-148 -->
| `get_recent_articles` | последние статьи |<!-- cb-k-149 -->
| `get_feed_stats` | статистика по источникам |<!-- cb-k-150 -->

Доступные ресурсы:<!-- cb-k-151 -->

```text<!-- cb-k-152 -->
ttrss://articles<!-- cb-k-153 -->
ttrss://topics<!-- cb-k-154 -->
```<!-- cb-k-155 -->

### 16.1. Проверка последних статей через MCP<!-- cb-k-156 -->

Bash/cURL:<!-- cb-k-157 -->

```bash<!-- cb-k-158 -->
curl -X POST http://localhost:8000/mcp \<!-- cb-k-159 -->
  -H "Content-Type: application/json" \<!-- cb-k-160 -->
  -d '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_recent_articles","arguments":{"limit":5}}}'<!-- cb-k-161 -->
```<!-- cb-k-162 -->

PowerShell:<!-- cb-k-163 -->

```powershell<!-- cb-k-164 -->
$r = Invoke-RestMethod -Method POST `<!-- cb-k-165 -->
  -Uri "http://localhost:8000/mcp" `<!-- cb-k-166 -->
  -ContentType "application/json" `<!-- cb-k-167 -->
  -Body '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_recent_articles","arguments":{"limit":5}}}'<!-- cb-k-168 -->

$r.result.content[0].text | ConvertFrom-Json | Format-Table<!-- cb-k-169 -->
```<!-- cb-k-170 -->

### 16.2. Проверка источников через MCP<!-- cb-k-171 -->

```powershell<!-- cb-k-172 -->
$r = Invoke-RestMethod -Method POST `<!-- cb-k-173 -->
  -Uri "http://localhost:8000/mcp" `<!-- cb-k-174 -->
  -ContentType "application/json" `<!-- cb-k-175 -->
  -Body '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_feed_stats","arguments":{}}}'<!-- cb-k-176 -->

$r.result.content[0].text | ConvertFrom-Json | Format-Table<!-- cb-k-177 -->
```<!-- cb-k-178 -->

PowerShell может отображать вложенные поля как `System.Object[]`. Для раскрытия JSON используйте:<!-- cb-k-179 -->

```powershell<!-- cb-k-180 -->
$r | ConvertTo-Json -Depth 20<!-- cb-k-181 -->
```<!-- cb-k-182 -->

---<!-- cb-k-183 -->

## 17. Manual one-time run<!-- cb-k-184 -->

Ручной запуск не является основным production-flow. Он полезен для отладки.<!-- cb-k-185 -->

Локально:<!-- cb-k-186 -->

```r<!-- cb-k-187 -->
source("data-raw/fetch_news.R")<!-- cb-k-188 -->
```<!-- cb-k-189 -->

Через Rscript:<!-- cb-k-190 -->

```bash<!-- cb-k-191 -->
Rscript data-raw/fetch_news.R<!-- cb-k-192 -->
```<!-- cb-k-193 -->

Перед ручным запуском проверьте переменные окружения. Для локального запуска чаще нужен `CH_HOST=localhost`, а не `CH_HOST=clickhouse`.<!-- cb-k-194 -->

---<!-- cb-k-195 -->

## 18. Reset and re-validate<!-- cb-k-196 -->

Используйте этот сценарий, когда нужно проверить восстановление с нуля после удаления ClickHouse volume.<!-- cb-k-197 -->

```bash<!-- cb-k-198 -->
# Остановить все сервисы и удалить volumes

docker compose down -v --remove-orphans<!-- cb-k-199 -->

# Запустить scheduler заново<!-- cb-k-200 -->

docker compose up -d --build scheduler<!-- cb-k-201 -->
```<!-- cb-k-202 -->

После этого повторить проверки:<!-- cb-k-203 -->

```bash<!-- cb-k-204 -->
docker logs -f ttrss-scheduler<!-- cb-k-205 -->
```<!-- cb-k-206 -->

```bash<!-- cb-k-207 -->
docker exec -it clickhouse clickhouse-client --database ttrss --query "SHOW TABLES"<!-- cb-k-208 -->
```<!-- cb-k-209 -->

```bash<!-- cb-k-210 -->
docker exec -it clickhouse clickhouse-client --database ttrss --query "SELECT count() FROM articles FINAL"<!-- cb-k-211 -->
```<!-- cb-k-212 -->

Важно: `docker compose down -v` сбрасывает все volumes. Если нужно сбросить только analytics и сохранить данные TT-RSS, используйте `docker compose down -v clickhouse shiny scheduler mcp`.

---<!-- cb-k-213 -->

## 19. ML-этап<!-- cb-k-214 -->

Поддерживаемые методы классификации:<!-- cb-k-215 -->

| Method | Описание |<!-- cb-k-216 -->
|---|---|<!-- cb-k-217 -->
| `lda` | тематическое моделирование через `topicmodels::LDA` |<!-- cb-k-218 -->
| `kmeans` | baseline-кластеризация по TF-IDF |<!-- cb-k-219 -->
| `yandex_llm` | closed-set классификация через Yandex GPT |<!-- cb-k-220 -->
| `llm` | closed-set классификация через выбранного LLM-провайдера (`ellmer`) |

`yandex_llm` и `llm` удобны, если нужны понятные названия тем из фиксированной таксономии.

`lda` и `kmeans` полезны как baseline и как способ быстро проверить структуру корпуса без внешних API.

### 19.1. Ненадзорные метрики качества<!-- cb-k-221 -->

`evaluate_topic_quality()` возвращает:

- `label_coverage`;
- `dominant_topic_share`;
- `topic_balance_entropy`;
- `topic_distinctiveness`;
- `per_topic` распределение.<!-- cb-k-222 -->

Пример:

```r
df <- classify_news(df, method = "lda", compute_quality = TRUE)
attr(df, "topic_quality")
```

### 19.2. Бенчмарк методов<!-- cb-k-223 -->

```r
source("data-raw/compare_methods.R")
```

Артефакты сравнения:<!-- cb-k-224 -->

```text<!-- cb-k-225 -->
data/method_comparison.csv<!-- cb-k-226 -->
data/method_comparison.rds<!-- cb-k-227 -->
```<!-- cb-k-228 -->

### 19.3. Optional mini ground-truth<!-- cb-k-229 -->

`mini_ground_truth_workflow.R` остается опциональным validation workflow. Это не основной публичный контур оценки модели.<!-- cb-k-230 -->

---<!-- cb-k-231 -->

## 20. Артефакты проекта<!-- cb-k-232 -->

Основные runtime-артефакты:<!-- cb-k-233 -->

| Артефакт | Где находится | Когда появляется |<!-- cb-k-234 -->
|---|---|---|<!-- cb-k-235 -->
| `articles` | ClickHouse, база `ttrss` | после успешного `fetch_news.R` |<!-- cb-k-236 -->
| `feeds` | ClickHouse, база `ttrss` | после инициализации схемы / записи данных |<!-- cb-k-237 -->
| `topic_summary` | ClickHouse, база `ttrss` | после агрегации тем |<!-- cb-k-238 -->
| `data/yandex_llm_cache.rds` | filesystem | после классификации через `yandex_llm` |<!-- cb-k-239 -->
| `data/method_comparison.csv` | filesystem | после `compare_methods.R` |<!-- cb-k-240 -->
| `data/method_comparison.rds` | filesystem | после `compare_methods.R` |<!-- cb-k-241 -->
| `data/news_raw.rds` | filesystem / Shiny data dir | legacy/local cache для dashboard |<!-- cb-k-242 -->

Операционные endpoints:<!-- cb-k-243 -->

| Endpoint | Назначение |<!-- cb-k-244 -->
|---|---|<!-- cb-k-245 -->
| `http://localhost:8080` | TT-RSS UI |<!-- cb-k-246 -->
| `http://localhost:8080/api/` | TT-RSS JSON API |<!-- cb-k-247 -->
| `http://localhost:3838/ttrss` | Shiny dashboard |<!-- cb-k-248 -->
| `http://localhost:8000/mcp` | MCP JSON-RPC endpoint |<!-- cb-k-249 -->
| `http://localhost:8000/health` | MCP healthcheck |<!-- cb-k-250 -->
| `http://localhost:8123` | ClickHouse HTTP |<!-- cb-k-251 -->

---<!-- cb-k-252 -->

## 21. Типовые проблемы и диагностика<!-- cb-k-253 -->

### 21.1. `API_DISABLED`<!-- cb-k-254 -->

Причина: в TT-RSS не включен API-доступ.<!-- cb-k-255 -->

Что сделать:<!-- cb-k-256 -->

1. Открыть `http://localhost:8080`.<!-- cb-k-257 -->
2. Войти под admin-пользователем.<!-- cb-k-258 -->
3. Включить `API access` / `external API` в настройках.<!-- cb-k-259 -->
4. Повторить запуск scheduler.<!-- cb-k-260 -->

Проверка:<!-- cb-k-261 -->

```bash<!-- cb-k-262 -->
curl -X POST http://localhost:8080/api/ \<!-- cb-k-263 -->
  -H "Content-Type: application/json" \<!-- cb-k-264 -->
  -d '{"op":"login","user":"admin","password":"password"}'<!-- cb-k-265 -->
```<!-- cb-k-266 -->

---<!-- cb-k-267 -->

### 21.2. `articles` table missing<!-- cb-k-268 -->

Возможные причины:<!-- cb-k-269 -->

- scheduler не стартовал;<!-- cb-k-270 -->
- ClickHouse не готов;<!-- cb-k-271 -->
- `fetch_news.R` упал до `ch_init_schema`;<!-- cb-k-272 -->
- неверные переменные окружения ClickHouse.<!-- cb-k-273 -->

Проверки:<!-- cb-k-274 -->

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
docker compose up -d
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
Данные собираются из TT-RSS, нормализуются, классифицируются методами lda / kmeans / yandex_llm / llm,
сохраняются в ClickHouse и доступны через Shiny dashboard и MCP JSON-RPC endpoint (методы: `lda`, `kmeans`, `yandex_llm`, `llm`).
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
