#!/usr/bin/env bash

# Hit GXA experiment pages to warm caches, exercise the application and gather performance metrics.
# Phases (env-controlled). Accession phases loop all accessions; searches are once per run:
#   WARM_ACCESSIONS=1  -> warm_accessions()  — HTML + JSON resource endpoints
#   WARM_BIOENTITIES=1 -> warm_bioentities() — experiment JSON + bioentity URLs
#   WARM_SEARCHES=1    -> warm_searches()    — baseline + differential search pages
#
# Individual results: tab-separated lines written to LOG_FILE (duration_s, status, bytes, method, url).
# Summary (tps, throughput, avg latency): stdout, stderr, and LOG_FILE.summary. Progress/config: stderr.
# Config (env or .env): BASE_URL, EXPERIMENTS_JSON_URL, LIMIT, SHUFFLE, PARALLEL,
#   REQUEST_INTERVAL_SECONDS, USER_START_INTERVAL_SECONDS,
#   WARM_ACCESSIONS, WARM_BIOENTITIES, WARM_SEARCHES, SEARCH_QUERIES_FILE, SEARCH_QUERIES,
#   SEARCH_SPECIES, PROGRESS, PROGRESS_INTERVAL, SORT_OUTPUT, LOG_FILE
# Catalogue order is descending numberOfAssays (largest experiments first); SHUFFLE=1 randomizes after LIMIT
# PARALLEL — concurrent virtual users; each user has one request in flight
# REQUEST_INTERVAL_SECONDS — think time before a user's next URL (not before their first)
# USER_START_INTERVAL_SECONDS — delay between launching each additional user (0 = together)
# WARM_ACCESSIONS=1 — HTML + JSON resource endpoints per accession (default)
# WARM_BIOENTITIES=1 — /json/experiments/{accession} -> profiles.rows -> bioentity URLs (default)
# WARM_SEARCHES=1 — POST /json/baseline_experiments and GET /json/search/differential_results (default)
# SEARCH_QUERIES_FILE — one geneQuery per line (default: scripts/search_terms.csv); # comments and a header are skipped
# SEARCH_QUERIES — optional comma-separated geneQuery override; when set, the file is not used
# SEARCH_CONDITIONS_FILE — one conditionQuery per line (default: scripts/search_conditions.csv)
# SEARCH_CONDITIONS — optional comma-separated conditionQuery override; when set, the file is not used
#   An empty geneQuery and an empty conditionQuery are always added and sent as []
# SEARCH_SPECIES — optional comma-separated override; when empty, species come from SPECIES_SUMMARY_URL
#   An empty species (any) is always added, so each term and condition is also searched with no species filter
# SPECIES_SUMMARY_URL — catalogue of species (iconSrc) used when SEARCH_SPECIES is empty
# Colors: auto when stdout is a TTY; NO_COLOR=1 disables, FORCE_COLOR=1 enables when piped
# LOG_FILE: defaults to scripts/gxa-hit-YYYYMMDD-HHMMSS.tsv next to this script
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_FILE="${ENV_FILE:-.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

if [[ -z "${BASE_URL:-}" && -n "${GXA_TARGET_JSON_URL:-}" ]]; then
  BASE_URL="${GXA_TARGET_JSON_URL%/json/experiments}"
fi

# start of configuration
BASE_URL="${BASE_URL:-http://hh-rke-wp-webadmin-35-master-1.caas.ebi.ac.uk:30932/gxa}"
BASE_URL="${BASE_URL%/}"
LIMIT="${LIMIT:0}"          # empty or 0 = all experiments
BIOENTITY_LIMIT="${BIOENTITY_LIMIT:-1}" # 0 = all bioentities, > 0 = limit to N bioentities per experiment
SHUFFLE="${SHUFFLE:-0}"     # 1 = random order, 0 = largest numberOfAssays first
PARALLEL="${PARALLEL:-15}"  # concurrent virtual users (one request in flight each)
REQUEST_INTERVAL_SECONDS="${REQUEST_INTERVAL_SECONDS:-0.25}"  # think time before a user's next URL
USER_START_INTERVAL_SECONDS="${USER_START_INTERVAL_SECONDS:-0.5}"  # delay between starting each user
WARM_ACCESSIONS="${WARM_ACCESSIONS:-1}"  # 1 = HTML + JSON resource endpoints per accession
WARM_BIOENTITIES="${WARM_BIOENTITIES:-0}"  # 1 = experiment JSON + /json/bioentity-information/{id}
WARM_SEARCHES="${WARM_SEARCHES:-1}"  # 1 = baseline + differential search pages (not per accession)
SEARCH_QUERIES="${SEARCH_QUERIES:-}"  # comma-separated geneQuery override; empty = load SEARCH_QUERIES_FILE
SEARCH_QUERIES_FILE="${SEARCH_QUERIES_FILE:-${SCRIPT_DIR}/search_terms.csv}"
SEARCH_CONDITIONS="${SEARCH_CONDITIONS:-}"  # comma-separated conditionQuery override; empty = load SEARCH_CONDITIONS_FILE
SEARCH_CONDITIONS_FILE="${SEARCH_CONDITIONS_FILE:-${SCRIPT_DIR}/search_conditions.csv}"
SEARCH_SPECIES="${SEARCH_SPECIES:-}"  # comma-separated override; empty = load SPECIES_SUMMARY_URL
SPECIES_SUMMARY_URL="${SPECIES_SUMMARY_URL:-https://wwwdev.ebi.ac.uk/gxa/json/species-summary}"
SORT_OUTPUT="${SORT_OUTPUT:-1}"
PROGRESS="${PROGRESS:-1}"  # 1 = live counts for the active phase (experiments, bioentities, or searches)
PROGRESS_INTERVAL="${PROGRESS_INTERVAL:-0.5}"  # seconds between live progress updates
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-10}"
MAX_TIME="${MAX_TIME:-120}"
OUTPUT_DIR="${OUTPUT_DIR:-${SCRIPT_DIR}/../reports/performance}"
LOG_FILE="${LOG_FILE:-${OUTPUT_DIR}/gxa-hit-$(date +%Y%m%d-%H%M%S).tsv}"
USE_COLOR=0
# end of configuration

