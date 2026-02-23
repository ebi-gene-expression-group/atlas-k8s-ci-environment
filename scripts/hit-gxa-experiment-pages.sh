#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://hh-rke-wp-webadmin-35-master-1.caas.ebi.ac.uk:30603/gxa}"
EXPERIMENTS_JSON_URL="${EXPERIMENTS_JSON_URL:-${BASE_URL%/}/json/experiments}"
EXPERIMENT_JSON_URL_TEMPLATE="${BASE_URL%/}/json/experiments"
BIOENTITY_INFO_URL_TEMPLATE="${BASE_URL%/}/json/bioentity-information"
LIMIT="${LIMIT:-}"

# For each experiment, extract profiles.rows[].id and hit bioentity info URLs.
curl -fsSL "$EXPERIMENTS_JSON_URL" \
  | jq -r '.experiments[].experimentAccession' \
  | { if [[ -n "$LIMIT" ]]; then head -n "$LIMIT"; else cat; fi; } \
  | shuf \
  | while read -r accession; do
      # echo "Hitting experiment html page $accession"
      curl -fsSL "${BASE_URL%/}/experiments/${accession}/Results" >/dev/null &
      curl -fsSL "${BASE_URL%/}/experiments/${accession}/Plots" >/dev/null &
      # echo "Hitting experiment json page $accession"
      curl -fsSL "${EXPERIMENT_JSON_URL_TEMPLATE}/${accession}" >/dev/null &
      curl -fsSL "${EXPERIMENT_JSON_URL_TEMPLATE}/${accession}/resources/DATA" >/dev/null &
      curl -fsSL "${EXPERIMENT_JSON_URL_TEMPLATE}/${accession}/resources/PLOTS" >/dev/null &
      # echo "Hitting bioentities info URLs for $accession"
      curl -fsSL "${EXPERIMENT_JSON_URL_TEMPLATE}/${accession}" \
        | jq -r '.profiles.rows[].id' \
        | xargs -n 1 -P4 -I {} curl -fsSL "${BIOENTITY_INFO_URL_TEMPLATE}/{}" >/dev/null &
    done

    wait