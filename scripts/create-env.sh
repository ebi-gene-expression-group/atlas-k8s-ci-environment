#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <env-name> [release]" >&2
  echo "Example: $0 dev gxa" >&2
  exit 1
fi

ENV_NAME="$1"
RELEASE="${2:-gxa}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALUES_DIR="${REPO_ROOT}/charts/${RELEASE}"
TEMPLATE_FILE="${VALUES_DIR}/values-test.yaml"
TARGET_FILE="${VALUES_DIR}/values-${ENV_NAME}.yaml"

if [[ ! -d "${VALUES_DIR}" ]]; then
  echo "ERROR: Chart directory not found: ${VALUES_DIR}" >&2
  exit 1
fi

if [[ ! -f "${TEMPLATE_FILE}" ]]; then
  echo "ERROR: Template values file not found: ${TEMPLATE_FILE}" >&2
  exit 1
fi

if [[ -f "${TARGET_FILE}" ]]; then
  echo "ERROR: Target values file already exists: ${TARGET_FILE}" >&2
else
  echo "Creating ${TARGET_FILE}"
  cp "${TEMPLATE_FILE}" "${TARGET_FILE}"
  # Update common fields to match the new environment
  if grep -qE '^environment:' "${TARGET_FILE}"; then
    sed -i '' -E "s/^environment:.*/environment: ${ENV_NAME}/" "${TARGET_FILE}"
  else
    printf '\n%s\n' "environment: ${ENV_NAME}" >> "${TARGET_FILE}"
  fi
fi





cat <<EOF
Created ${TARGET_FILE}

Next steps:
- Review and update JDBC, Solr, and experiment settings in the new file.
- Deploy with: RELEASE=${RELEASE} ENV=${ENV_NAME} make deploy
EOF