EXPERIMENTS_JSON_URL="${EXPERIMENTS_JSON_URL:-${BASE_URL}/json/experiments}"


if [[ -t 1 && -z "${NO_COLOR:-}" ]] || [[ "${FORCE_COLOR:-}" == "1" ]]; then
  USE_COLOR=1
fi

if [[ "$USE_COLOR" == "1" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_CYAN=$'\033[36m'
  C_MAGENTA=$'\033[35m'
else
  C_RESET="" C_BOLD="" C_DIM="" C_GREEN="" C_YELLOW="" C_RED="" C_CYAN="" C_MAGENTA=""
fi

now_s() {
  # python3 -c 'import time; print(time.time())'
  date +%s.%N
}

format_bytes_rate() {
  awk -v bps="$1" 'BEGIN {
    if (bps >= 1048576) printf "%.1f MB/s", bps / 1048576
    else if (bps >= 1024) printf "%.1f KB/s", bps / 1024
    else printf "%.0f B/s", bps
  }'
}

format_bytes_total() {
  awk -v bytes="$1" 'BEGIN {
    if (bytes >= 1048576) printf "%.1f MB", bytes / 1048576
    else if (bytes >= 1024) printf "%.1f KB", bytes / 1024
    else printf "%d B", bytes
  }'
}

colorize_result_line() {
  local duration status bytes method url
  IFS=$'\t' read -r duration status bytes method url <<< "$1"

  local status_color="$C_GREEN"
  if [[ ! "$status" =~ ^[0-9]+$ ]] || [[ "$status" -eq 0 ]]; then
    status_color="$C_RED"
  elif (( status >= 500 )); then
    status_color="$C_RED"
  elif (( status >= 400 )); then
    status_color="$C_YELLOW"
  elif (( status >= 300 )); then
    status_color="$C_CYAN"
  fi

  local duration_color="$C_DIM"
  if awk -v d="$duration" 'BEGIN { exit !(d >= 3.0) }'; then
    duration_color="$C_RED"
  elif awk -v d="$duration" 'BEGIN { exit !(d >= 1.0) }'; then
    duration_color="$C_YELLOW"
  fi

  printf '%b%s%b\t%b%s%b\t%s\t%s\t%s\n' \
    "$duration_color" "$duration" "$C_RESET" \
    "$status_color" "$status" "$C_RESET" \
    "$bytes" "$method" "$url"
}

print_slowest_line() {
  local line="$1"
  if [[ "$USE_COLOR" == "1" ]]; then
    colorize_result_line "$line"
  else
    printf '%s\n' "$line"
  fi
}

