# ttrssR: Cybersecurity News ML Pipeline

`ttrssR` is an R package and service stack for end-to-end cybersecurity news analytics:

RSS ingestion -> normalization -> topic classification -> ClickHouse storage -> Shiny dashboard -> MCP tools for AI agents.

## Project Scope

- Domain: threat intelligence, incident news, vulnerability updates, malware and phishing monitoring.
- Data source: TT-RSS via JSON API.
- Storage: ClickHouse (analytical queries and summaries).
- ML: `lda`, `kmeans`, `llm`, `yandex_llm` + quality evaluation.
- Delivery: Shiny dashboard and MCP server (`stdio` + `HTTP` variants).

## High-Level Architecture

1. TT-RSS aggregates RSS feeds.
2. `ttrssR` fetches and normalizes full article content.
3. Articles are classified by one of supported ML backends.
4. Results are persisted in ClickHouse.
5. Users and agents consume data via Shiny and MCP.

## Tech Stack

| Layer | Technology |
|---|---|
| Core language | R (package-based architecture) |
| RSS ingestion | TT-RSS JSON API |
| ML / NLP | `topicmodels`, `tidytext`, optional LLM backends |
| DB | ClickHouse |
| Dashboard | Shiny + shinydashboard + plotly + DT |
| Agent interface | MCP (JSON-RPC 2.0) |
| Runtime | Docker Compose |

## Repository Structure

```text
news-ai-aggregator/
├── R/
│   ├── api.R                         # TT-RSS API client
│   ├── etl.R                         # data fetch + normalization
│   ├── classify.R                    # lda/kmeans/llm/yandex_llm + quality metrics
│   ├── ground_truth.R                # canonical mapping + supervised evaluation
│   ├── db.R                          # ClickHouse layer
│   └── app.R                         # run_dashboard() / run_mcp_server()
├── inst/
│   ├── shiny/                        # dashboard app
│   └── mcp/                          # MCP servers (stdio + HTTP)
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
├── docker-compose.yml                # analytics stack (ClickHouse + Shiny + MCP)
├── docker/ttrss/docker-compose.yml   # standalone TT-RSS stack
└── README.md
```

## Quick Start

### Prerequisites

- Docker Desktop
- R (4.5+ recommended)

### 1) Start TT-RSS

```bash
docker compose -f docker/ttrss/docker-compose.yml up -d
```

TT-RSS URL: `http://localhost:8080`

### 2) Start analytics stack

```bash
docker compose up -d --build
```

Services:

- Shiny: `http://localhost:3838/ttrss`
- MCP: `http://localhost:8000/mcp`
- ClickHouse HTTP: `http://localhost:8123`

### 3) Ingest + classify news

```r
source("data-raw/fetch_news.R")
```

### 4) Open dashboard

Open `http://localhost:3838/ttrss`.

## ML Stage: Current Status

### Supported methods

- `lda`: topic modeling (`topicmodels::LDA`).
- `kmeans`: TF-IDF clustering baseline.
- `llm`: generic LLM tagging backend.
- `yandex_llm`: Yandex Assistant API (`gpt://<folder>/<model>`).

### Yandex LLM reliability improvements

- retry with exponential backoff on `429/5xx`;
- session cache for repeated texts;
- persistent cache (`data/yandex_llm_cache.rds`) across runs;
- safe fallback to `"Без категории"` on request failures.

### Unsupervised quality metrics

`evaluate_topic_quality()` returns:

- `label_coverage`;
- `dominant_topic_share`;
- `topic_balance_entropy`;
- `topic_distinctiveness`;
- per-topic distribution (`per_topic`).

Example:

```r
df <- classify_news(df, method = "lda", compute_quality = TRUE)
attr(df, "topic_quality")
```

## Method Benchmarking

Run unified benchmark on one dataset:

```r
source("data-raw/compare_methods.R")
```

Outputs:

- `data/method_comparison.csv`
- `data/method_comparison.rds`

## Mini Ground-Truth + Canonical Mapping

This workflow gives presentation-grade supervised evidence (`accuracy`, `macro_f1`, confusion matrix).

Run:

```r
source("data-raw/mini_ground_truth_workflow.R")
```

### Workflow

1. Script creates `data/ground_truth_template.csv`.
2. Manually fill `topic_true`.
3. Save as `data/ground_truth_labeled.csv`.
4. Re-run script to compute metrics.

### Files

- Mapping template: `data-raw/canonical_topic_mapping_template.csv`
- Metrics summary: `data/ground_truth_metrics.csv`
- Full metrics report: `data/ground_truth_metrics.rds`

### Reusable functions

- `create_ground_truth_sample()`
- `apply_canonical_label_mapping()`
- `evaluate_against_ground_truth()`

## Environment Variables

Common:

- `TTRSS_URL`, `TTRSS_USER`, `TTRSS_PASSWORD`
- `CH_HOST`, `CH_PORT`, `CH_DB`, `CH_USER`, `CH_PASSWORD`
- `CLASSIFY_METHOD`, `N_TOPICS`, `MAX_ARTICLES`

Yandex LLM:

- `YANDEX_CLOUD_API_KEY`
- `YANDEX_CLOUD_FOLDER`
- `YANDEX_CLOUD_MODEL` (default `yandexgpt-lite/rc`)
- `YANDEX_CLOUD_BASE_URL` (default `https://rest-assistant.api.cloud.yandex.net/v1`)
- `YANDEX_CACHE_PATH` (optional cache file override)

## MCP Integration

The project provides:

- `inst/mcp/stdio_server.R` for local agent integration via stdin/stdout.
- `inst/mcp/server.R` for HTTP transport in Docker.

Current toolset includes:

- `search_articles`
- `get_topic_summary`
- `get_recent_articles`
- `get_feed_stats`

## Testing

Tests are organized in `tests/testthat`:

- API client coverage (`test-api.R`)
- ETL and normalization (`test-etl.R`)
- classification and quality logic (`test-classify.R`)
- ground-truth/canonical mapping evaluation (`test-ground-truth.R`)

Run tests (locally with R installed):

```r
testthat::test_dir("tests/testthat")
```

## Repository

https://github.com/AlexeyPetrov1/news-ai-aggregator
