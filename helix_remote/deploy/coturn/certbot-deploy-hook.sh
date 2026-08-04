#!/bin/sh
# Publishes the Let's Encrypt certificate to the TURN server and restarts
# it so the new certificate takes effect.
#
# Run once by hand to enable turns:, then install it as a certbot deploy
# hook so renewals stay picked up:
#
#   sudo cp deploy/coturn/certbot-deploy-hook.sh \
#       /etc/letsencrypt/renewal-hooks/deploy/helix-turn.sh
#   sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/helix-turn.sh
#
# Why copy instead of mounting /etc/letsencrypt into the container: the
# private key there is root-owned 0600, so coturn would have to run as
# root to read it. Copying to a directory owned by coturn's own uid keeps
# the internet-facing relay unprivileged.
set -eu

DOMAIN=${TURN_DOMAIN:-hr.agiletechbd.com}
PROJECT_DIR=${HELIX_PROJECT_DIR:-/opt/helix-remote/helix_remote}
DEST=${TURN_CERT_DIR:-$PROJECT_DIR/turn-certs}

# uid/gid coturn runs as inside the official image.
TURN_UID=${TURN_UID:-65534}
TURN_GID=${TURN_GID:-65534}

SRC=/etc/letsencrypt/live/$DOMAIN

if [ ! -f "$SRC/fullchain.pem" ]; then
    echo "No certificate at $SRC - issue one with certbot first." >&2
    exit 1
fi

mkdir -p "$DEST"
# Follow the symlinks in live/ so the container gets real files and needs
# no access to /etc/letsencrypt/archive.
cp -L "$SRC/fullchain.pem" "$DEST/fullchain.pem"
cp -L "$SRC/privkey.pem" "$DEST/privkey.pem"

chown "$TURN_UID:$TURN_GID" "$DEST/fullchain.pem" "$DEST/privkey.pem"
chmod 0644 "$DEST/fullchain.pem"
chmod 0600 "$DEST/privkey.pem"

echo "TURN certificates published to $DEST"

# coturn reads its certificate once at startup, so a renewed certificate
# only takes effect after a restart.
if command -v docker >/dev/null 2>&1; then
    cd "$PROJECT_DIR" && docker compose restart helix-turn
    echo "Restarted helix-turn"
else
    echo "docker not found - restart the helix-turn container yourself." >&2
fi
