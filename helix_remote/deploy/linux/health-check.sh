#!/usr/bin/env bash
# Health of Orbit Home, every 5 minutes (helix-health.timer): tells you when
# something changes, on the journal, and, off the VM, at HELIX_ALERT_URL.
#
# Checks: the server answers /v1/health/ready; the services run (helix-server,
# postgresql, caddy, the coturn containers); disk space; with HELIX_METRICS_TOKEN,
# dead jobs and the mailbox backlog; the newest backup is under 36 hours old, the
# last backup run did not end WITH ERRORS, a restore drill passed in the last 45
# days; the public certificate has more than 14 days left; PostgreSQL does not
# answer on a public address.
#
# Off-box (settings in /opt/helix/.env or /etc/helix/backup.env; none is read by
# the server):
#   HELIX_HEARTBEAT_URL  pinged on every healthy run (healthchecks.io and the
#                        like: when the pings stop, that service tells you, even
#                        when the whole VM is down)
#   HELIX_ALERT_URL      plain-text POST on every change (ntfy.sh...), keep it private
# Exit 0 healthy, 1 not.
set -uo pipefail
# shellcheck source=common.sh
. "$(dirname "$(readlink -f "$0")")/common.sh"

PORT=$(setting HELIX_PORT); PORT=${PORT:-8080}
BACKUP_DIR=$(setting HELIX_BACKUP_DIR); BACKUP_DIR=${BACKUP_DIR:-/var/backups/helix}
STATE=${HELIX_HEALTH_STATE:-$HELIX_HOME/health-state.txt}
MIN_FREE=${HELIX_MIN_FREE_PERCENT:-10}
BACKLOG_WARN=${HELIX_BACKLOG_WARN:-50000}
BACKUP_MAX_HOURS=${HELIX_BACKUP_MAX_HOURS:-36}
DRILL_MAX_DAYS=${HELIX_DRILL_MAX_DAYS:-45}
problems=()
add() { problems+=("$1"); }

# 1. Ready.
code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "http://127.0.0.1:$PORT/v1/health/ready" || true)
case $code in
    200) ;;
    000|'') add "The server does not answer." ;;
    *) add "The server is not ready (HTTP $code)." ;;
esac

# 2. Services.
for unit in helix-server postgresql caddy; do
    if systemctl list-unit-files "$unit.service" >/dev/null 2>&1 && \
       systemctl list-unit-files "$unit.service" 2>/dev/null | grep -q "$unit"; then
        systemctl is-active --quiet "$unit" 2>/dev/null || add "The $unit service is not running."
    fi
done
# coturn runs in Docker (docker-compose.yml); the relay ports must be listening
# (UDP 3478 main, 3479 voice), asked of the kernel so this needs no Docker rights.
for p in 3478 3479; do
    if ss -H -lun 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$p$"; then :; else
        [ "$p" = 3479 ] && [ -z "$(setting HELIX_TURN_VOICE_URLS)" ] && continue
        add "coturn is not listening on UDP $p (calls cannot connect)."
    fi
done
n=$(systemctl show -p NRestarts --value helix-server 2>/dev/null || echo 0)
[ "${n:-0}" -ge 5 ] && add "helix-server restarted $n times since it last started (a crash loop: journalctl -u helix-server)."

# 3. Disk.
while read -r pct mount; do
    free=$((100 - ${pct%\%}))
    [ "$free" -lt "$MIN_FREE" ] && add "$mount has $free% free (under $MIN_FREE%)."
done < <(df --output=pcent,target -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | tail -n +2)

# 4. Metrics.
token=$(env_value HELIX_METRICS_TOKEN)
if [ -n "$token" ]; then
    metrics=$(curl -s -m 10 -H "Authorization: Bearer $token" "http://127.0.0.1:$PORT/v1/ops/metrics" || true)
    dead=$(printf '%s\n' "$metrics" | awk '/^helix_jobs_dead/ {s+=$NF} END {print s+0}')
    backlog=$(printf '%s\n' "$metrics" | awk '/^helix_mailbox_backlog/ {s+=$NF} END {print s+0}')
    [ "${dead%.*}" -gt 0 ] && add "$dead background jobs failed for good (dead letters)."
    [ "${backlog%.*}" -gt "$BACKLOG_WARN" ] && add "$backlog undelivered envelopes wait in mailboxes."
fi
token=

# 5. Backups.
if [ -d "$BACKUP_DIR/db" ]; then
    newest=$(find "$BACKUP_DIR/db" -maxdepth 1 -name 'helix-*.dump' -printf '%T@ %p\n' | sort -n | tail -n 1 | cut -d' ' -f1)
    if [ -z "$newest" ]; then
        add "There is no verified database backup in $BACKUP_DIR/db."
    elif [ $(( $(date +%s) - ${newest%.*} )) -gt $((BACKUP_MAX_HOURS * 3600)) ]; then
        add "The newest database backup is older than $BACKUP_MAX_HOURS hours."
    fi
    if [ -r "$BACKUP_DIR/backup.log" ] && tail -n 40 "$BACKUP_DIR/backup.log" | grep ' END ' | tail -n 1 | grep -q 'WITH ERRORS'; then
        add "The last backup run ended with errors (backup.log)."
    fi
    if [ "$DRILL_MAX_DAYS" -gt 0 ]; then
        lastpass=$(grep -E '^[^ ]+ PASS ' "$BACKUP_DIR/drill.log" 2>/dev/null | tail -n 1 | cut -d' ' -f1)
        if [ -z "$lastpass" ]; then
            add "No restore drill has passed yet (restore-drill.sh)."
        elif [ $(( $(date +%s) - $(date -d "$lastpass" +%s 2>/dev/null || echo 0) )) -gt $((DRILL_MAX_DAYS * 86400)) ]; then
            add "The last passing restore drill is older than $DRILL_MAX_DAYS days."
        fi
    fi
elif [ -n "$(setting HELIX_BACKUP_DIR)" ]; then
    add "The backup folder $BACKUP_DIR cannot be reached."
fi

# 6. The certificate people connect with.
base=$(env_value HELIX_PUBLIC_BASE_URL)
host=$(printf '%s' "$base" | sed -n 's#^https://\([^/:]*\).*#\1#p')
if [ -n "$host" ] && [ "$host" != localhost ]; then
    end=$(echo | timeout 8 openssl s_client -servername "$host" -connect "$host:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    if [ -n "$end" ]; then
        days=$(( ($(date -d "$end" +%s) - $(date +%s)) / 86400 ))
        [ "$days" -lt 14 ] && add "The certificate for $host expires in $days days."
    fi
fi

# 7. PostgreSQL must listen on this machine only.
if ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -E ':5432$' | grep -vE '^(127\.|\[::1\]|::1)' | grep -q .; then
    add "PostgreSQL listens beyond this machine (listen_addresses and the firewall should keep it local)."
fi

# Report a change only.
current=$(printf '%s\n' "${problems[@]:-}" | sort)
previous=$(cat "$STATE" 2>/dev/null || true)
printf '%s\n' "$current" >"$STATE"
alert=$(setting HELIX_ALERT_URL)
if [ "$current" != "$previous" ]; then
    if [ "${#problems[@]}" -gt 0 ]; then
        text="Orbit Home needs attention: ${problems[*]}"
        logger -t helix-health -p user.err "$text"
    else
        text="Orbit Home is healthy again."
        logger -t helix-health -p user.info "$text"
    fi
    notify_post "$alert" "$text"
fi
if [ "${#problems[@]}" -eq 0 ]; then
    notify_get "$(setting HELIX_HEARTBEAT_URL)"
    exit 0
fi
exit 1
