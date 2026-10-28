#!/usr/bin/env bash
# Restore drill: restores the newest dump into a throwaway database
# (helix_drill), starts one server node on it on 127.0.0.1:8090, checks
# /v1/health/ready, then removes everything again. Run monthly by
# helix-drill.timer; the result is appended to <backup dir>/drill.log, which the
# health check watches.
#
# The drill node cannot reach the real world: its database name is fixed, queued
# jobs are emptied before it starts, push, SMS and federation are off, it listens
# on loopback on its own port with throwaway JWT keys and its own blob folder.
# The settings are the server's own (.env) except for those; a setting that would
# stop production starting also fails the drill. The production server is not
# touched and may keep running.
#
# Needs: the `helix` role with CREATEDB (install.sh grants it), and age plus
# HELIX_AGE_IDENTITY (a private key file) to drill from a .age dump instead.
#   ./restore-drill.sh [dump-file]
set -uo pipefail
umask 077
# shellcheck source=common.sh
. "$(dirname "$(readlink -f "$0")")/common.sh"

BACKUP_DIR=$(setting HELIX_BACKUP_DIR); BACKUP_DIR=${BACKUP_DIR:-/var/backups/helix}
PORT=${HELIX_DRILL_PORT:-8090}
DRILL_DB=helix_drill
SERVER=${HELIX_SERVER_BIN:-$HELIX_HOME/bin/helix-server}
MIGRATE=${HELIX_MIGRATE_BIN:-$HELIX_HOME/bin/helix-migrate}
work=$(mktemp -d /tmp/helix-drill.XXXXXX)
node_pid=
passed=0
detail=

drill_log() { printf '%s %s %s\n' "$(date -Iseconds)" "$1" "$2" >>"$BACKUP_DIR/drill.log"; }
cleanup() {
    [ -n "$node_pid" ] && kill "$node_pid" 2>/dev/null && wait "$node_pid" 2>/dev/null
    dropdb --if-exists --force "$DRILL_DB" 2>/dev/null || echo "Could not drop $DRILL_DB; drop it yourself: dropdb --force $DRILL_DB" >&2
    rm -rf "$work"
}
trap cleanup EXIT

dump=${1:-}
if [ -z "$dump" ]; then
    dump=$(find "$BACKUP_DIR/db" -maxdepth 1 -name 'helix-*.dump' | sort | tail -n 1)
fi
if [ -z "$dump" ] || [ ! -r "$dump" ]; then
    drill_log FAIL "no dump to restore in $BACKUP_DIR/db"
    echo "No dump found." >&2; exit 1
fi
label=$(basename "$dump")
case $dump in
    *.age)
        identity=$(setting HELIX_AGE_IDENTITY)
        [ -r "$identity" ] || { drill_log FAIL "$label needs HELIX_AGE_IDENTITY"; echo "Set HELIX_AGE_IDENTITY to the age key file." >&2; exit 1; }
        age --decrypt --identity "$identity" --output "$work/restored.dump" "$dump" || { drill_log FAIL "$label could not be decrypted"; exit 1; }
        dump=$work/restored.dump ;;
esac

dburl=$(env_value HELIX_DATABASE_URL)
if [ -z "$dburl" ]; then drill_log FAIL "HELIX_DATABASE_URL is not in $HELIX_ENV_FILE"; exit 1; fi
drill_url=$(printf '%s' "$dburl" | sed -E 's#(/)helix(\?|$)#\1helix_drill\2#')

dropdb --if-exists --force "$DRILL_DB" 2>/dev/null
if ! createdb "$DRILL_DB" 2>"$work/err"; then
    detail="could not create $DRILL_DB: $(head -n 1 "$work/err")"
elif ! pg_restore --no-owner --exit-on-error -d "$DRILL_DB" "$dump" 2>"$work/err"; then
    detail="pg_restore failed: $(head -n 1 "$work/err")"
else
    # Nothing queued may reach the real world.
    psql -q -d "$DRILL_DB" -c 'TRUNCATE platform.jobs' 2>/dev/null || true
    mkdir -p "$work/blobs"
    key=$(head -c 32 /dev/urandom | base64 -w0 | tr '+/' '-_' | tr -d '=')
    overrides=(
        "HELIX_DATABASE_URL=$drill_url" "HELIX_HOST=127.0.0.1" "HELIX_PORT=$PORT"
        "HELIX_PUBLIC_BASE_URL=http://127.0.0.1:$PORT" "HELIX_NODE_ID=restore-drill-$$"
        "HELIX_TOPOLOGY=single_host" "HELIX_BLOB_STORE=local" "HELIX_BLOB_DIR=$work/blobs"
        "HELIX_LOG_FILE=$work/server.log" "HELIX_DB_POOL_SIZE=4"
        "HELIX_JWT_KEYS={\"drill\":\"$key\"}" "HELIX_JWT_ACTIVE_KID=drill"
        "HELIX_PUSH_PROVIDER=none" "HELIX_SMS_PROVIDER=none" "HELIX_GLOBAL_MODE=false"
        "HELIX_FEDERATION_ENABLED=false"
    )
    # The server's own .env supplies the rest (the pepper and the like).
    if (cd "$HELIX_HOME" && env "${overrides[@]}" "$MIGRATE" >"$work/migrate.log" 2>&1); then
        (cd "$HELIX_HOME" && exec env "${overrides[@]}" "$SERVER" >"$work/stdout.log" 2>"$work/stderr.log") &
        node_pid=$!
        for _ in $(seq 1 90); do
            kill -0 "$node_pid" 2>/dev/null || break
            body=$(curl -s -m 5 -w '\n%{http_code}' "http://127.0.0.1:$PORT/v1/health/ready" || true)
            if [ "$(printf '%s' "$body" | tail -n 1)" = 200 ]; then
                passed=1; detail="ready: $(printf '%s' "$body" | head -n 1)"; break
            fi
            sleep 2
        done
        if [ "$passed" != 1 ]; then
            kill -0 "$node_pid" 2>/dev/null && detail="not ready within 180 s" || detail="the drill node exited"
            tail -n 15 "$work/stdout.log" "$work/stderr.log" 2>/dev/null
        fi
    else
        detail="migrate failed: $(tail -n 1 "$work/migrate.log")"
    fi
fi

if [ "$passed" = 1 ]; then
    drill_log PASS "$label $detail"
    echo "Drill passed: $label restored, migrated and served /v1/health/ready."
    exit 0
fi
drill_log FAIL "$label $detail"
echo "Drill FAILED: $detail" >&2
exit 1
