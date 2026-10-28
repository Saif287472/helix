#!/usr/bin/env bash
# One-time setup of a Helix Global VM (Ubuntu 22.04+/Debian 12+), run as root
# from this folder:  sudo ./install.sh [--domain helix.example.com]
#
# It does the parts that are safe to automate and says what it did:
#   - the `helix` user, /opt/helix (bin, ops, releases, logs), /var/lib/helix/blobs,
#     /var/backups/helix and /etc/helix
#   - copies the ops scripts and installs the systemd units and timers
#   - the PostgreSQL role and database `helix` (role with CREATEDB for the drill),
#     listening on this machine only
#   - the firewall (ufw): SSH, HTTPS and HTTP (certificates), the TURN ports
#   - enables the backup, health and drill timers
# It does NOT install packages from third-party repositories. Install first:
#   PostgreSQL 17 (apt.postgresql.org), Caddy (caddyserver.com/docs/install),
#   Docker (for coturn), age, rclone, rsync, curl, ufw, openssl.
# It does NOT create or print any secret. Put the server's .env in
# /opt/helix/.env (mode 600, owner helix): copy the one from the PC when moving
# (docs/operations/VM_MIGRATION.md), or write a new one from server/.env.example.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run as root (sudo)." >&2; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
domain=
while [ $# -gt 0 ]; do
    case $1 in --domain) domain=$2; shift ;; *) echo "unknown option $1" >&2; exit 1 ;; esac
    shift
done

missing=()
for tool in psql pg_dump pg_restore caddy docker age rsync curl ufw openssl; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [ "${#missing[@]}" -gt 0 ]; then
    echo "Install these first: ${missing[*]}" >&2
    echo "(PostgreSQL 17 from apt.postgresql.org, Caddy and Docker from their own repositories.)" >&2
    exit 1
fi
pgver=$(psql --version | sed -E 's/[^0-9]*([0-9]+).*/\1/')
[ "$pgver" -ge 17 ] || { echo "PostgreSQL 17 or newer is required (found $pgver)." >&2; exit 1; }

echo "== user and folders"
id helix >/dev/null 2>&1 || useradd --system --home-dir /opt/helix --shell /usr/sbin/nologin helix
install -d -o helix -g helix -m 750 /opt/helix /opt/helix/bin /opt/helix/ops /opt/helix/releases /opt/helix/logs
install -d -o helix -g helix -m 700 /var/lib/helix /var/lib/helix/blobs /var/backups/helix
install -d -o root -g helix -m 750 /etc/helix
[ -e /etc/helix/backup.env ] || install -o root -g helix -m 640 "$here/backup.env.example" /etc/helix/backup.env

echo "== ops scripts and units"
for f in common.sh backup-helix.sh health-check.sh restore-drill.sh deploy.sh release.sh; do
    install -o root -g helix -m 755 "$here/$f" /opt/helix/ops/"$f"
done
for unit in helix-server.service helix-backup.service helix-backup.timer helix-health.service helix-health.timer helix-drill.service helix-drill.timer; do
    install -o root -g root -m 644 "$here/$unit" /etc/systemd/system/"$unit"
done
systemctl daemon-reload

echo "== PostgreSQL role and database (local only)"
sudo -u postgres psql -qtAc "SELECT 1 FROM pg_roles WHERE rolname='helix'" | grep -q 1 \
    || sudo -u postgres psql -q -c "CREATE ROLE helix LOGIN CREATEDB"
sudo -u postgres psql -qtAc "SELECT 1 FROM pg_database WHERE datname='helix'" | grep -q 1 \
    || sudo -u postgres createdb -O helix helix
echo "The role has no password yet. Set it, and put the same one in HELIX_DATABASE_URL in /opt/helix/.env:"
echo "    sudo -u postgres psql -c \"ALTER ROLE helix PASSWORD '<a long random password>'\""
echo "(The ops scripts connect by the local socket as the helix user, no password.)"
listen=$(sudo -u postgres psql -qtAc "SHOW listen_addresses")
case $listen in localhost|127.0.0.1|"localhost,127.0.0.1"|"127.0.0.1,::1"|"localhost,::1") ;;
    *) echo "WARNING: PostgreSQL listen_addresses is '$listen'. Set it to 'localhost' in postgresql.conf and restart." >&2 ;;
esac

echo "== firewall"
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp comment 'HTTP (certificates)' >/dev/null
ufw allow 443/tcp comment 'HTTPS' >/dev/null
ufw allow 3478 comment 'TURN' >/dev/null
ufw allow 3479 comment 'TURN voice' >/dev/null
ufw allow 49160:49800/udp comment 'TURN relay ranges' >/dev/null
echo "Postgres (5432) and the server (8080) stay closed. Enable the firewall when SSH access is confirmed:  ufw enable"

echo "== timers"
systemctl enable --now helix-backup.timer helix-health.timer helix-drill.timer >/dev/null
systemctl enable helix-server >/dev/null
echo
echo "Done. Next:"
echo "  1. /opt/helix/.env (mode 600, owner helix) -- see VM_MIGRATION.md"
echo "  2. /etc/helix/backup.env: HELIX_OFFSITE, HELIX_AGE_RECIPIENT, HELIX_ALERT_URL, HELIX_HEARTBEAT_URL"
echo "  3. a release: copy releases/<tag> to /opt/helix/releases and run /opt/helix/ops/deploy.sh <tag>"
echo "  4. Caddy: ${domain:+$domain, }see Caddyfile.example;  coturn: docker compose (deploy/linux/README.md)"
