#!/usr/bin/env bash
# Merge charts/openbao/acl/catalog.*.yaml, then apply the result to OpenBao on fg-public.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export BAO_ADDR="${BAO_ADDR:-https://openbao.hh-webadmin-35.wp-k8s.ebi.ac.uk}"
export OPENBAO_ACTOR="${OPENBAO_ACTOR:-root}"

if [[ -t 1 && -z "${NO_COLOR:-}" ]] || [[ "${FORCE_COLOR:-}" == "1" ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_GREEN=$'\033[32m'
    C_RED=$'\033[31m'
    C_CYAN=$'\033[36m'
else
    C_RESET="" C_BOLD="" C_DIM="" C_GREEN="" C_RED="" C_CYAN=""
fi

log() { printf '%b\n' "${C_CYAN}${C_BOLD}==>${C_RESET} $*"; }
ok() { printf '%b\n' "${C_GREEN}${C_BOLD}ok${C_RESET} $*"; }

tmp="${TMPDIR:-/tmp}"
catalog_dir="$(mktemp -d "${tmp%/}/openbao-catalog.XXXXXX")"
cleanup() {
    local rc=$?
    rm -rf "$catalog_dir"
    if [[ $rc -ne 0 ]]; then
        printf '%b\n' "${C_RED}${C_BOLD}error${C_RESET} ACL apply failed (exit ${rc})" >&2
    fi
}
trap cleanup EXIT

shopt -s nullglob
catalogs=( "$ROOT"/charts/openbao/acl/catalog.*.yaml )
if [[ ${#catalogs[@]} -eq 0 ]]; then
    printf '%b\n' "${C_RED}${C_BOLD}error${C_RESET} no catalogs match charts/openbao/acl/catalog.*.yaml" >&2
    exit 1
fi

log "Merging ${#catalogs[@]} ACL catalogs"
for catalog in "${catalogs[@]}"; do
    printf '%b\n' "  ${C_DIM}${catalog#"$ROOT"/}${C_RESET}"
done

# *+ extends maps and concatenates arrays. Drop null values so an empty key
# (for example secret_sets:) does not wipe a list merged from another file.
# shellcheck disable=SC2016
yq eval-all '. as $item ireduce ({}; . *+ ($item | with_entries(select(.value != null))))' \
    "${catalogs[@]}" \
    > "$catalog_dir/catalog.yaml"
export OPENBAO_CATALOG="$catalog_dir/catalog.yaml"
log "Wrote ${C_DIM}${OPENBAO_CATALOG}${C_RESET}"

log "Applying ACL as ${C_BOLD}${OPENBAO_ACTOR}${C_RESET} at ${C_DIM}${BAO_ADDR}${C_RESET}"
python3 "$ROOT/scripts/openbao-apply-acl.py"
ok "ACL apply complete"
