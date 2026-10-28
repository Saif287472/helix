#!/usr/bin/env bash
# Switches Helix Global to a release in /opt/helix/releases/<tag> (copied from
# release.sh): checks the hashes, takes a backup, stops the server gracefully,
# swaps the executables, migrates, starts, checks /v1/health/ready. If the
# migration fails the previous version is put back.
#
#   sudo /opt/helix/ops/deploy.sh <tag> [--skip-backup]
#
# Run as root (it stops and starts the service); the files stay owned by helix.
set -euo pipefail
tag=${1:?usage: deploy.sh <tag> [--skip-backup]}; shift || true
skip_backup=0; [ "${1:-}" = --skip-backup ] && skip_backup=1
HOME_DIR=${HELIX_HOME:-/opt/helix}
release=$HOME_DIR/releases/$tag
bin=$HOME_DIR/bin; prev=$HOME_DIR/bin-previous
port=$(grep -E '^[[:space:]]*HELIX_PORT[[:space:]]*=' "$HOME_DIR/.env" 2>/dev/null | tail -n 1 | sed 's/.*=[[:space:]]*//' | tr -d "\"' ")
port=${port:-8080}

for exe in helix-server helix-migrate helix-admin-tool; do
    [ -x "$release/$exe" ] || { echo "$release has no $exe. Build it with release.sh." >&2; exit 1; }
    want=$(sed -n "s/^sha256-$exe=//p" "$release/VERSION" 2>/dev/null)
    [ -n "$want" ] || { echo "$release/VERSION has no hash for $exe. Build the release again." >&2; exit 1; }
    have=$(sha256sum "$release/$exe" | cut -d' ' -f1)
    [ "$have" = "$want" ] || { echo "$exe in $release is not the file that was built (hash differs). Nothing was changed." >&2; exit 1; }
done
[ -r "$HOME_DIR/.env" ] || { echo "No $HOME_DIR/.env." >&2; exit 1; }

if [ "$skip_backup" != 1 ]; then
    echo "Taking a backup before the deploy..."
    sudo -u helix "$HOME_DIR/ops/backup-helix.sh" || { echo "The backup failed. Nothing was changed; fix it, or deploy with --skip-backup." >&2; exit 1; }
fi

echo "Stopping the server (graceful)..."
systemctl stop helix-server
if [ -d "$bin" ]; then rm -rf "$prev"; mv "$bin" "$prev"; fi
mkdir -p "$bin"
cp "$release"/helix-server "$release"/helix-migrate "$release"/helix-admin-tool "$release"/VERSION "$bin"/
chown -R helix:helix "$bin"

echo "Migrating..."
if ! (cd "$HOME_DIR" && sudo -u helix "$bin/helix-migrate"); then
    echo "Migration failed; putting the previous version back." >&2
    if [ -d "$prev" ]; then rm -rf "$bin"; mv "$prev" "$bin"; fi
    systemctl start helix-server || true
    echo "Deploy failed at the migration; the previous version is running again." >&2
    exit 1
fi

systemctl start helix-server
for _ in $(seq 1 60); do
    if curl -fs -m 5 "http://127.0.0.1:$port/v1/health/ready" >/dev/null; then
        echo "Helix Global is running $tag and ready."
        exit 0
    fi
    sleep 2
done
echo "Not ready after 120 s. Look at: journalctl -u helix-server -n 100" >&2
echo "To go back: sudo /opt/helix/ops/deploy.sh <previous tag>  (or: mv $bin $bin.bad; mv $prev $bin; systemctl restart helix-server)" >&2
exit 1
