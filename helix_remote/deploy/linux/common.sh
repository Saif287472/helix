# Shared helpers for the Helix ops scripts (sourced, not run).
# shellcheck shell=bash

HELIX_HOME=${HELIX_HOME:-/opt/helix}
HELIX_ENV_FILE=${HELIX_ENV_FILE:-$HELIX_HOME/.env}

# The value of KEY in the server's .env (last matching line wins, as the server
# reads it; surrounding quotes removed). The file is never sourced: a stray
# `$(...)` in a value must not run. Prints nothing when the key is absent.
env_value() {
    local key=$1 line
    [ -r "$HELIX_ENV_FILE" ] || return 0
    line=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$HELIX_ENV_FILE" | tail -n 1) || true
    [ -n "$line" ] || return 0
    line=${line#*=}
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    case $line in
        \"*\") line=${line#\"}; line=${line%\"} ;;
        \'*\') line=${line#\'}; line=${line%\'} ;;
    esac
    printf '%s' "$line"
}

# A setting: the process environment wins, then the server's .env.
setting() {
    local key=$1 value=${!1:-}
    if [ -n "$value" ]; then printf '%s' "$value"; else env_value "$key"; fi
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Plain-text POST (an alert) or GET (a heartbeat) to an off-box URL; failures
# are ignored so a dead alert service never breaks the job that calls it.
notify_post() { [ -n "${1:-}" ] && curl -fsS -m 10 -X POST --data-binary "$2" "$1" >/dev/null 2>&1 || true; }
notify_get() { [ -n "${1:-}" ] && curl -fsS -m 10 "$1" >/dev/null 2>&1 || true; }
