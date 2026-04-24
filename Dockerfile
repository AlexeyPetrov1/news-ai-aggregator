## ============================================================
## Dockerfile — ttrssR Shiny Dashboard
## Образ: rocker/shiny (Shiny Server + R 4.5)
## Сборка: docker build -t ttrssr-shiny .
## ============================================================

FROM rocker/shiny:4.5.0

LABEL maintainer="ttrssR project"
LABEL description="ttrssR Shiny dashboard container"

# ── Системные зависимости ──────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libgsl-dev \
    libpq-dev \
    libsodium-dev \
    && rm -rf /var/lib/apt/lists/*

# ── R-пакеты (один слой для кэширования) ─────────────────────────────────
RUN Rscript -e "\
  pkgs <- c( \
    'httr2','jsonlite','dplyr','tidyr','stringr','lubridate', \
    'tidytext','topicmodels','stopwords','reshape2', \
    'DBI','RClickhouse', \
    'shiny','shinydashboard','ggplot2','plotly','wordcloud2','DT', \
    'plumber','glue','cli','rlang' \
  ); \
  install.packages(pkgs, repos='https://cloud.r-project.org', Ncpus=4)"

# ── Копируем пакет и устанавливаем ────────────────────────────────────────
COPY . /pkg/ttrssR/
RUN Rscript -e "install.packages('/pkg/ttrssR', repos=NULL, type='source')"

# ── Разворачиваем Shiny-приложение ────────────────────────────────────────
RUN mkdir -p /srv/shiny-server/ttrss/shiny
RUN cp -r /pkg/ttrssR/inst/shiny/. /srv/shiny-server/ttrss/shiny/

# ── Конфигурация Shiny Server ─────────────────────────────────────────────
COPY docker/shiny-server.conf /etc/shiny-server/shiny-server.conf

# ── Папка для данных (монтируется снаружи) ────────────────────────────────
RUN mkdir -p /srv/shiny-server/ttrss/shiny/data \
    && chown -R shiny:shiny /srv/shiny-server

EXPOSE 3838

CMD ["/usr/bin/shiny-server"]
