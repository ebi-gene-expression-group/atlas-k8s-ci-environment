#!/usr/bin/env bash

# Hit GXA experiment pages to warm caches, exercise the application and gather performance metrics.
# Fetches experiment accessions, then requests HTML and JSON resources for each. Follows redirects
# Output: access-log style lines (host, status, size, duration), sorted by duration (slowest first).
# Config: BASE_URL, LIMIT, HTML_RESOURCES, JSON_RESOURCES (see .env).
#
set -euo pipefail
# shellcheck source=.env
. "$(dirname "$0")/.env"

BASE_URL="${BASE_URL:-http://hh-rke-wp-webadmin-35-master-1.caas.ebi.ac.uk:30603/gxa}"
EXPERIMENTS_JSON_URL="${EXPERIMENTS_JSON_URL:-${BASE_URL%/}/json/experiments}"
EXPERIMENT_JSON_URL_TEMPLATE="${EXPERIMENT_JSON_URL_TEMPLATE:-${BASE_URL%/}/json/experiments}"
# BIOENTITY_INFO_URL_TEMPLATE="${BASE_URL%/}/json/bioentity-information"
LIMIT="${LIMIT:-}"
HTML_RESOURCES="${HTML_RESOURCES:-Results Plots}"
JSON_RESOURCES="${JSON_RESOURCES:-resources/DATA resources/PLOTS}"
# Extended access log: host ident authuser "request" status bytes duration_s
# (Add timestamps with: ./script.sh | ts '[%Y-%m-%dT%H:%M:%S]'  # requires moreutils)
CURL_OPTS=(-fsS -o /dev/null -w '%{remote_ip} - - "GET %{url_effective} HTTP/1.1" %{http_code} %{size_download} %{time_total}\n')
# For each experiment, extract profiles.rows[].id and hit bioentity info URLs.
curl -sSL "$EXPERIMENTS_JSON_URL" \
  | jq -r '.experiments[].experimentAccession' \
  | { if [[ -n "$LIMIT" ]]; then head -n "$LIMIT"; else cat; fi; } \
  | shuf \
  | while read -r accession; do
      for resource in $HTML_RESOURCES; do
        curl "${CURL_OPTS[@]}" "${BASE_URL}/experiments/${accession}/${resource}" &
      done
      for resource in $JSON_RESOURCES; do
        curl "${CURL_OPTS[@]}" "${EXPERIMENT_JSON_URL_TEMPLATE}/${accession}/${resource}" &
      done
    done 
