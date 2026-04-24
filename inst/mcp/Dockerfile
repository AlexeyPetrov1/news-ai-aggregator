## ============================================================
## Dockerfile — ttrssR MCP Server (plumber + JSON-RPC 2.0)
## Контекст сборки: корень пакета (docker-compose передаёт context: .)
## ============================================================

FROM rocker/r-ver:4.5.0

LABEL maintainer="ttrssR project"
LABEL description="MCP Server for TT-RSS Analytics"

RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libpq-dev \
    libsodium-dev \
    zlib1g-dev \
    cmake \
    && rm -rf /var/lib/apt/lists/*

ARG CACHE_BUST=4
RUN Rscript -e "\
  install.packages(c( \
    'plumber','jsonlite','DBI','RClickhouse', \
    'dplyr','cli','rlang' \
  ), repos='https://cloud.r-project.org', Ncpus=4)"

# Копируем только нужные R-исходники (db.R sourced напрямую)
COPY R/db.R /pkg/ttrssR/R/db.R
COPY inst/mcp/server.R /app/server.R

WORKDIR /app

EXPOSE 8000

CMD ["Rscript", "-e", \
     "pr <- plumber::plumb('server.R'); plumber::pr_run(pr, host='0.0.0.0', port=8000)"]
