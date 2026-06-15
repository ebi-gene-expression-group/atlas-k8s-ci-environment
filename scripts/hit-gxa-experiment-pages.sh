#!/usr/bin/env bash

# Hit GXA experiment pages to warm caches, exercise the application and gather performance metrics.
# Fetches experiment accessions, then requests four endpoints per experiment:
#   HTML:  /experiments/{accession}/Results, /experiments/{accession}/Plots
#   JSON:  /json/experiments/{accession}/resources/DATA, .../resources/PLOTS
#
# Individual results: tab-separated lines written to LOG_FILE (duration_s, status, bytes, url).
# Summary (tps, throughput, avg latency): stdout, stderr, and LOG_FILE.summary. Progress/config: stderr.
# Config (env or .env): BASE_URL, EXPERIMENTS_JSON_URL, LIMIT, SHUFFLE, PARALLEL, SORT_OUTPUT, LOG_FILE
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

BASE_URL="${BASE_URL:-http://hh-rke-wp-webadmin-35-master-1.caas.ebi.ac.uk:30932/gxa}"
BASE_URL="${BASE_URL%/}"
EXPERIMENTS_JSON_URL="${EXPERIMENTS_JSON_URL:-${BASE_URL}/json/experiments}"
LIMIT="${LIMIT:-}"          # empty or 0 = all experiments
SHUFFLE="${SHUFFLE:-1}"     # 1 = random order, 0 = catalogue order
PARALLEL="${PARALLEL:-32}"  # max concurrent curl requests
SORT_OUTPUT="${SORT_OUTPUT:-1}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-10}"
MAX_TIME="${MAX_TIME:-120}"
LOG_FILE="${LOG_FILE:-${SCRIPT_DIR}/gxa-hit-$(date +%Y%m%d-%H%M%S).tsv}"

USE_COLOR=0
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
  C_RESET= C_BOLD= C_DIM= C_GREEN= C_YELLOW= C_RED= C_CYAN= C_MAGENTA=
fi

now_s() {
  python3 -c 'import time; print(time.time())'
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
  local duration status bytes url
  IFS=$'\t' read -r duration status bytes url <<< "$1"

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

  printf '%b%s%b\t%b%s%b\t%s\t%s\n' \
    "$duration_color" "$duration" "$C_RESET" \
    "$status_color" "$status" "$C_RESET" \
    "$bytes" "$url"
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
  local aggregate_bps_display total_bytes_display avg_latency summary_file

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
  summary_file="${LOG_FILE%.*}.summary"

  {
    echo "=== summary ==="
    echo "requests:     ${total} (${ok} ok, ${fail} failed)"
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
read -r -a HTML_ENDPOINTS <<< "${HTML_ENDPOINTS:-Results Plots}"
read -r -a JSON_ENDPOINTS <<< "${JSON_ENDPOINTS:-resources/DATA resources/PLOTS}"

CURL_WRITE_OUT='%{time_total}\t%{http_code}\t%{size_download}\t%{url_effective}\n'

echo "${C_BOLD}starting $0${C_RESET}" >&2
echo "${C_DIM}BASE_URL:${C_RESET} $BASE_URL" >&2
echo "${C_DIM}EXPERIMENTS_JSON_URL:${C_RESET} $EXPERIMENTS_JSON_URL" >&2
echo "${C_DIM}LIMIT:${C_RESET} ${LIMIT:-all}" >&2
echo "${C_DIM}SHUFFLE:${C_RESET} $SHUFFLE" >&2
echo "${C_DIM}PARALLEL:${C_RESET} $PARALLEL" >&2
echo "${C_DIM}HTML endpoints:${C_RESET} ${HTML_ENDPOINTS[*]}" >&2
echo "${C_DIM}JSON endpoints:${C_RESET} ${JSON_ENDPOINTS[*]}" >&2
echo "${C_DIM}LOG_FILE:${C_RESET} $LOG_FILE" >&2
echo "${C_DIM}summary:${C_RESET} ${LOG_FILE%.*}.summary" >&2

if ! command -v jq >/dev/null 2>&1; then
  echo "${C_RED}ERROR: jq is required${C_RESET}" >&2
  exit 1
fi

accessions=()
while IFS= read -r accession; do
  [[ -n "$accession" ]] && accessions+=("$accession")
done < <(
  curl -fsSL --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
    "$EXPERIMENTS_JSON_URL" \
    | jq -r '.experiments[].experimentAccession'
)

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

echo "${C_BOLD}Hitting ${#accessions[@]} experiment(s), $(( ${#HTML_ENDPOINTS[@]} + ${#JSON_ENDPOINTS[@]} )) requests each${C_RESET}" >&2

log_file="$LOG_FILE"
mkdir -p "$(dirname "$log_file")"
: >"$log_file"

wait_for_slot() {
  while true; do
    active=$(jobs -rp | wc -l | tr -d ' ')
    (( active < PARALLEL )) && break
    sleep 0.05
  done
}

hit_url() {
  curl -sS -L -o /dev/null \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$MAX_TIME" \
    -w "$CURL_WRITE_OUT" \
    "$1" >>"$log_file" 2>/dev/null || true
}

run_start=$(now_s)

for accession in "${accessions[@]}"; do
  for endpoint in "${HTML_ENDPOINTS[@]}"; do
    wait_for_slot
    hit_url "${BASE_URL}/experiments/${accession}/${endpoint}" &
  done
  for endpoint in "${JSON_ENDPOINTS[@]}"; do
    wait_for_slot
    hit_url "${BASE_URL}/json/experiments/${accession}/${endpoint}" &
  done
done

wait
run_end=$(now_s)

if [[ "$SORT_OUTPUT" == "1" ]]; then
  sorted_file="$(mktemp)"
  sort -t $'\t' -k1,1nr "$log_file" >"$sorted_file"
  mv "$sorted_file" "$log_file"
fi

emit_summary
