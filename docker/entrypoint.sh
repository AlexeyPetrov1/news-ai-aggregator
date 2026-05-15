#!/bin/sh  #cb-g-199
# Write container env vars to /home/shiny/.Renviron so Shiny worker  #cb-g-200
# processes (spawned via "su --login shiny") can read them.  #cb-g-201
env_file=/home/shiny/.Renviron  #cb-g-202
: > "$env_file"  #cb-g-203

for var in \  #cb-g-204
  TTRSS_URL TTRSS_USER TTRSS_PASSWORD \  #cb-g-205
  CH_HOST CH_PORT CH_DB CH_USER CH_PASSWORD \  #cb-g-206
  LLM_API_KEY CLASSIFY_METHOD N_TOPICS \  #cb-g-207
  YANDEX_CLOUD_API_KEY YANDEX_CLOUD_FOLDER \  #cb-g-208
  YANDEX_CLOUD_MODEL YANDEX_CLOUD_BASE_URL; do  #cb-g-209
  val=$(printenv "$var" 2>/dev/null)  #cb-g-210
  if [ -n "$val" ]; then  #cb-g-211
    echo "${var}=\"${val}\"" >> "$env_file"  #cb-g-212
  fi  #cb-g-213
done  #cb-g-214

chown shiny:shiny "$env_file"  #cb-g-215
exec /usr/bin/shiny-server "$@"  #cb-g-216
