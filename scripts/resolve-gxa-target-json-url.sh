#!/usr/bin/env bash
# Print GXA_TARGET_JSON_URL from the current k8s cluster (ingress), for Helm ENV=test / gxa.
set -euo pipefail

RELEASE="${RELEASE:-gxa}"
ENV="${ENV:-test}"
CTX_PATH="/gxa"

NODE_HOSTNAME="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"
INGRESS_PORT="$(kubectl get service ingress-nginx-ingress-controller-http \
  --namespace ingress \
  -o jsonpath='{.spec.ports[0].nodePort}')"
echo "http://${NODE_HOSTNAME}:${INGRESS_PORT}${CTX_PATH}/json/experiments"