emit_summary() {
  local total ok fail slowest run_elapsed aggregate_rps total_bytes aggregate_bps
  local aggregate_bps_display total_bytes_display avg_latency summary_file status_counts
  local code count status_color

  total=$(wc -l <"$log_file" | tr -d ' ')
  ok=$(awk -F'\t' '$2 >= 200 && $2 < 400 { c++ } END { print c + 0 }' "$log_file")
  fail=$((total - ok))
  slowest=$(head -n1 "$log_file")
  run_elapsed=$(awk -v s="$run_start" -v e="$run_end" 'BEGIN { printf "%.3f", e - s }')
  aggregate_rps=$(awk -v n="$total" -v t="$run_elapsed" 'BEGIN { if (t > 0) printf "%.2f", n / t; else print "0.00" }')
  total_bytes=$(awk -F'\t' '{ bytes += $3 } END { print bytes + 0 }' "$log_file")
  aggregate_bps=$(awk -v b="$total_bytes" -v t="$run_elapsed" 'BEGIN { if (t > 0) print b / t; else print 0 }')
  aggregate_bps_display=$(format_bytes_rate "$aggregate_bps")
  total_bytes_display=$(format_bytes_total "$total_bytes")
  avg_latency=$(awk -F'\t' '{ sum += $1; n++ } END { if (n > 0) printf "%.3f", sum / n; else print "0.000" }' "$log_file")
  status_counts=$(awk -F'\t' '{ c[$2]++ } END { for (s in c) printf "%s\t%s\n", s, c[s] }' "$log_file" | sort -n)
  summary_file="${LOG_FILE%.*}.summary"

  {
    echo "=== summary ==="
    echo "requests:     ${total} (${ok} ok, ${fail} failed)"
    echo "status:"
    if [[ -n "$status_counts" ]]; then
      while IFS=$'\t' read -r code count; do
        printf '  %-6s %s\n' "$code" "$count"
      done <<<"$status_counts"
    fi
    echo "wall time:    ${run_elapsed}s"
    echo "tps:          ${aggregate_rps} req/s"
    echo "throughput:   ${aggregate_bps_display} (${total_bytes_display} total)"
    echo "avg latency:  ${avg_latency}s"
    echo "slowest:      ${slowest}"
    echo "log file:     ${LOG_FILE}"
  } >"$summary_file"

  if [[ "$USE_COLOR" == "1" ]]; then
    if (( fail > 0 )); then
      fail_part="${C_RED}${fail} failed${C_RESET}"
    else
      fail_part="${C_GREEN}0 failed${C_RESET}"
    fi
    {
      printf '%b\n' "${C_BOLD}=== summary ===${C_RESET}"
      printf 'requests:     %s (%s ok, %b)\n' "$total" "${C_GREEN}${ok}${C_RESET}" "$fail_part"
      printf '%bstatus:%b\n' "$C_DIM" "$C_RESET"
      if [[ -n "$status_counts" ]]; then
        while IFS=$'\t' read -r code count; do
          status_color="$C_GREEN"
          if [[ ! "$code" =~ ^[0-9]+$ ]] || [[ "$code" -eq 0 ]]; then
            status_color="$C_RED"
          elif (( code >= 500 )); then
            status_color="$C_RED"
          elif (( code >= 400 )); then
            status_color="$C_YELLOW"
          elif (( code >= 300 )); then
            status_color="$C_CYAN"
          fi
          printf '  %b%-6s%b %s\n' "$status_color" "$code" "$C_RESET" "$count"
        done <<<"$status_counts"
      fi
      printf 'wall time:    %ss\n' "$run_elapsed"
      printf 'tps:          %b%s req/s%b\n' "$C_CYAN" "$aggregate_rps" "$C_RESET"
      printf 'throughput:   %b%s%b (%s total)\n' "$C_CYAN" "$aggregate_bps_display" "$C_RESET" "$total_bytes_display"
      printf 'avg latency:  %b%ss%b\n' "$C_CYAN" "$avg_latency" "$C_RESET"
      printf '%b' "${C_MAGENTA}slowest:      ${C_RESET}"
      print_slowest_line "$slowest"
      printf '%b\n' "${C_DIM}log file:     ${C_RESET}${LOG_FILE}"
      printf '%b\n' "${C_DIM}summary file: ${C_RESET}${summary_file}"
    } | tee /dev/stderr
  else
    tee /dev/stderr <"$summary_file"
    echo "summary file: ${summary_file}"
  fi
}

# Four endpoints per experiment (override with space-separated lists if needed).
read -r -a HTML_ENDPOINTS <<< "${HTML_ENDPOINTS:-Results Plots Downloads}"
read -r -a JSON_ENDPOINTS <<< "${JSON_ENDPOINTS:-resources/DATA resources/PLOTS}"
# One term per line. Blank lines, # comments, and a header (search_term or condition) are skipped.
load_search_terms() {
  local file="$1"
  local line
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" == \#* || "$line" == "search_term" || "$line" == "condition" ]] && continue
    printf '%s\n' "$line"
  done < "$file"
}

search_queries=()
search_conditions=()
if [[ -n "$SEARCH_QUERIES" ]]; then
  IFS=',' read -r -a search_queries <<< "$SEARCH_QUERIES"
else
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] && search_queries+=("$line")
  done < <(load_search_terms "$SEARCH_QUERIES_FILE")
fi
if [[ -n "$SEARCH_CONDITIONS" ]]; then
  IFS=',' read -r -a search_conditions <<< "$SEARCH_CONDITIONS"
