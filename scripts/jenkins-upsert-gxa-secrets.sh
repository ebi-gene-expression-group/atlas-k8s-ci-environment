#!/usr/bin/env bash
# Create or update the Jenkins Secret-file credential used by gxa-deploy
# (id gxa-secrets-<ENV>, file charts/gxa/.secrets-<ENV>.yaml).
#
# Required env: JENKINS_URL, JENKINS_USER, JENKINS_TOKEN
# Optional: ENV (default test), RELEASE (default gxa), FILE, ID,
#           JENKINS_CREDENTIALS_STORE (default system store under domain _)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV="${ENV:-test}"
RELEASE="${RELEASE:-gxa}"
ID="${ID:-${RELEASE}-secrets-${ENV}}"
FILE="${FILE:-${REPO_ROOT}/charts/${RELEASE}/.secrets-${ENV}.yaml}"

: "${JENKINS_URL:?Set JENKINS_URL (controller URL, trailing slash optional)}"
: "${JENKINS_USER:?Set JENKINS_USER}"
: "${JENKINS_TOKEN:?Set JENKINS_TOKEN}"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: secrets file not found: $FILE" >&2
  exit 1
fi

JENKINS_URL="${JENKINS_URL%/}"
STORE="${JENKINS_CREDENTIALS_STORE:-${JENKINS_URL}/credentials/store/system/domain/_}"
STORE="${STORE%/}"
CRED_URL="${STORE}/credential/${ID}"

COOKIE="$(mktemp)"
BODY="$(mktemp)"
XML="$(mktemp)"
trap 'rm -f "$COOKIE" "$BODY" "$XML"' EXIT

AUTH=(-u "${JENKINS_USER}:${JENKINS_TOKEN}")

CRUMB="$(
  curl -fsS "${AUTH[@]}" -c "$COOKIE" \
    "${JENKINS_URL}/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)"
)"

http_code() {
  local method="$1" url="$2"
  shift 2
  curl -sS "${AUTH[@]}" -b "$COOKIE" -c "$COOKIE" -H "$CRUMB" \
    -o /dev/null -w "%{http_code}" -X "$method" "$@" "$url"
}

EXISTING="$(http_code GET "${CRED_URL}/api/json")"
case "$EXISTING" in
  200) ACTION=update ;;
  404) ACTION=create ;;
  *)
    echo "ERROR: GET ${CRED_URL}/api/json returned HTTP ${EXISTING} (expected 200 or 404)" >&2
    echo "Check JENKINS_URL, credentials permission, and whether the id lives in a folder store." >&2
    echo "Folder example: JENKINS_CREDENTIALS_STORE=\$JENKINS_URL/job/<folder>/credentials/store/folder/domain/_" >&2
    exit 1
    ;;
esac

{
  printf '%s\n' '<org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl>'
  printf '%s\n' '  <scope>GLOBAL</scope>'
  printf '%s\n' "  <id>${ID}</id>"
  printf '%s\n' "  <description>${RELEASE} Helm secrets for ${ENV}</description>"
  printf '%s\n' "  <fileName>.secrets-${ENV}.yaml</fileName>"
  printf '  <secretBytes>%s</secretBytes>\n' "$(base64 < "$FILE" | tr -d '\n')"
  printf '%s\n' '</org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl>'
} >"$XML"

if [[ "$ACTION" == create ]]; then
  POST_URL="${STORE}/createCredentials"
else
  POST_URL="${CRED_URL}/config.xml"
fi

echo "Jenkins: ${JENKINS_URL}"
echo "Store:   ${STORE}"
echo "Id:      ${ID}"
echo "File:    ${FILE}"
echo "Action:  ${ACTION}  POST ${POST_URL}"

POST_CODE="$(
  curl -sS "${AUTH[@]}" -b "$COOKIE" -c "$COOKIE" -H "$CRUMB" \
    -o "$BODY" -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/xml" \
    --data-binary @"$XML" \
    "$POST_URL"
)"

if [[ "$POST_CODE" != 200 && "$POST_CODE" != 201 && "$POST_CODE" != 302 ]]; then
  echo "ERROR: POST returned HTTP ${POST_CODE}" >&2
  cat "$BODY" >&2 || true
  echo >&2
  exit 1
fi

VERIFY="$(http_code GET "${CRED_URL}/api/json")"
if [[ "$VERIFY" != 200 ]]; then
  echo "ERROR: credential ${ID} not readable after ${ACTION} (HTTP ${VERIFY})" >&2
  exit 1
fi

echo "OK: ${ACTION}d ${ID} (HTTP ${POST_CODE})"
