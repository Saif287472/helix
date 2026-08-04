#!/bin/sh
# Renders deploy/coturn/turnserver.conf into a real config and starts
# coturn with it.
#
# Why render at all: coturn's config format has no variable interpolation,
# and the alternative - passing --static-auth-secret on the command line -
# puts the shared secret into the container's argv, where `docker inspect`
# and the host's process list both expose it. Rendering into a tmpfs keeps
# it off disk and out of argv.
set -eu

TEMPLATE=/etc/coturn/turnserver.conf.template
RENDERED=/tmp/turnserver.conf
CERT_DIR=${TURN_CERT_DIR:-/etc/coturn/certs}

if [ -z "${HELIX_REMOTE_TURN_SECRET:-}" ]; then
    echo "FATAL: HELIX_REMOTE_TURN_SECRET is not set." >&2
    echo "Generate one with: openssl rand -hex 32" >&2
    echo "It must be identical to the backend's HELIX_REMOTE_TURN_SECRET." >&2
    exit 1
fi

if [ -z "${TURN_REALM:-}" ]; then
    echo "FATAL: TURN_REALM is not set (e.g. hr.agiletechbd.com)." >&2
    exit 1
fi

# TLS is opt-in: without certificates present, coturn still serves plain
# TURN on 3478, which is enough for calls to work. The template's cert
# lines resolve to empty and get dropped below.
if [ -f "$CERT_DIR/fullchain.pem" ] && [ -f "$CERT_DIR/privkey.pem" ]; then
    TURN_CERT_FILE="$CERT_DIR/fullchain.pem"
    TURN_PKEY_FILE="$CERT_DIR/privkey.pem"
    if [ ! -r "$TURN_PKEY_FILE" ]; then
        echo "FATAL: $TURN_PKEY_FILE exists but is not readable by uid $(id -u)." >&2
        echo "Re-run deploy/coturn/certbot-deploy-hook.sh to fix ownership." >&2
        exit 1
    fi
    echo "TURN: TLS enabled, serving turns: on 5349."
else
    TURN_CERT_FILE=""
    TURN_PKEY_FILE=""
    echo "TURN: no certificates in $CERT_DIR - serving plain turn: on 3478 only."
    echo "TURN: run deploy/coturn/certbot-deploy-hook.sh to enable turns:."
fi

# Substitution is done with a here-doc-free sed so the secret is never
# passed as an argument to another process either.
export TURN_CERT_FILE TURN_PKEY_FILE
TURN_EXTERNAL_IP=${TURN_EXTERNAL_IP:-}
export TURN_EXTERNAL_IP

umask 077
: > "$RENDERED"

while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        *'${TURN_SECRET}'*)
            value=$HELIX_REMOTE_TURN_SECRET
            key=${line%%=*}
            ;;
        *'${TURN_REALM}'*)
            value=$TURN_REALM
            key=${line%%=*}
            ;;
        *'${TURN_EXTERNAL_IP}'*)
            value=$TURN_EXTERNAL_IP
            key=${line%%=*}
            ;;
        *'${TURN_CERT_FILE}'*)
            value=$TURN_CERT_FILE
            key=${line%%=*}
            ;;
        *'${TURN_PKEY_FILE}'*)
            value=$TURN_PKEY_FILE
            key=${line%%=*}
            ;;
        *)
            printf '%s\n' "$line" >> "$RENDERED"
            continue
            ;;
    esac
    # An unset optional value means "leave the setting out entirely" -
    # coturn rejects a bare `external-ip=` with no argument.
    if [ -n "$value" ]; then
        printf '%s=%s\n' "$key" "$value" >> "$RENDERED"
    fi
done < "$TEMPLATE"

# With no certificate there is nothing to serve TLS with. Drop the
# listener and its options, and turn TLS/DTLS off explicitly - otherwise
# coturn falls back to looking for its default turn_server_cert.pem and
# logs four warnings about not finding it on every start.
if [ -z "$TURN_CERT_FILE" ]; then
    grep -vE '^(no-tlsv1|tls-listening-port)' "$RENDERED" > "$RENDERED.tmp"
    mv "$RENDERED.tmp" "$RENDERED"
    printf 'no-tls\nno-dtls\n' >> "$RENDERED"
fi

exec turnserver -c "$RENDERED"