else
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] && search_conditions+=("$line")
  done < <(load_search_terms "$SEARCH_CONDITIONS_FILE")
fi
# Empty gene and condition are extra product slots, sent as [] by warm_searches.
if [[ "$WARM_SEARCHES" == "1" && ${#search_queries[@]} -gt 0 ]]; then
  search_queries+=("")
fi
if [[ "$WARM_SEARCHES" == "1" && ${#search_conditions[@]} -gt 0 ]]; then
  search_conditions+=("")
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "${C_RED}ERROR: jq is required${C_RESET}" >&2
  exit 1
fi

search_species=()
if [[ -n "$SEARCH_SPECIES" ]]; then
  IFS=',' read -r -a search_species <<< "$SEARCH_SPECIES"
elif [[ "$WARM_SEARCHES" == "1" ]]; then
  echo "${C_DIM}Loading species from:${C_RESET} $SPECIES_SUMMARY_URL" >&2
  if ! species_json=$(curl -fsSL \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$MAX_TIME" \
    "$SPECIES_SUMMARY_URL"); then
    echo "${C_RED}ERROR: failed to load species from $SPECIES_SUMMARY_URL${C_RESET}" >&2
    exit 1
  fi
  while IFS= read -r species || [[ -n "$species" ]]; do
    [[ -n "$species" ]] && search_species+=("$species")
  done < <(jq -r '.speciesSummary[].cards[].iconSrc | select(length > 0)' <<<"$species_json")
fi
# Empty species is the "any" filter: one extra pass per gene and condition.
if [[ "$WARM_SEARCHES" == "1" ]]; then
  search_species+=("")
fi

CURL_WRITE_OUT='%{time_total}\t%{http_code}\t%{size_download}\t%{method}\t%{url_effective}\n'

echo "${C_BOLD}starting $0${C_RESET}" >&2
echo "${C_DIM}date:${C_RESET} $(date)" >&2
echo "${C_DIM}BASE_URL:${C_RESET} $BASE_URL" >&2
echo "${C_DIM}EXPERIMENTS_JSON_URL:${C_RESET} $EXPERIMENTS_JSON_URL" >&2
echo "${C_DIM}LIMIT:${C_RESET} ${LIMIT:-all}" >&2
echo "${C_DIM}BIOENTITY_LIMIT:${C_RESET} ${BIOENTITY_LIMIT:-1}" >&2
echo "${C_DIM}SHUFFLE:${C_RESET} $SHUFFLE" >&2
echo "${C_DIM}PARALLEL:${C_RESET} $PARALLEL" >&2
echo "${C_DIM}REQUEST_INTERVAL_SECONDS:${C_RESET} $REQUEST_INTERVAL_SECONDS" >&2
echo "${C_DIM}USER_START_INTERVAL_SECONDS:${C_RESET} $USER_START_INTERVAL_SECONDS" >&2
echo "${C_DIM}WARM_ACCESSIONS:${C_RESET} $WARM_ACCESSIONS" >&2
echo "${C_DIM}WARM_BIOENTITIES:${C_RESET} $WARM_BIOENTITIES" >&2
echo "${C_DIM}WARM_SEARCHES:${C_RESET} $WARM_SEARCHES" >&2
echo "${C_DIM}SEARCH_QUERIES_FILE:${C_RESET} $SEARCH_QUERIES_FILE" >&2
echo "${C_DIM}SEARCH_CONDITIONS_FILE:${C_RESET} $SEARCH_CONDITIONS_FILE" >&2
queries_display=""
conditions_display=""
if ((${#search_queries[@]} > 0)); then
  query_parts=()
  for query in "${search_queries[@]}"; do
    query_parts+=("${query:-any}")
  done
  queries_display="${query_parts[*]}"
fi
if ((${#search_conditions[@]} > 0)); then
  condition_parts=()
  for condition in "${search_conditions[@]}"; do
    condition_parts+=("${condition:-any}")
  done
  conditions_display="${condition_parts[*]}"
fi
echo "${C_DIM}SEARCH_QUERIES (${#search_queries[@]}):${C_RESET} ${queries_display}" >&2
echo "${C_DIM}SEARCH_CONDITIONS (${#search_conditions[@]}):${C_RESET} ${conditions_display}" >&2
echo "${C_DIM}SPECIES_SUMMARY_URL:${C_RESET} $SPECIES_SUMMARY_URL" >&2
species_display=""
if ((${#search_species[@]} > 0)); then
  species_parts=()
  for species in "${search_species[@]}"; do
    species_parts+=("${species:-any}")
  done
  species_display="${species_parts[*]}"
fi
echo "${C_DIM}SEARCH_SPECIES (${#search_species[@]}):${C_RESET} ${species_display}" >&2
echo "${C_DIM}PROGRESS:${C_RESET} $PROGRESS" >&2
echo "${C_DIM}HTML endpoints:${C_RESET} ${HTML_ENDPOINTS[*]}" >&2
echo "${C_DIM}JSON endpoints:${C_RESET} ${JSON_ENDPOINTS[*]}" >&2
echo "${C_DIM}LOG_FILE:${C_RESET} $LOG_FILE" >&2
echo "${C_DIM}summary:${C_RESET} ${LOG_FILE%.*}.summary" >&2

HEALTH_URL="${BASE_URL}/json/health"
echo "${C_DIM}Checking health:${C_RESET} $HEALTH_URL" >&2
if ! health_response=$(curl -fsSL \
  --connect-timeout "$CONNECT_TIMEOUT" \
  --max-time "$MAX_TIME" \
  "$HEALTH_URL"); then
  echo "${C_RED}ERROR: health check failed for $HEALTH_URL${C_RESET}" >&2
  exit 1
fi
if ! jq -e '.solr == "UP" and .db == "UP"' >/dev/null <<<"$health_response"; then
  echo "${C_RED}ERROR: health check is not ready for $HEALTH_URL: $health_response${C_RESET}" >&2
  exit 1
fi

if [[ "$WARM_ACCESSIONS" != "1" && "$WARM_BIOENTITIES" != "1" && "$WARM_SEARCHES" != "1" ]]; then
  echo "${C_RED}ERROR: enable WARM_ACCESSIONS, WARM_BIOENTITIES, and/or WARM_SEARCHES${C_RESET}" >&2
  exit 1
fi

if [[ "$WARM_SEARCHES" == "1" && ( ${#search_queries[@]} -eq 0 || ${#search_conditions[@]} -eq 0 ) ]]; then
  echo "${C_RED}ERROR: search warmups need both gene terms and conditions (SEARCH_QUERIES_FILE and SEARCH_CONDITIONS_FILE)${C_RESET}" >&2
  exit 1
fi

if [[ "$WARM_SEARCHES" == "1" && ${#search_species[@]} -eq 0 ]]; then
  echo "${C_RED}ERROR: no search species (set SEARCH_SPECIES or SPECIES_SUMMARY_URL)${C_RESET}" >&2
  exit 1
fi

# Allow user to set accessions externally by providing ACCESSIONS as a space-separated list.
accessions=()
if [[ "$WARM_ACCESSIONS" == "1" || "$WARM_BIOENTITIES" == "1" ]]; then
  if [[ -n "${ACCESSIONS:-}" ]]; then
    IFS=' ' read -r -a accessions <<< "$ACCESSIONS"
  else
    while IFS= read -r accession; do
      [[ -n "$accession" ]] && accessions+=("$accession")
    done < <(
      curl -fsSL \
        --connect-timeout "$CONNECT_TIMEOUT" \
        --max-time "$MAX_TIME" \
        "$EXPERIMENTS_JSON_URL" \
        | jq -r '.experiments | sort_by(.numberOfAssays) | reverse[] | .experimentAccession'
    )
  fi

  if ((${#accessions[@]} == 0)); then
    echo "${C_RED}ERROR: no experiment accessions returned from $EXPERIMENTS_JSON_URL${C_RESET}" >&2
    exit 1
  fi

  if [[ -n "$LIMIT" && "$LIMIT" =~ ^[0-9]+$ && "$LIMIT" -gt 0 ]]; then
    accessions=("${accessions[@]:0:LIMIT}")
  fi

  if [[ "$SHUFFLE" == "1" ]]; then
    shuffled=()
    while IFS= read -r accession; do
      [[ -n "$accession" ]] && shuffled+=("$accession")
    done < <(printf '%s\n' "${accessions[@]}" | shuf)
    accessions=("${shuffled[@]}")
  fi
fi

warm_plan=""
[[ "$WARM_ACCESSIONS" == "1" ]] && warm_plan="${#HTML_ENDPOINTS[@]} HTML + ${#JSON_ENDPOINTS[@]} JSON per accession"
[[ -n "$warm_plan" && "$WARM_BIOENTITIES" == "1" ]] && warm_plan+=", "
[[ "$WARM_BIOENTITIES" == "1" ]] && warm_plan+="bioentity URLs from profiles.rows"
[[ -n "$warm_plan" && "$WARM_SEARCHES" == "1" ]] && warm_plan+=", "
[[ "$WARM_SEARCHES" == "1" ]] && warm_plan+="baseline + differential search pages"
if [[ "$WARM_ACCESSIONS" == "1" || "$WARM_BIOENTITIES" == "1" ]]; then
  echo "${C_BOLD}Hitting ${#accessions[@]} experiment(s) (${warm_plan})${C_RESET}" >&2
else
  echo "${C_BOLD}Hitting ${warm_plan}${C_RESET}" >&2
fi

log_file="$LOG_FILE"
mkdir -p "$(dirname "$log_file")"
: >"$log_file"
progress_state_file="${log_file}.progress"
progress_watch_flag="${log_file}.watch"
accession_queue="${log_file}.queue"
work_lock="${log_file}.work.lock"

# Unit separator, not tab: bash read treats tab as whitespace and drops the empty
# accession field, which shifts the total into the label and leaves the denominator 0.
PROGRESS_SEP=$'\x1f'

write_progress_state() {
  local tmp
  tmp="$(mktemp "${progress_state_file}.tmp.XXXXXX")"
  printf '%s%s%s%s%s%s%s\n' \
    "$acc_index" "$PROGRESS_SEP" \
    "$current_accession" "$PROGRESS_SEP" \
    "$progress_label" "$PROGRESS_SEP" \
    "$progress_total" >"$tmp"
  mv "$tmp" "$progress_state_file"
}

read_progress_state() {
  acc_index=0
  current_accession=""
  progress_label="${progress_label:-experiments}"
  progress_total="${progress_total:-0}"
  if [[ -f "$progress_state_file" ]]; then
    IFS="$PROGRESS_SEP" read -r acc_index current_accession progress_label progress_total <"$progress_state_file" || true
    acc_index="${acc_index:-0}"
    progress_label="${progress_label:-experiments}"
    progress_total="${progress_total:-0}"
  fi
  [[ "$acc_index" =~ ^[0-9]+$ ]] || acc_index=0
  [[ "$progress_total" =~ ^[0-9]+$ ]] || progress_total=0
}

INTERRUPTED=0

kill_background_jobs() {
  local pid
  while IFS= read -r pid; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done < <(jobs -rp)
}

on_interrupt() {
  if [[ "$INTERRUPTED" == "1" ]]; then
    kill_background_jobs
    exit 130
  fi
  INTERRUPTED=1
  printf '\n%bInterrupted — stopping...%b\n' "$C_YELLOW" "$C_RESET" >&2
  stop_progress_watcher
  kill_background_jobs
  wait 2>/dev/null || true
  run_end=$(now_s)
  if [[ -s "$log_file" ]]; then
    emit_summary
  fi
  cleanup_work_files
  exit 130
}

trap on_interrupt INT TERM

interval_positive() {
  awk -v s="$1" 'BEGIN { exit !(s > 0) }'
}

interruptible_sleep() {
  local seconds="$1"
  interval_positive "$seconds" || return 0
  sleep "$seconds" &
  wait "$!" || true
}

acquire_lock() {
  local lock_dir="$1"
  while ! mkdir "$lock_dir" 2>/dev/null; do
    [[ "$INTERRUPTED" == "1" ]] && return 1
    sleep 0.05
  done
}

release_lock() {
  rmdir "$1" 2>/dev/null || true
}

# Claim the next accession and record it in the progress file. Empty queue -> failure.
claim_accession() {
  local line=""
  acquire_lock "$work_lock" || return 1
  line="$(claim_accession_locked)" || true
  release_lock "$work_lock"
  [[ -n "$line" ]] || return 1
  printf '%s\n' "$line"
}

claim_accession_locked() {
  local line=""
  [[ -s "$accession_queue" ]] || return 0
  IFS= read -r line <"$accession_queue" || return 0
  [[ -n "$line" ]] || return 0
  tail -n +2 "$accession_queue" >"${accession_queue}.next"
  mv "${accession_queue}.next" "$accession_queue"
  read_progress_state
  acc_index=$((acc_index + 1))
  current_accession="$line"
  write_progress_state
  printf '%s\n' "$line"
}

hit_url() {
  curl -sS -L -o /dev/null \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$MAX_TIME" \
    -w "$CURL_WRITE_OUT" \
    "$1" >>"$log_file" 2>/dev/null || true
}

# Think time before every request except this user's first.
user_think() {
  if [[ "$user_has_requested" == "1" ]]; then
    interruptible_sleep "$REQUEST_INTERVAL_SECONDS"
  fi
  user_has_requested=1
}

user_hit_url() {
  [[ "$INTERRUPTED" == "1" ]] && return 0
  user_think
  [[ "$INTERRUPTED" == "1" ]] && return 0
  hit_url "$1"
}

warm_accession_pages() {
  local accession="$1"
  local endpoint
  [[ "$INTERRUPTED" == "1" ]] && return 0
  for endpoint in "${HTML_ENDPOINTS[@]}"; do
    [[ "$INTERRUPTED" == "1" ]] && return 0
    user_hit_url "${BASE_URL}/experiments/${accession}/${endpoint}"
  done
  for endpoint in "${JSON_ENDPOINTS[@]}"; do
    [[ "$INTERRUPTED" == "1" ]] && return 0
    user_hit_url "${BASE_URL}/json/experiments/${accession}/${endpoint}"
  done
  return 0
}

# Fetch experiment JSON (logged), then each /json/bioentity-information/{id} in order.
warm_bioentity_accession() {
  local accession="$1"
  local experiment_json_url="${BASE_URL}/json/experiments/${accession}"
  local tmp id bioentity_count=0
  [[ "$INTERRUPTED" == "1" ]] && return 0
  tmp="$(mktemp)"

  user_think
  curl -sS -L -o "$tmp" \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$MAX_TIME" \
    -w "$CURL_WRITE_OUT" \
    "$experiment_json_url" >>"$log_file" 2>/dev/null || true

  while IFS= read -r id; do
    [[ "$INTERRUPTED" == "1" ]] && break
    [[ -n "$id" ]] || continue
    if [[ "$BIOENTITY_LIMIT" -gt 0 && "$bioentity_count" -ge "$BIOENTITY_LIMIT" ]]; then
      break
    fi
    user_hit_url "${BASE_URL}/json/bioentity-information/${id}"
    bioentity_count=$((bioentity_count + 1))
  done < <(jq -r '.profiles.rows[]?.id // empty' "$tmp" 2>/dev/null || true)

  rm -f "$tmp"
  return 0
}

user_worker() {
  local accession
  user_has_requested=0
  while accession="$(claim_accession)"; do
    [[ "$INTERRUPTED" == "1" ]] && break
    case "$USER_PHASE" in
      bioentities)
        warm_bioentity_accession "$accession"
        ;;
      *)
        warm_accession_pages "$accession"
        ;;
    esac
  done
  return 0
}

run_user_workers() {
  local i pid started=0
  local -a pids=()
  USER_PHASE="$1"
  case "$USER_PHASE" in
    bioentities) progress_label="bioentities" ;;
    *) progress_label="experiments" ;;
  esac
  progress_total=${#accessions[@]}
  acc_index=0
  current_accession=""
  write_progress_state
  printf '%s\n' "${accessions[@]}" >"$accession_queue"
  for ((i = 0; i < PARALLEL; i++)); do
    if (( started > 0 )); then
      interruptible_sleep "$USER_START_INTERVAL_SECONDS"
    fi
    [[ "$INTERRUPTED" == "1" ]] && break
    user_worker &
    pids+=("$!")
    started=$((started + 1))
  done
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
}

warm_accessions() {
  run_user_workers experiments
}

warm_bioentities() {
  run_user_workers bioentities
}

# Search pages are global (one pass per run), not tied to an accession or bioentity.
# gene_query and condition_query are raw terms; an empty term is sent as [].
warm_searches() {
  local gene_query="${1:-}"
  local species_query="${2:-}"
  local condition_query="${3:-}"
  local search_term_category="${4:-symbol}"
  
  if [[ -n "$gene_query" ]]; then
    gene_query="[{\"value\":\"${gene_query}\",\"category\":\"${search_term_category}\"}]"
  else
    gene_query="[]"
  fi
  if [[ -n "$condition_query" ]]; then
    condition_query="[{\"value\":\"${condition_query}\"}]"
  else
    condition_query="[]"
  fi

  curl -sS -L -o /dev/null \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$MAX_TIME" \
    -w "$CURL_WRITE_OUT" \
    --data-urlencode "geneQuery=${gene_query}" \
    --data-urlencode "conditionQuery=${condition_query}" \
    --data-urlencode "species=${species_query}" \
    --data-urlencode 'source=ORGANISM_PART' \
    "${BASE_URL}/json/baseline_experiments" >>"$log_file" 2>/dev/null || true

  interruptible_sleep "$REQUEST_INTERVAL_SECONDS"

  curl -sS -L --get -o /dev/null \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$MAX_TIME" \
    -w "$CURL_WRITE_OUT" \
    --data-urlencode "geneQuery=${gene_query}" \
    --data-urlencode "conditionQuery=${condition_query}" \
    --data-urlencode "species=${species_query}" \
    "${BASE_URL}/json/search/differential_results" >>"$log_file" 2>/dev/null || true

  interruptible_sleep "$REQUEST_INTERVAL_SECONDS"

  curl -sS -L --get -o /dev/null \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$MAX_TIME" \
    -w "$CURL_WRITE_OUT" \
    --data-urlencode "geneQuery=${gene_query}" \
    --data-urlencode "conditionQuery=${condition_query}" \
    --data-urlencode "species=${species_query}" \
    "${BASE_URL}/json/search/differential_facets" >>"$log_file" 2>/dev/null || true
}

cleanup_work_files() {
  rm -f "$accession_queue" "${accession_queue}.next" "${progress_state_file}.tmp."*
  release_lock "$work_lock"
}

report_progress() {
  local current="$1"
  local total="$2"
  local accession="$3"
  local label="${progress_label:-experiments}"
  [[ "$PROGRESS" == "1" ]] || return 0
  local logged elapsed req_per_sec
  logged=$(wc -l <"$log_file" | tr -d ' ')
  elapsed=$(awk -v s="$run_start" -v e="$(now_s)" 'BEGIN { printf "%.1f", e - s }')
  req_per_sec=$(awk -v n="$logged" -v t="$elapsed" 'BEGIN {
    if (t > 0) printf "%.1f", n / t
    else print "0.0"
  }')
  mean_latency=$(awk '{sum+=$1} END {if(NR>0) printf "%.2f", sum/NR; else print "0.00"}' "$log_file")
  if [[ -t 2 && "$USE_COLOR" == "1" ]]; then
    printf '\r%b%-12s %4d/%d%b  %brequests: %7s%b  %b%2.2f req/s%b  latency %b%2.2f s/req%b %s%b\033[K' \
      "$C_CYAN" "${label}:" "$current" "$total" "$C_RESET" \
      "$C_DIM" "$logged" "$C_RESET" \
      "$C_CYAN" "$req_per_sec" "$C_RESET" \
      "$C_DIM" "$mean_latency" "$C_RESET" \
      "$accession" >&2
  else
    printf '%-12s %4d/%d  requests: %7s  %2.2f req/s  %2.2f s/req %s\n' \
      "${label}:" "$current" "$total" "$logged" "$req_per_sec" "$mean_latency" "$accession" >&2
  fi
}

progress_watcher() {
  while [[ -f "$progress_watch_flag" && "$INTERRUPTED" != "1" ]]; do
    read_progress_state
    report_progress "$acc_index" "$progress_total" "$current_accession"
    sleep "$PROGRESS_INTERVAL" &
    wait $! 2>/dev/null || true
  done
}

start_progress_watcher() {
  [[ "$PROGRESS" == "1" ]] || return 0
  write_progress_state
  touch "$progress_watch_flag"
  progress_watcher &
  progress_watch_pid=$!
}

stop_progress_watcher() {
  [[ -n "${progress_watch_pid:-}" ]] || return 0
  rm -f "$progress_watch_flag"
  kill "$progress_watch_pid" 2>/dev/null || true
  wait "$progress_watch_pid" 2>/dev/null || true
  unset progress_watch_pid
  rm -f "$progress_state_file" "$progress_watch_flag"
}

run_start=$(now_s)
acc_index=0
current_accession=""
if [[ "$WARM_ACCESSIONS" == "1" ]]; then
  progress_label="experiments"
  progress_total=${#accessions[@]}
elif [[ "$WARM_BIOENTITIES" == "1" ]]; then
  progress_label="bioentities"
  progress_total=${#accessions[@]}
else
  progress_label="searches"
  progress_total=$(( ${#search_queries[@]} * ${#search_species[@]} * ${#search_conditions[@]} ))
fi

write_progress_state
start_progress_watcher

if [[ "$WARM_ACCESSIONS" == "1" ]]; then
  warm_accessions
fi
if [[ "$WARM_BIOENTITIES" == "1" ]]; then
  warm_bioentities
fi
if [[ "$WARM_SEARCHES" == "1" ]]; then
  search_index=0
  progress_label="searches"
  progress_total=$(( ${#search_queries[@]} * ${#search_species[@]} * ${#search_conditions[@]} ))
  acc_index=0
  current_accession=""
  write_progress_state
  for query in "${search_queries[@]}"; do
    for species in "${search_species[@]}"; do
      for condition in "${search_conditions[@]}"; do
        search_index=$((search_index + 1))
        acc_index=$search_index
        current_accession="${query:-any} / ${condition:-any} (${species:-any})"
        write_progress_state
        if [[ "$PROGRESS" != "1" ]]; then
          echo "Warming up search for gene: ${query:-any}, condition: ${condition:-any}, species: ${species:-any}" >&2
        fi
        warm_searches "$query" "$species" "$condition"
      done
    done
  done
fi

read_progress_state
cleanup_work_files
stop_progress_watcher
report_progress "$acc_index" "$progress_total" "$current_accession"

if [[ "$PROGRESS" == "1" && -t 2 ]]; then
  echo >&2
fi

[[ "$INTERRUPTED" == "1" ]] && exit 130

wait
run_end=$(now_s)

if [[ "$SORT_OUTPUT" == "1" ]]; then
  sorted_file="$(mktemp)"
  sort -t $'\t' -k1,1nr "$log_file" >"$sorted_file"
  mv "$sorted_file" "$log_file"
fi

emit_summary
