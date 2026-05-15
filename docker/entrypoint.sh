#!/bin/sh
# Write container env vars to /home/shiny/.Renviron so Shiny worker
# processes (spawned via "su --login shiny") can read them.
env_file=/home/shiny/.Renviron
: > "$env_file"

for var in \
  TTRSS_URL TTRSS_USER TTRSS_PASSWORD \
  CH_HOST CH_PORT CH_DB CH_USER CH_PASSWORD \
  LLM_API_KEY CLASSIFY_METHOD N_TOPICS \
  YANDEX_CLOUD_API_KEY YANDEX_CLOUD_FOLDER \
  YANDEX_CLOUD_MODEL YANDEX_CLOUD_BASE_URL; do
  val=$(printenv "$var" 2>/dev/null)
  if [ -n "$val" ]; then
    echo "${var}=\"${val}\"" >> "$env_file"
  fi
done

chown shiny:shiny "$env_file"
exec /usr/bin/shiny-server "$@"
