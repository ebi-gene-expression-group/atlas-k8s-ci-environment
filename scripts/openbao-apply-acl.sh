#!/usr/bin/env bash
# Apply charts/openbao/acl/catalog.yaml to OpenBao on fg-public.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export BAO_ADDR="${BAO_ADDR:-https://openbao.hh-webadmin-35.wp-k8s.ebi.ac.uk}"
export OPENBAO_ACTOR="${OPENBAO_ACTOR:-root}"
exec python3 "$ROOT/scripts/openbao-apply-acl.py"
