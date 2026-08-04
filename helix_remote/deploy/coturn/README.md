# TURN relay (coturn), co-hosted with the backend

WebRTC calls need a relay whenever the two parties can't reach each other
directly. On mobile carrier networks that's the common case, not the
exception, so without TURN a call between two phones typically rings and
then fails to connect. The admin console shows this as **TURN Server
Configured: DISABLED** on the Config screen.

This directory runs coturn on the same VPS as the backend. At a couple of
dozen users that is the right call - relayed audio is roughly 50 kbit/s
each way per participant, so even a handful of simultaneous calls is a
rounding error against a VPS's bandwidth.

## How the credentials work

There are no user accounts on the TURN server. The backend mints
short-lived credentials on demand (`GET /api/v1/calls/turn-credentials`)
using a shared secret:

- username: `<unix-expiry>:<account-id>:<device-id>`, valid one hour
- password: `base64(HMAC-SHA1(secret, username))`

coturn's `use-auth-secret` mode verifies exactly that construction, which
is why the two sides only need to agree on one value:
`HELIX_REMOTE_TURN_SECRET`. The backend rate-limits issuance per account
and per device, so a stolen credential also expires on its own.

## Setup

All commands run from the repo root on the VPS
(`/opt/helix-remote/helix_remote`).

### 1. Fill in the environment

In `.env`:

```sh
# One secret, shared by both services.
openssl rand -hex 32
```

```ini
HELIX_REMOTE_TURN_URL=turn:hr.agiletechbd.com:3478,turns:hr.agiletechbd.com:5349
HELIX_REMOTE_TURN_SECRET=<the value you just generated>
TURN_REALM=hr.agiletechbd.com
TURN_EXTERNAL_IP=157.250.207.166
```

`TURN_EXTERNAL_IP` is the VPS's public IPv4 address. Getting it wrong is
the single most common cause of "the call connects but there's no audio":
clients are handed a relay address they can't reach.

### 2. Open the firewall

The backend is deliberately not exposed directly (nginx proxies it), but
TURN has to be reachable from the internet:

```sh
sudo ufw allow 3478/tcp comment 'TURN'
sudo ufw allow 3478/udp comment 'TURN'
sudo ufw allow 5349/tcp comment 'TURN over TLS'
sudo ufw allow 5349/udp comment 'TURN over TLS'
sudo ufw allow 49160:49200/udp comment 'TURN relay range'
sudo ufw status
```

The relay range must match `min-port`/`max-port` in `turnserver.conf`.
40 ports covers roughly 40 concurrent relayed streams; widen both
together if you outgrow it.

### 3. Start it

```sh
docker compose up -d helix-turn
docker compose logs -f helix-turn
```

Expect `TURN: no certificates in /etc/coturn/certs - serving plain turn:
on 3478 only.` on the first run. Calls work at this point.

### 4. Enable TLS (turns:), recommended

`turns:` on 5349 looks like ordinary HTTPS traffic, so it gets through
restrictive networks that block UDP outright. It reuses the same Let's
Encrypt certificate nginx already has:

```sh
sudo TURN_DOMAIN=hr.agiletechbd.com deploy/coturn/certbot-deploy-hook.sh
```

Then install it as a renewal hook so it survives certificate renewals -
coturn only reads its certificate at startup, so a renewed certificate
does nothing until the container restarts:

```sh
sudo cp deploy/coturn/certbot-deploy-hook.sh \
    /etc/letsencrypt/renewal-hooks/deploy/helix-turn.sh
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/helix-turn.sh
```

The hook copies the certificate to `./turn-certs/` owned by coturn's uid
rather than mounting `/etc/letsencrypt` into the container. That's on
purpose: the private key in `archive/` is root-only, so a mount would
force this internet-facing relay to run as root.

### 5. Restart the backend and confirm

The backend reads the TURN settings at startup:

```sh
docker compose up -d helix-backend
```

The admin console's Config screen should now show **TURN Server
Configured: ENABLED**, and the Logs screen should no longer carry the
`HELIX_REMOTE_TURN_URL or HELIX_REMOTE_TURN_SECRET is not set` warning.

## Verifying it actually relays

Config saying ENABLED only means the backend has a URL and a secret. To
check the relay itself answers, fetch a credential as a logged-in user
and test it at https://icetest.info or with `turnutils_uclient`:

```sh
docker compose exec helix-turn turnutils_uclient \
    -T -u "$(date -d '+1 hour' +%s):smoketest" \
    -w "$(printf '%s' "$(date -d '+1 hour' +%s):smoketest" \
        | openssl dgst -sha1 -hmac "$HELIX_REMOTE_TURN_SECRET" -binary \
        | base64)" \
    hr.agiletechbd.com
```

A successful run prints allocation results rather than `401`. A `401`
means the secret in `.env` and the one coturn loaded have drifted apart -
restart `helix-turn` after any change to it.

## Security notes

`turnserver.conf` denies relaying to every private, loopback,
link-local and reserved address range. This matters more than usual
here: with host networking an unrestricted relay could reach the
backend on `127.0.0.1:8080` directly, bypassing nginx, TLS and the rate
limiter, and could reach a cloud metadata endpoint at
`169.254.169.254`. Don't remove those `denied-peer-ip` lines to "fix"
a connectivity problem - if a legitimate peer is being denied, it is on
a public address and something else is wrong.

The shared secret is never passed on coturn's command line and never
written to disk. `entrypoint.sh` renders the config into a tmpfs mount
at container start, so `docker inspect`, the host process list, and the
container's writable layer all stay clean.
