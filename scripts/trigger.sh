#!/bin/bash
# =============================================================
# trigger.sh — call the demo endpoints to generate traffic.
#
# Usage:
#   bash scripts/trigger.sh                 # 1x /normal and 1x /error on localhost
#   bash scripts/trigger.sh normal 20       # 20x /normal
#   bash scripts/trigger.sh error 5         # 5x /error
#   bash scripts/trigger.sh mix 50          # 50 requests, ~20% errors
#   bash scripts/trigger.sh loop            # every 2s forever (Ctrl+C to stop), ~20% errors
#
#   BASE_URL=http://10.0.0.5:8080 bash scripts/trigger.sh mix 100   # remote VM
#   DELAY=0.5 bash scripts/trigger.sh loop                          # faster loop
# =============================================================
set -uo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
DELAY="${DELAY:-2}"
MODE="${1:-both}"
COUNT="${2:-1}"

call() {
  local path="$1" code
  code=$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}${path}")
  printf '%s  GET %-8s -> HTTP %s\n' "$(date '+%H:%M:%S')" "${path}" "${code}"
}

random_call() {
  if (( RANDOM % 5 == 0 )); then call /error; else call /normal; fi
}

case "${MODE}" in
  normal) for ((i=0; i<COUNT; i++)); do call /normal; done ;;
  error)  for ((i=0; i<COUNT; i++)); do call /error;  done ;;
  both)   for ((i=0; i<COUNT; i++)); do call /normal; call /error; done ;;
  mix)    for ((i=0; i<COUNT; i++)); do random_call; done ;;
  loop)   while true; do random_call; sleep "${DELAY}"; done ;;
  *) echo "Unknown mode '${MODE}'. Use: normal | error | both | mix | loop" >&2; exit 1 ;;
esac
