#!/bin/bash
# =============================================================
# loadgen.sh — continuous load generator for dynatrace-demo.
#
# Runs as the systemd service "dynatrace-demo-loadgen". Every second it
# sends a share of REQUESTS_PER_MIN requests to the app; ERROR_PCT % of
# them go to /error and the rest to /normal.
#
# Steady-state settings: /etc/default/dynatrace-demo-loadgen (re-read
# every second, so changes apply without a restart).
# Error spikes: "dtdemo-load spike ..." writes a spike file that
# overrides the settings until it expires.
# =============================================================
set -uo pipefail

CONF="${LOADGEN_CONF:-/etc/default/dynatrace-demo-loadgen}"
STATE_DIR="${LOADGEN_STATE_DIR:-/var/lib/dynatrace-demo-loadgen}"
SPIKE_FILE="${STATE_DIR}/spike"
STATUS_FILE="${STATE_DIR}/status"

is_int() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }

load_conf() {
  BASE_URL="http://localhost:8080"
  REQUESTS_PER_MIN=60
  ERROR_PCT=2
  # shellcheck disable=SC1090
  [[ -r "${CONF}" ]] && . "${CONF}"
  is_int "${REQUESTS_PER_MIN}" || REQUESTS_PER_MIN=60
  is_int "${ERROR_PCT}" || ERROR_PCT=2
  (( ERROR_PCT > 100 )) && ERROR_PCT=100
}

trap 'echo "loadgen stopping"; exit 0' TERM INT

acc=0                 # carries fractional requests between ticks
win_start=$(date +%s) # start of the current 60s stats window
ok=0; err=0; fail=0
last_ok=0; last_err=0; last_fail=0
prev_mode=""

echo "loadgen starting (config: ${CONF}, state: ${STATE_DIR})"

while true; do
  tick_start=$(date +%s%N)
  now=$(( tick_start / 1000000000 ))
  load_conf

  # --- current mode: baseline, or spike while the spike file is valid ---
  mode="baseline"; rpm=${REQUESTS_PER_MIN}; pct=${ERROR_PCT}; left=0
  if [[ -r "${SPIKE_FILE}" ]]; then
    read -r s_end s_pct s_rpm < "${SPIKE_FILE}" || true
    if is_int "${s_end:-}" && is_int "${s_pct:-}" && is_int "${s_rpm:-}" && (( s_end > now )); then
      mode="spike"; rpm=${s_rpm}; pct=${s_pct}; left=$(( s_end - now ))
      (( pct > 100 )) && pct=100
    fi
  fi
  if [[ "${mode}" != "${prev_mode}" ]]; then
    if [[ "${mode}" == "spike" ]]; then
      echo "SPIKE started: ${rpm} req/min, ${pct}% errors, ${left}s remaining"
    else
      echo "BASELINE: ${rpm} req/min, ${pct}% errors"
    fi
    prev_mode=${mode}
  fi

  # --- send this tick's requests (one curl process, keep-alive) ---
  acc=$(( acc + rpm )); n=$(( acc / 60 )); acc=$(( acc % 60 ))
  if (( n > 0 )); then
    args=()
    for (( i = 0; i < n; i++ )); do
      if (( RANDOM % 100 < pct )); then path=/error; else path=/normal; fi
      args+=(-o /dev/null "${BASE_URL}${path}")
    done
    while read -r code; do
      case "${code}" in
        2*) ok=$(( ok + 1 )) ;;
        5*) err=$(( err + 1 )) ;;
        *)  fail=$(( fail + 1 )) ;;
      esac
    done < <(curl -s --connect-timeout 2 --max-time 5 -w '%{http_code}\n' "${args[@]}" 2>/dev/null)
  fi

  # --- once a minute: log and roll the stats window ---
  if (( now - win_start >= 60 )); then
    echo "last 60s [${mode}]: ok=${ok} errors=${err} unreachable=${fail}"
    (( fail > 0 && ok == 0 && err == 0 )) && echo "WARNING: app not reachable at ${BASE_URL}"
    last_ok=${ok}; last_err=${err}; last_fail=${fail}
    ok=0; err=0; fail=0; win_start=${now}
  fi

  # --- status for "dtdemo-load status" ---
  if [[ -d "${STATE_DIR}" && -w "${STATE_DIR}" ]]; then
    cat > "${STATUS_FILE}.tmp" <<STATUS
updated=${now}
mode=${mode}
target_url=${BASE_URL}
requests_per_min=${rpm}
error_pct=${pct}
spike_seconds_left=${left}
last_min_ok=${last_ok}
last_min_errors=${last_err}
last_min_unreachable=${last_fail}
current_min_ok=${ok}
current_min_errors=${err}
current_min_unreachable=${fail}
STATUS
    mv -f "${STATUS_FILE}.tmp" "${STATUS_FILE}"
  fi

  # --- sleep out the rest of the 1s tick ---
  elapsed_ms=$(( ( $(date +%s%N) - tick_start ) / 1000000 ))
  if (( elapsed_ms < 1000 )); then
    sleep "$(printf '0.%03d' $(( 1000 - elapsed_ms )))"
  fi
done
