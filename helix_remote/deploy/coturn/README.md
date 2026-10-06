# TURN relay (coturn), co-hosted with the server

WebRTC calls need a relay whenever the two parties can't reach each other
directly. On mobile carrier networks that's the common case, not the
exception, so without TURN a call between two phones typically rings and
then fails to connect. Without TURN settings the server answers credential
requests with 503 `unavailable`.

This directory runs coturn next to the Helix server (a VPS with Docker, or a
Windows PC with WSL, below). At a couple of dozen users that is the right call - relayed audio is roughly 50 kbit/s
each way per participant, so even a handful of simultaneous calls is a
rounding error against a VPS's bandwidth.

## How the credentials work

There are no user accounts on the TURN server. The server mints
short-lived credentials on demand (`GET /v1/calls/turn`) using a shared
secret:

- username: `<unix-expiry>:<random id>`, valid one hour (it never names an
  account or a device: on plain `turn:` it crosses the network unencrypted)
- password: `base64(HMAC-SHA1(secret, username))`

coturn's `use-auth-secret` mode verifies exactly that construction, which
is why the two sides only need to agree on one value:
`HELIX_TURN_SECRET`. The server rate-limits issuance per device, so a stolen
credential also expires on its own.

## Setup

All commands run from `helix_remote/` on the VPS
(`/opt/helix-remote/helix_remote`). The compose file only runs coturn; run
the Helix server itself as described in
`docs/operations/V2_SERVER_HANDOFF.md`.

### 1. Fill in the environment

In `server/.env` (compose is started with `--env-file server/.env`, so
coturn and the server read the same secret and cannot drift apart):

```sh
# One secret, shared by both services.
openssl rand -hex 32
```

```ini
HELIX_TURN_URLS=turn:helix.agiletechbd.com:3478?transport=udp,turn:helix.agiletechbd.com:3478?transport=tcp
HELIX_TURN_SECRET=<the value you just generated>
TURN_REALM=helix.agiletechbd.com
TURN_EXTERNAL_IP=<the VPS public IPv4 address>
```

`TURN_EXTERNAL_IP` is the VPS's public IPv4 address. Getting it wrong is
the single most common cause of "the call connects but there's no audio":
clients are handed a relay address they can't reach.

### 2. Open the firewall

The server is deliberately not exposed directly (Caddy or another reverse
proxy fronts it), but TURN has to be reachable from the internet:

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
docker compose --env-file server/.env up -d helix-turn
docker compose logs -f helix-turn
```

Expect `TURN: no certificates in /etc/coturn/certs - serving plain turn:
on 3478 only.` on the first run. Calls work at this point.

### 4. Enable TLS (turns:), optional

Calls work without this step, over plain `turn:` on 3478 (the media itself
is always end-to-end encrypted; plain `turn:` only exposes the handshake
and the fact that an address is calling). `turns:` on 5349 hides that and
looks like ordinary HTTPS traffic, so it also gets through restrictive
networks that block UDP outright. It needs a certificate for the host in
the URL (this example reuses a Let's Encrypt certificate that already
exists on the VPS):

```sh
sudo TURN_DOMAIN=helix.agiletechbd.com deploy/coturn/certbot-deploy-hook.sh
```

Then add a `turns:` entry to `HELIX_TURN_URLS`, for example
`turns:helix.agiletechbd.com:5349?transport=tcp`, and restart the server.
Until the certificate is in place leave `turns:` out: a URL that cannot
connect only slows calls down.

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

### 5. Restart the server and confirm

The server reads the TURN settings at startup (Ctrl+C, then
`dart run bin/server.dart` in `server/`). An authenticated
`GET /v1/calls/turn` should now return credentials instead of 503
`unavailable`.

## Windows home PC (behind a router)

Helix Global runs on a Windows PC rather than a VPS. coturn has
no native Windows build, so `windows/start-turn.ps1` runs it in WSL1 (which
shares Windows' network stack) using the same template and entrypoint as
above. The router is what makes this different from the VPS: coturn listens
on the PC's LAN address and advertises the router's public one.

### One-time setup

1. **Install coturn in WSL:** `wsl -d Ubuntu -u root -- apt install -y coturn`.
2. **Give the PC a fixed LAN address** (a DHCP reservation in the router),
   because the port forwards below point at it.
3. **Forward on the router** to that LAN address: UDP 3478, TCP 3478, and
   UDP 49160-49200 (the relay range in `turnserver.conf`).
4. **Allow them through Windows Firewall** (elevated PowerShell):

   ```powershell
   New-NetFirewallRule -DisplayName 'Helix TURN (UDP)' -Direction Inbound -Protocol UDP -LocalPort 3478,49160-49200 -Action Allow
   New-NetFirewallRule -DisplayName 'Helix TURN (TCP)' -Direction Inbound -Protocol TCP -LocalPort 3478 -Action Allow
   ```

5. **Configure the server in `server/.env` only.** The server lets
   Windows environment variables override `.env`, and so does
   `start-turn.ps1`, so remove any `HELIX_TURN_*` user/system environment
   variables - otherwise the server and coturn can end up with different
   secrets.

   ```ini
   HELIX_TURN_URLS=turn:helix.agiletechbd.com:3478?transport=udp,turn:helix.agiletechbd.com:3478?transport=tcp
   HELIX_TURN_SECRET=<openssl rand -hex 32>
   ```

   Restart the server after changing either value.

### Run

```powershell
.\deploy\coturn\windows\start-turn.ps1   # detects public and LAN IP
.\deploy\coturn\windows\stop-turn.ps1
```

The script reads `HELIX_TURN_SECRET` (required) and, for the realm,
`TURN_REALM`, else the host of the first `HELIX_TURN_URLS` entry, else the
host of `HELIX_PUBLIC_BASE_URL`, from the process environment or
`server\.env`. If the server's `.env` is somewhere else, pass
`-EnvFile <path>`. The script never prints the secret and never puts it on a
command line. It serves plain `turn:` on 3478; `turns:` is optional (above)
and is not enabled by this script.

The public IP is detected at each start. A home connection's public IP can
change; when it does, the DNS record and this relay both need the new one -
re-run `start-turn.ps1` after updating DNS.

## Verifying it actually relays

Having the settings only means the server has a URL and a secret. To
check the relay itself answers, fetch a credential as a logged-in user
and test it at https://icetest.info or with `turnutils_uclient`:

```sh
docker compose exec helix-turn turnutils_uclient \
    -T -u "$(date -d '+1 hour' +%s):smoketest" \
    -w "$(printf '%s' "$(date -d '+1 hour' +%s):smoketest" \
        | openssl dgst -sha1 -hmac "$HELIX_TURN_SECRET" -binary \
        | base64)" \
    helix.agiletechbd.com
```

A successful run prints allocation results rather than `401`. A `401`
means the secret in `server/.env` and the one coturn loaded have drifted apart -
restart `helix-turn` after any change to it.

## Security notes

`turnserver.conf` denies relaying to every private, loopback,
link-local and reserved address range. This matters more than usual
here: with host networking an unrestricted relay could reach the
server on `127.0.0.1:8080` directly, bypassing Caddy, TLS and the rate
limiter, and could reach a cloud metadata endpoint at
`169.254.169.254`. Don't remove those `denied-peer-ip` lines to "fix"
a connectivity problem - if a legitimate peer is being denied, it is on
a public address and something else is wrong.

The shared secret is never passed on coturn's command line and never
written to disk. `entrypoint.sh` renders the config into a tmpfs mount
at container start, so `docker inspect`, the host process list, and the
container's writable layer all stay clean.
