# Helix Remote v2 Server - Deployment Handoff

Status: written in Phase S7 (2026-10-01) from the code on branch
`architecture-v2`. The v2 server is **not deployed**. Helix Global still runs
the v1 backend (`helix_remote/backend`, SQLite) until cutover (Phase X), which
the user performs. Until then, the v1 handoff
(`helix-remote-server-handoff.md` at the repo root) describes production.

This file is the v2 equivalent of that handoff. Day-two operation (health,
metrics, logs, jobs, backups, upgrades, troubleshooting) is in
[`V2_OPERABILITY.md`](V2_OPERABILITY.md). Plan of record:
`../architecture/ARCHITECTURE_V2_PLAN.md`.

Rules that do not change from v1: the user edits `.env` (agents never do);
never paste secret values anywhere; the running server is production and is
never stopped or restarted by an agent.

## What the server is

- One Dart program, package `helix_remote_server` in `helix_remote/server/`.
- It needs PostgreSQL 17. SQLite is not used at all.
- It is stateless. Any node can serve any request. All shared state is in
  Postgres (durable tables, plus UNLOGGED tables for short-lived state).
- It is built from modules, one per area. Each module owns one Postgres
  schema of the same name and has a `MODULE.md` next to its code:
  `ops`, `identity`, `keys`, `messaging`, `realtime`, `people`, `media`,
  `backup`, `groups`, `calls`, `federation`, `admin`, `compliance`
  (`lib/src/modules/all_modules.dart`). Group calls are deferred.
- The platform layer (database, bus, jobs, rate limits, storage, push, logs)
  is described in `server/lib/src/platform/PLATFORM.md`.
- The REST path prefix is `/v1/...` and the WebSocket is `/v1/ws`. v1 used
  `/api/v1/...`. Old app builds cannot talk to v2.

## Process layout

One node is one OS process: `dart run bin/server.dart`, started from
`helix_remote/server/`.

Inside the process:

| Part | What it does | Code |
|---|---|---|
| HTTP server (shelf) | REST, the WebSocket upgrade, media transfer | `lib/src/server.dart` |
| Postgres pool | Up to `HELIX_DB_POOL_SIZE` connections (default 10), a separate 4-connection pool for the ephemeral store, and one dedicated `LISTEN` connection for the event bus (reopened with backoff if it drops) | `platform/db/postgres_db.dart` |
| Event bus | Postgres `LISTEN/NOTIFY` on one channel, `helix_bus` | `platform/bus/event_bus.dart` |
| Job runner | Polls `platform.jobs` every 2 s and on a bus wake-up; runs push, federation relays and purges | `platform/jobs/jobs.dart` |
| Periodic scheduler | Checks every 15 s; each job runs once per interval on one node of the cluster | `platform/jobs/jobs.dart` |
| WebSocket gateway | Per-node connection table; routes in the ephemeral store | `modules/realtime/` |

The server is a single Dart isolate. To use more than one CPU core, run more
than one node (see "More than one node" in `V2_OPERABILITY.md`).

Around it, on the PC:

```
phones --TLS--> Caddy (80/443) --> 127.0.0.1:8080  helix_remote_server  --> PostgreSQL 17 (127.0.0.1:5432)
                                                        |
                                                        +--> helix_blobs/ (local object storage, or S3)
                                                        +--> FCM (push), BulkSMSBD (SMS)
phones --UDP/TCP 3478, 49160-49200--> coturn (WSL1)   (credentials minted by the server)
```

- **PostgreSQL 17** runs natively as the Windows service
  `postgresql-x64-17`. The role `helix` (no superuser, no CREATEDB) and the
  databases `helix` (server) and `helix_test` (tests) come from
  `server/tool/setup_local_postgres.ps1`, which the user runs. Agents never
  handle Postgres passwords.
- **Caddy** terminates TLS (`J:\Projects\Servers\helix_server`).
- **coturn** runs in WSL1 (`helix_remote/deploy/coturn/`).

## Start and stop

Order after a PC reboot: PostgreSQL, coturn, Caddy, then the server.

```powershell
Get-Service postgresql-x64-17        # must be Running (Start-Service needs an admin shell)

cd J:\Projects\helix\helix_remote
.\deploy\coturn\windows\start-turn.ps1

cd J:\Projects\Servers\helix_server
.\caddy.exe run                      # admin PowerShell

cd J:\Projects\helix\helix_remote\server
dart run bin/migrate.dart            # optional; see below
dart run bin/server.dart
```

- **Working directory matters.** `.env` is read from the current directory
  (`lib/src/platform/config/env_file.dart`), and the default local blob
  directory `helix_blobs` is relative to it. Always start from
  `helix_remote/server/`.
- **`.env` and the environment.** `KEY=VALUE` lines; blank lines and `#`
  comments are ignored; values may be wrapped in single or double quotes.
  Real environment variables win over `.env`. The environment is read once
  at start, so restart after editing `.env`.
- **`bin/migrate.dart`** applies migrations and exits. Every node also
  migrates at start under an advisory lock, so running it first is a deploy
  convenience, not a requirement. It builds every module, so it needs the
  full `.env` (pepper, SMS, TURN and so on), not just the database URL.
- **Stop with Ctrl+C.** The server stops accepting new requests and lets
  in-flight ones finish for up to 10 seconds, stops the scheduler and job
  runner, closes WebSockets with code 1001, and closes the database.
- **On Windows, only Ctrl+C is handled.** `bin/server.dart` listens for
  SIGTERM only on other platforms. Closing the console window or killing the
  process is a hard stop. It is safe for data (transactions, and job leases
  that expire after 2 minutes), but in-flight requests are lost.
- **Exit codes.** A bad setting, core or module (pepper, SMS, TURN, FCM,
  federation, an unwritable `HELIX_LOG_FILE`), prints the variable names and
  exits with 78 (EX_CONFIG); `bin/migrate.dart` does the same. If Postgres is
  unreachable at start, the process fails with `database is not reachable`.

## Environment variables

Generated from the code. Core settings are in
`lib/src/platform/config/server_config.dart`; module settings are read from the
same environment by the module named in the last column.

Legend. **Req**: required to start. **Dev**: meant for development or tests
only. **Secret**: never print, paste, commit or log; it must not appear in a
doc, a ticket or a chat.

Every boolean, core and module alike, accepts `1/true/yes` and `0/false/no`
(any case); anything else is a startup error (exit 78). One parser
(`parseEnvFlag` in `server_config.dart`) reads them all.

### Core

| Name | Req | Default | Dev | Secret | What it does |
|---|---|---|---|---|---|
| `HELIX_DATABASE_URL` | yes | none | no | **yes** | Postgres URL, `postgresql://helix:<password>@127.0.0.1:5432/helix?sslmode=disable` (percent-encode the password). The server appends `max_connection_count=<HELIX_DB_POOL_SIZE>`. Never logged. |
| `HELIX_HOST` | no | `127.0.0.1` | no | no | Listen address. Keep it on loopback; Caddy proxies to it. |
| `HELIX_PORT` | no | `8080` | no | no | Listen port, 0 to 65535. For a second node on the same PC, use another port. |
| `HELIX_PUBLIC_BASE_URL` | no | `http://<host>:<port>` | no | no | The public URL, `https://helix.agiletechbd.com` in production. It must be an absolute URL. Its host must be a DNS name or IPv4 address (checked at start even if federation is off). The host (and port, if any) is this server's federation domain. Also used by the `/open` page and `federation_domain`. |
| `HELIX_TOPOLOGY` | no | `single_host` | no | no | `single_host` or `cluster`. `cluster` only adds one rule: it refuses local object storage outside dev mode (it needs `HELIX_BLOB_STORE=s3`). Nothing else reads it. |
| `HELIX_GLOBAL_MODE` | no | `false` | no | no | `true` on Helix Global: sign-up by phone and SMS code. `false` is a personal server: invites only. `true` refuses to start without a configured SMS provider. |
| `HELIX_SERVER_NAME` | no | `Helix` | no | no | The starting server name. The operator can change it later (stored in `ops.settings`, which then wins). |
| `HELIX_NODE_ID` | no | random UUIDv7 per process | no | no | A name for this node, used in logs, job leases and WebSocket routes. Keep it unique among running nodes. |
| `HELIX_JWT_KEYS` | yes | none | no | **yes** | JSON object of key id to base64url secret, each at least 32 bytes: `{"2026-10":"<generate: 32 random bytes, base64url>"}`. Verifies device tokens and admin tokens. Every node needs the same value. |
| `HELIX_JWT_ACTIVE_KID` | if 2+ keys | the key, if only one | no | no | Which key signs new tokens. Must name a key in `HELIX_JWT_KEYS`. |
| `HELIX_BLOB_STORE` | no | `local` | no | no | `local` (a directory) or `s3` (any S3-compatible store). |
| `HELIX_BLOB_DIR` | no | `helix_blobs` | no | no | Directory for `local` storage, relative to the working directory; created if missing. Use an absolute path if more than one node shares it. |
| `HELIX_S3_ENDPOINT` | if `s3` | none | no | no | Store endpoint, for example `https://s3.example.com`. Phones use presigned URLs on this endpoint, so it must be reachable from phones. |
| `HELIX_S3_REGION` | no | `us-east-1` | no | no | SigV4 region. |
| `HELIX_S3_BUCKET` | if `s3` | none | no | no | Bucket name. The bucket must already exist. |
| `HELIX_S3_ACCESS_KEY_ID` | if `s3` | none | no | **yes** | Access key id. Treat as secret. |
| `HELIX_S3_SECRET_ACCESS_KEY` | if `s3` | none | no | **yes** | Secret key. |
| `HELIX_S3_PATH_STYLE` | no | `true` | no | no | `true`: `endpoint/bucket/key`. `false`: `bucket.endpoint/key`. |
| `HELIX_MAX_ATTACHMENT_BYTES` | no | `104857600` (100 MiB) | no | no | Largest attachment, at least 1024. Reported to apps in `GET /v1/server`. |
| `HELIX_TRUSTED_PROXIES` | no | `127.0.0.1,::1` | no | no | Peers whose `X-Forwarded-For` is believed (Caddy). Comma-separated addresses. The client address is the rightmost `X-Forwarded-For` hop that is not in this list. |
| `HELIX_TRUST_X_REAL_IP` | no | `false` | no | no | `true` also believes `X-Real-IP` from a trusted proxy, ahead of `X-Forwarded-For`. Only for a proxy that always overwrites that header (`header_up X-Real-IP {remote_host}` in Caddy); a client can set it otherwise. |
| `HELIX_DEV_MODE` | no | `false` | **yes** | no | Allows local blobs with `cluster`, plain-HTTP federation and a cheaper admin password hash. Never in production. |
| `HELIX_SCHEMA_PREFIX` | no | empty | **yes** | no | Prefixes every schema name (`[a-z][a-z0-9_]*`). For tests (isolation). Never set it in production: it would point the server at differently named schemas. |
| `HELIX_LOG_FILE` | no | none | no | no | Log lines (JSON, redacted) are also appended to this file; stdout keeps them too. Opened at start (an unwritable path exits with 78). Rotate it with a copy-and-truncate tool. |
| `HELIX_DB_POOL_SIZE` | no | `10` | no | no | Connections in the main Postgres pool, 2 to 200. Count every node's pool plus 5 per node (ephemeral pool and `LISTEN`) against Postgres `max_connections`. |
| `HELIX_MAX_INFLIGHT_BODY_BYTES` | no | `268435456` (256 MiB) | no | no | Request body bytes one node buffers at once, across all requests (at least 1 MiB). Over it, requests get 503 `unavailable` with `Retry-After: 2`. Keep it above the largest route limit (a full backup is up to 64 MiB). |
| `HELIX_METRICS_TOKEN` | no | none | no | **yes** | At least 32 characters. A bearer token that opens `GET /v1/ops/metrics` and nothing else, for a Prometheus scraper (compared in constant time). Unset: metrics need an admin token. |

### identity (`modules/identity/config.dart`, `sms.dart`)

| Name | Req | Default | Dev | Secret | What it does |
|---|---|---|---|---|---|
| `HELIX_PHONE_PEPPER` | yes | none | no | **yes** | Key for stored phone hashes: `<generate: 32 random bytes, base64url>`, at least 32 bytes. Keep it out of database backups. It also keys the phone discovery index, so a stolen database cannot be used to test numbers without it. Changing it orphans every stored phone hash and discovery index, so treat it as permanent. Every node needs the same value. |
| `HELIX_SMS_PROVIDER` | no | `none` | no | no | `none` or `bulksmsbd`. Required to be `bulksmsbd` when `HELIX_GLOBAL_MODE=true`. |
| `HELIX_SMS_API_KEY` | if `bulksmsbd` | none | no | **yes** | BulkSMSBD API key. |
| `HELIX_SMS_SENDER_ID` | if `bulksmsbd` | none | no | no | BulkSMSBD approved sender id. |
| `HELIX_TERMS_VERSION` | no | the built-in terms version | no | no | Overrides the terms version reported to apps. On Helix Global, registration must name this version. |
| `HELIX_OTP_RESEND_SECONDS` | no | `30` | no | no | Minimum gap between two codes to one number, 0 to 600. |

### push (`platform/push/push.dart`)

| Name | Req | Default | Dev | Secret | What it does |
|---|---|---|---|---|---|
| `HELIX_PUSH_PROVIDER` | no | `none` | no | no | `none` or `fcm`. With `none`, wake-ups are silently dropped. |
| `HELIX_FCM_PROJECT_ID` | if `fcm` | none | no | no | Firebase project id. |
| `HELIX_FCM_SERVICE_ACCOUNT` | if `fcm` | none | no | **yes** | Path to the Firebase service-account key file, or the JSON itself (a value starting with `{`). Prefer the path, kept outside the repository. |

### calls (`modules/calls/module.dart`)

| Name | Req | Default | Dev | Secret | What it does |
|---|---|---|---|---|---|
| `HELIX_TURN_URLS` | with the secret | none | no | no | Comma-separated TURN URLs handed to apps, each starting with `turn:` or `turns:` (TLS, port 5349; see "coturn and TURN"), for example `turn:helix.agiletechbd.com:3478?transport=udp,turn:helix.agiletechbd.com:3478?transport=tcp`. Set together with `HELIX_TURN_SECRET` or not at all (one without the other is a startup error). If unset, `GET` TURN credentials answer 503 `unavailable`. |
| `HELIX_TURN_SECRET` | with the URLs | none | no | **yes** | Shared secret; the same value as coturn's `static-auth-secret`. |

### admin (`modules/admin/module.dart`)

| Name | Req | Default | Dev | Secret | What it does |
|---|---|---|---|---|---|
| `HELIX_ADMIN_PASSWORD` | no | none | no | **yes** | Creates the first operator on a server that has none. At least 12 characters. It **never replaces** an existing password (unlike v1's `HELIX_REMOTE_ADMIN_PASSWORD`, which overrode it). Remove it after the first start. |
| `HELIX_ADMIN_KDF_MEMORY_KIB` | no | 19456 (the Argon2id recommendation) | **yes** | no | Argon2id memory cost for admin passwords. Outside dev mode it can only raise the cost; in dev mode it can lower it (minimum 64). |

### federation (`modules/federation/config.dart`, `modules/ops/module.dart`)

| Name | Req | Default | Dev | Secret | What it does |
|---|---|---|---|---|---|
| `HELIX_FEDERATION_ENABLED` | no | `false` | no | no | The **starting** value of the operator switch. Once the operator sets the switch (admin config), the stored value wins. |
| `HELIX_FEDERATION_ALLOW` | no | empty (any domain) | no | no | Comma-separated peer domains. If set, it is the only set of peers. Each must be a valid domain, or start fails. |
| `HELIX_FEDERATION_ALLOW_PRIVATE` | no | `false` | no | no | Also talk to peers on loopback and private addresses. For LANs and tests. Link-local addresses are always refused. |
| `HELIX_FEDERATION_HTTP` | no | `false` | **yes** | no | Use `http` instead of `https` for peers. Honoured only with `HELIX_DEV_MODE=true`. |

### ops (`modules/ops/module.dart`)

| Name | Req | Default | Dev | Secret | What it does |
|---|---|---|---|---|---|
| `HELIX_ANDROID_CERT_SHA256` | no | none | no | no | Comma-separated `AB:CD:...` SHA-256 fingerprints (32 bytes each) of the app's signing certificates. The server then serves `/.well-known/assetlinks.json` so shared links open the app. Not secret, but it must match the real signing certificate. |

### Tests only (not read by the server)

`HELIX_TEST_DATABASE_URL` (secret: contains the password) and
`HELIX_REQUIRE_TEST_DATABASE` are read by `server/test/support/`. See
`server/README.md`.

## Caddy

The upstream is the server's `HELIX_HOST:HELIX_PORT`. Keep the same site
block as v1 if the port does not change:

```caddy
helix.agiletechbd.com {
    reverse_proxy 127.0.0.1:8080
}
```

- **HSTS.** Add `Strict-Transport-Security` in Caddy, once HTTPS works for
  every client you serve (it makes browsers refuse plain HTTP for the whole
  period, so start with a short `max-age`):

  ```caddy
  helix.agiletechbd.com {
      header Strict-Transport-Security "max-age=31536000"
      reverse_proxy 127.0.0.1:8080
  }
  ```

  The server cannot set it itself: it only ever sees plain HTTP from Caddy on
  loopback, and browsers ignore HSTS sent over HTTP. It does set the other
  security headers on every response (`X-Content-Type-Options: nosniff`,
  `Cache-Control: no-store`, `Referrer-Policy: no-referrer`) and, on the
  `/open` landing page, a CSP with `frame-ancestors 'none'` and
  `X-Frame-Options: DENY`. Do not override those in Caddy. Served paths:
  `/open` and `/open/` only.
- **WebSocket.** `/v1/ws` needs no special Caddy setting: `reverse_proxy`
  forwards upgrades by itself. The server sends a ping every 30 s and the
  client heartbeat is 25 s, so idle connections stay open.
- **Client address.** When the connection comes from a trusted proxy
  (`HELIX_TRUSTED_PROXIES`, default loopback), the server takes the client
  address from the rightmost `X-Forwarded-For` hop that is not a trusted
  proxy. Caddy's `reverse_proxy` sets that header itself, so the bare site
  block above is enough, and hops a client writes into the header are never
  chosen. `X-Real-IP` is ignored (a client can send its own) unless
  `HELIX_TRUST_X_REAL_IP=true`, which is only for a proxy that always
  overwrites it.
- **If all users look like one address**, per-IP limits hit everyone at once.
  See "Troubleshooting" in `V2_OPERABILITY.md`.
- **Do not rewrite paths.** v2 uses `/v1/...`, `/.well-known/...` and `/open`
  at the site root. Federation peers fetch
  `https://<domain>/.well-known/helix-server` and call `/v1/s2s/...`.
- **Body size.** The server enforces its own limits (1 MiB by default,
  8 MiB for sends, 64 MiB for full backups, 96 KiB for crash reports,
  streamed uploads for media), reads a body only after the caller's
  credentials check out, and buffers at most `HELIX_MAX_INFLIGHT_BODY_BYTES`
  at once. Do not add a smaller limit in Caddy.
- **Two nodes.** List both upstreams, and let Caddy check readiness:

  ```caddy
  reverse_proxy 127.0.0.1:8080 127.0.0.1:8081 {
      health_uri /v1/health/ready
      health_interval 10s
  }
  ```

  Any node can serve any request, including WebSockets. After editing, run
  `caddy.exe reload` from the Caddy directory (or restart Caddy).

## coturn and TURN

- The server never relays media. It mints time-limited credentials
  (`GET /v1/calls/turn`, calls module): `username =
  <expiry>:<random id>` (new on every request, never an account or device
  id), `credential = base64(HMAC-SHA1(secret, username))`, valid one hour,
  limited to 10 per device per hour. coturn checks only the expiry and the
  HMAC, so it needs no account in the name. This matters because on `turn:`
  (port 3478) the username crosses the network unencrypted: anyone on the
  path sees it next to the client's address, and it must not identify a
  person.
- The server settings are `HELIX_TURN_URLS` and `HELIX_TURN_SECRET`.
  coturn's `static-auth-secret` must be the same value, and `use-auth-secret`
  must be on (`deploy/coturn/turnserver.conf` already does this).
- Ports are unchanged from v1: TCP 3478, UDP 3478, UDP 49160-49200 on the
  router and in Windows Firewall (`deploy/coturn/README.md`, "Windows home
  PC").
- **`turns:` (TLS).** On plain `turn:` the credentials, and the fact that an
  address is calling, are visible to anyone on the path; the media itself is
  always end-to-end encrypted. To hide the handshake too, give coturn a
  certificate (`TURN_CERT_FILE` and its key; `turnserver.conf` already has the
  TLS block and `tls-listening-port=5349`), open TCP 5349 on the router and in
  Windows Firewall, and list a `turns:` URL after the `turn:` ones in
  `HELIX_TURN_URLS`, for example
  `...,turns:helix.agiletechbd.com:5349?transport=tcp`. The certificate name
  must match the host in the URL. Entries must start with `turn:` or
  `turns:`, otherwise the server refuses to start. Until the certificate is
  in place, leave `turns:` out: a URL that cannot connect only slows calls
  down.
- **Open item for cutover:** `deploy/coturn/windows/start-turn.ps1` reads
  `HELIX_REMOTE_TURN_SECRET` and `HELIX_REMOTE_TURN_URL` from the environment
  or `backend\.env`. Phase X deletes `backend/`. The script must be changed to
  read `server\.env` and the new names (`HELIX_TURN_SECRET`,
  `HELIX_TURN_URLS`, or `TURN_REALM`) before the old backend goes. Until then,
  keep the same secret value in both places, and coturn needs no restart.
- The readiness probe does **not** check TURN. A missing TURN setting shows up
  as calls failing to get credentials (503 `unavailable`).

## Push (FCM)

- Push is data-only: `{t: message|call|call_ended}` and a call id, never
  content. Apps fetch and decrypt after waking.
- Set `HELIX_PUSH_PROVIDER=fcm`, `HELIX_FCM_PROJECT_ID`, and
  `HELIX_FCM_SERVICE_ACCOUNT` (a path to the service-account key file; keep
  it outside the repository). The server calls the FCM HTTP v1 API
  (`fcm.googleapis.com`), caches the access token and refreshes it five
  minutes early.
- A token FCM no longer knows (HTTP 404) is dropped. Only `fcm` tokens are
  sent; other kinds are ignored until APNs exists.
- Pushes run as `messaging.push` and `calls.push` outbox jobs. They retry
  with backoff and end up as dead letters after 5 attempts
  (`messaging.push`) or 3 (`calls.push`) (`V2_OPERABILITY.md`, "Jobs").
- The service-account key is the same kind of file v1 used. The v1 Firebase
  project can be reused.

## SMS (BulkSMSBD)

- Set `HELIX_SMS_PROVIDER=bulksmsbd`, `HELIX_SMS_API_KEY`,
  `HELIX_SMS_SENDER_ID`. Helix Global needs it; personal servers can run
  with `none`.
- The server sends to `https://bulksmsbd.net/api/smsapi` and treats
  `response_code` 202 as success (the gateway answers HTTP 200 even for
  errors). Failures are logged as `sms_failed` with a short reason
  (`unreachable`, `gateway_error`, `invalid_credentials`, `invalid_sender`,
  `invalid_destination`, `rejected`) and the caller gets 503
  `sms_unavailable`. The number, the code and the key are never logged.
- **Open item (POST versus GET).** v1 called the gateway with **GET** and the
  API key in the query string (`backend/lib/src/sms_provider.dart`). v2 calls it
  with **POST** and a form body, to keep the key out of URLs. v1's way is the
  one proven in production. Confirm POST against the real gateway at cutover:
  request one code and check that the text arrives. If the gateway rejects
  POST, the fix is in `modules/identity/sms.dart` and needs a change-log entry.

## Object storage

| | `local` (default) | `s3` |
|---|---|---|
| Setting | `HELIX_BLOB_STORE=local`, `HELIX_BLOB_DIR` | `HELIX_BLOB_STORE=s3` and the `HELIX_S3_*` settings |
| Bytes flow | Through the server: resumable `PUT /v1/media/{id}/content`, ranged `GET` | Direct between phone and store, with presigned URLs (PUT valid 15 minutes, GET 5 minutes) |
| Layout | Files `<dir>/<kind>/<id>`; kinds `attachment`, `persistent`, `backup` | Objects `<kind>/<id>` in the bucket |
| Several nodes | Only if they share the directory (same PC, same absolute path) | Yes. `cluster` requires it |
| Readiness | `storage` check: the directory exists | `storage` check: `HEAD` on the bucket returns 200 |

- The S3 bucket must exist before the server starts. The key needs
  `GetObject`, `PutObject`, `DeleteObject` on objects and head access to the
  bucket (the readiness check).
- Phones use the S3 endpoint directly, so `HELIX_S3_ENDPOINT` must be an
  address phones can reach, not `127.0.0.1`.
- Objects are end-to-end encrypted before upload. The store only sees
  random ids and ciphertext.
- There is no tool to move objects from local storage to S3. Switching a
  server that holds data leaves the old objects behind.

## Federation

Off by default. To turn it on:

1. `HELIX_PUBLIC_BASE_URL` must be the real public `https` URL. Its host is
   the federation domain, and peers must reach
   `https://<domain>/.well-known/helix-server` (served by the server whether
   federation is on or off) with a valid certificate. TLS is the trust root.
2. Turn it on, either by `HELIX_FEDERATION_ENABLED=true` (the starting
   value) or by the operator switch (`PATCH /v1/admin/config` with
   `federation_enabled`, from the Helix Admin app). The stored switch wins
   over the environment afterwards. Changes reach every node within seconds
   (bus message; the cache also expires after 30 s).
3. Set `HELIX_FEDERATION_ALLOW` to the peer domains you trust. Empty means
   any domain, subject to the address guard. An allow list is strongly
   advised.
4. Leave `HELIX_FEDERATION_ALLOW_PRIVATE` and `HELIX_FEDERATION_HTTP` off
   unless this is a LAN or dev setup.

While the switch is off, outbound relays answer 502 `federation_unavailable`
and inbound S2S requests are refused with 401. The server creates its
Ed25519 identity key at first start, even with federation off. It lives in
the database table `federation.settings`, so **a database dump contains this
private key**. See "Backups" in `V2_OPERABILITY.md`.

## Admin: first run

- **Without `HELIX_ADMIN_PASSWORD`:** the first caller of
  `POST /v1/admin/setup` becomes the operator (the Helix Admin app does this
  at first run). Setup is public until it is done, so on a server that is
  reachable from the internet, do it straight away, or use the seed below.
- **With `HELIX_ADMIN_PASSWORD`:** the server creates the operator at start
  (log events `admin_seeded`, or `admin_seed_ignored` if the value is shorter
  than 12 characters). It never replaces an existing password. Remove the
  line from `.env` after the first start, then restart when convenient.
- Passwords are 12 to 256 characters (Argon2id). Admin tokens last 12 hours.
  Five failed sign-ins lock the admin for 15 minutes, doubling up to 24 hours.
- **There is no reset tool.** v1 had `bin/reset_admin_password.dart`; v2 has
  no equivalent yet. The recovery steps (a SQL change by the operator) are in
  `V2_OPERABILITY.md`, "Troubleshooting".

## Operator console (Helix Admin)

`helix_remote/admin` is the operator console. It runs on the v2 admin API
only (`/v1/admin/*` and `GET /v1/ops/metrics`); it cannot talk to a v1 server.
It is a Flutter app for Android and Windows (a web build compiles, but see the
log note below).

- **Run it:** from `helix_remote/admin`, `flutter run -d windows`, or install
  the Android build the user makes (agents do not build APKs). Nothing in
  `.env` is needed for the console itself.
- **Point it at the server:** type the public address (for example
  `https://helix.agiletechbd.com`). It must be `https://`; plain `http://` is
  accepted only for this machine (`localhost`, `127.0.0.1`, the Android
  emulator's `10.0.2.2`), because the admin password travels to that address.
  The console asks the server whether setup is done (`GET /v1/admin/setup`).
- **First run:** if the server has no admin yet, the console shows
  "First-time setup": choose a password of 12 to 256 characters, typed twice.
  Skip this by seeding `HELIX_ADMIN_PASSWORD` (see "Admin: first run").
- **Signing in:** admin password only. After five wrong passwords from one
  address the server locks that address (15 minutes, doubling) and the
  console says how long to wait, from the `Retry-After` header. The token
  lasts 12 hours; after that, or after the admin password is changed
  elsewhere, the console returns to sign-in with a note.
- **Saved session:** the console keeps the token in platform secure storage
  (Android Keystore, Windows credential store) and the server address in
  preferences. "App lock" in Settings asks for the device's screen lock before
  the saved session opens.
- **What it does:** Overview (health, maintenance mode, federation switch,
  feature flags, activity numbers from `/v1/ops/metrics` including dead jobs and
  undelivered messages), Accounts (search by Helix name or the last four
  digits, suspend or resume, ban, delete, revoke a device, create a recovery
  code), Invites (only on servers that register by invite), Reports, the audit
  log, the server log (recent lines and a live feed over the admin WebSocket),
  and Settings (server name, admin password, purge dead jobs, sign out).
- **Shown once:** invite and recovery codes appear in a dialog when created
  and are not stored or listed again. The server keeps only hashes.
- **Phone numbers:** the server sends only the last four digits; the console
  shows nothing more.
- **The live log on the web:** a browser cannot set the `Authorization`
  header on a WebSocket, so the web build polls `GET /v1/admin/logs`
  every 3 seconds instead of following the stream.

## Rotating secrets

- **JWT key:** add a new entry to `HELIX_JWT_KEYS`, set
  `HELIX_JWT_ACTIVE_KID` to it, restart every node, keep the old key for at
  least 12 hours (the longest token lifetime: admin tokens are 12 hours,
  device access tokens 15 minutes, and refresh tokens are not JWTs), then
  remove the old key. Nobody is signed out while the old key stays.
- **Phone pepper:** do not rotate. It orphans stored phone hashes.
- **TURN secret:** change it in `.env` and in coturn together, then restart
  both. Credentials in flight stop working after at most an hour.
- **Admin password:** change it in the admin app (this ends other admin
  sessions).

## Draft cutover checklist (Phase X)

**DRAFT. The coordinator finalises this at Phase X.** Everything marked
"user" is done by the user. Agents do not touch the live server, `.env` or the
production database.

Decisions the user made on 2026-10-02 (plan §13, "Cutover decisions"):
federation off, `HELIX_ADMIN_PASSWORD` for the first admin, uploads on local
disk, `architecture-v2` merged into `main` with every commit kept (tag the last
v1 commit `v1-final` first), BulkSMSBD tested by POST on the day, the TURN
script reads the new `.env`, phones get the same app id (uninstall, then
install) and no rollback plan is wanted (the tag exists anyway).

### Before the day

1. Agent: merge `architecture-v2` into `main`; delete `backend/` and the
   retired packages (plan, Phase X); update `AGENTS.md`, CI, verify scripts.
2. Agent: change `deploy/coturn/windows/start-turn.ps1` to read
   `server\.env` and the new variable names (see "coturn and TURN").
3. Agent: list the final `.env` lines (below) with the real names from the
   code at that time. Re-run the generated table above against the code.
4. User: make sure the Postgres role and databases exist
   (`server/tool/setup_local_postgres.ps1`), and that backups work
   (`V2_OPERABILITY.md`, "Backups").
5. User, before releasing the app build: **check the TLS pin.** The app pins
   Helix Global's certificate key (`helix_remote_network_security.xml`,
   captured 2026-08-07). Caddy may have renewed with a new key since, and a
   stale pin makes Global unreachable in release builds. Get the current pin
   from the live certificate, update the config, or pass the new value with
   `--dart-define=HELIX_GLOBAL_PINS=<base64 sha256>,<backup>` at build time.
   Debug builds are not pinned.
6. Agent: tag the last v1 commit on `main` (`git tag v1-final`) before the
   merge.
7. User, optional rehearsal: create a throwaway database as the Postgres
   superuser (`createdb -U postgres -O helix helix_rehearsal`), start the new server on
   another port (`$env:HELIX_PORT = "8081"`, `HELIX_GLOBAL_MODE=false`,
   `HELIX_SMS_PROVIDER=none`) with that database, check
   `http://127.0.0.1:8081/v1/health/ready`, then drop the database.

### New `.env` lines (`helix_remote/server/.env`)

Placeholders only. The user fills in the values. Generate each random secret
once, for example in PowerShell (prints one base64url value):

```powershell
$b = New-Object byte[] 32; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); [Convert]::ToBase64String($b).TrimEnd('=').Replace('+','-').Replace('/','_')
```

```ini
# --- core ---
HELIX_DATABASE_URL=postgresql://helix:<helix role password, percent-encoded>@127.0.0.1:5432/helix?sslmode=disable
HELIX_HOST=127.0.0.1
HELIX_PORT=8080
HELIX_PUBLIC_BASE_URL=https://helix.agiletechbd.com
HELIX_TOPOLOGY=single_host
HELIX_GLOBAL_MODE=true
HELIX_SERVER_NAME=Helix Global
HELIX_JWT_KEYS={"2026-10":"<generate: 32 random bytes, base64url>"}
HELIX_JWT_ACTIVE_KID=2026-10
HELIX_BLOB_STORE=local
HELIX_BLOB_DIR=<absolute path, for example J:\Projects\Servers\helix_blobs>
HELIX_TRUSTED_PROXIES=127.0.0.1,::1

# --- identity ---
HELIX_PHONE_PEPPER=<generate: 32 random bytes, base64url>
HELIX_SMS_PROVIDER=bulksmsbd
HELIX_SMS_API_KEY=<BulkSMSBD API key, same as v1 HELIX_REMOTE_SMS_API_KEY>
HELIX_SMS_SENDER_ID=<BulkSMSBD sender id, same as v1 HELIX_REMOTE_SMS_SENDER_ID>

# --- push ---
HELIX_PUSH_PROVIDER=fcm
HELIX_FCM_PROJECT_ID=<Firebase project id, same as v1>
HELIX_FCM_SERVICE_ACCOUNT=<path to the Firebase service-account key file>

# --- calls (same values as v1 and coturn) ---
HELIX_TURN_URLS=<same list as v1 HELIX_REMOTE_TURN_URL>
HELIX_TURN_SECRET=<same value as v1 HELIX_REMOTE_TURN_SECRET and coturn>

# --- admin (remove after the first start) ---
HELIX_ADMIN_PASSWORD=<choose: 12 or more characters>

# --- app links ---
HELIX_ANDROID_CERT_SHA256=<AB:CD:... fingerprint(s) of the APK signing certificate, as in v1>

# --- federation (leave off at cutover) ---
# HELIX_FEDERATION_ENABLED=false
# HELIX_FEDERATION_ALLOW=<peer domains, comma-separated>
```

How the v1 names map:

| v1 (`backend/.env`) | v2 (`server/.env`) | Note |
|---|---|---|
| `HELIX_REMOTE_JWT_SECRET` | `HELIX_JWT_KEYS` | New key ring. All v1 sessions end anyway (clean slate). |
| `HELIX_REMOTE_HOST`, `_PORT` | `HELIX_HOST`, `HELIX_PORT` | |
| `HELIX_REMOTE_DEV_MODE` | `HELIX_DEV_MODE` | Keep it off. |
| `HELIX_REMOTE_DB_PATH` | `HELIX_DATABASE_URL` | SQLite file replaced by Postgres. |
| `HELIX_REMOTE_ATTACHMENTS_DIR` | `HELIX_BLOB_DIR` | Old attachments are not carried over. |
| `HELIX_REMOTE_PUBLIC_BASE_URL` | `HELIX_PUBLIC_BASE_URL` | |
| `HELIX_REMOTE_GLOBAL_INSTANCE_MODE` | `HELIX_GLOBAL_MODE` | |
| `HELIX_REMOTE_SMS_API_KEY`, `_SMS_SENDER_ID` | `HELIX_SMS_API_KEY`, `HELIX_SMS_SENDER_ID` | Add `HELIX_SMS_PROVIDER=bulksmsbd`. |
| `HELIX_REMOTE_FCM_PROJECT_ID`, `_FCM_SERVICE_ACCOUNT` | `HELIX_FCM_PROJECT_ID`, `HELIX_FCM_SERVICE_ACCOUNT` | Add `HELIX_PUSH_PROVIDER=fcm`. `HELIX_REMOTE_FCM_ACCESS_TOKEN` is gone. |
| `HELIX_REMOTE_TURN_URL`, `_TURN_SECRET` | `HELIX_TURN_URLS`, `HELIX_TURN_SECRET` | Values can stay the same. |
| `HELIX_REMOTE_ADMIN_PASSWORD` | `HELIX_ADMIN_PASSWORD` | Now only seeds the first admin. |
| `HELIX_ANDROID_CERT_SHA256` | `HELIX_ANDROID_CERT_SHA256` | Unchanged. |
| `HELIX_REMOTE_JWT_KEY_RING_JSON`, `_JWT_ACTIVE_KID` | `HELIX_JWT_KEYS`, `HELIX_JWT_ACTIVE_KID` | |
| `HELIX_REMOTE_MAX_ATTACHMENT_BYTES` | `HELIX_MAX_ATTACHMENT_BYTES` | |
| `HELIX_REMOTE_ACCOUNT_QUOTA_BYTES`, `_ATTACHMENT_RETENTION_DAYS` | none | Now fixed in the media module (4 GiB, 30 days). |
| `HELIX_REMOTE_DEPLOYMENT_TOPOLOGY`, `_BACKEND_WORKERS`, `_LOG_FILE`, `_SERVER_AUDIENCE`, `_ADMIN_TOKEN`, `_FEDERATION_*` | none | Not used in v2. |

### The day

1. User: stop the v1 backend (Ctrl+C in its console). Keep Caddy and coturn
   running. Copy `remote_backend.db` and `attachments_storage` somewhere safe
   if you want a way back; v2 does not read them.
2. User: write the new `.env` lines above in `helix_remote/server/.env`.
3. User: `cd J:\Projects\helix\helix_remote\server`, then
   `dart run bin/migrate.dart`. Expect `Applied: platform:1, ops:1, ...`. A
   second run prints `Up to date.`
4. User: `dart run bin/server.dart`. Expect the log event `server_started`
   with the module list.
5. User: Caddy. If `HELIX_PORT` is still 8080, the upstream is unchanged and
   nothing needs editing.
6. User: coturn. Run the updated `start-turn.ps1` (or leave it running if the
   secret did not change).
7. User, verify:
   - `curl.exe https://helix.agiletechbd.com/v1/health/ready` returns
     `{"ready":true,"checks":{"database":true,"storage":true}}`.
   - `curl.exe https://helix.agiletechbd.com/v1/server` shows the name,
     `registration: phone` and the version.
   - Sign in to the Helix Admin app (the first operator comes from
     `HELIX_ADMIN_PASSWORD`).
   - Install the new app build on a phone, register by SMS (this is the
     POST-versus-GET check: if no code arrives, look for `sms_failed` and its
     reason in the server log; the fix is to switch the BulkSMSBD call back
     to GET in `modules/identity/sms.dart`), send a message and make a call.
   - Things only a real phone can show (see `app/MODULE.md`): the camera and
     microphone prompts, voice-note recording and playback, video playback,
     the lock-screen incoming-call screen and audio routing, and that the app
     lock asks for the fingerprint or PIN after the app was swiped away.
8. User: remove `HELIX_ADMIN_PASSWORD` from `.env`.
9. User: reinstall the app on every phone (clean slate, plan D2).

### Rollback

Before the day, keep the v1 commit (the last `main` commit before the merge)
and the untouched v1 database and attachments. To go back: stop the v2
server, check out that v1 commit in a working copy, restore `backend/.env`,
and start `dart run bin/server.dart` in `helix_remote/backend` as before.
Phones with the new app will not work against v1.

## Review items found while writing this document

These are mismatches between plan, docs and code, or things to decide:

- Resolved in S7: `HELIX_LOG_FILE` now appends to the file; every boolean
  uses one parser (`1/true/yes`, `0/false/no`); module settings errors exit
  with 78 from both `bin/server.dart` and `bin/migrate.dart`.
- The plan lists `bin/admin_tool.dart` (reset admin password). It does not
  exist.
- `.env.example` says to remove an old JWT key "after 60 days (the
  refresh-token lifetime)". Refresh tokens are opaque, not JWTs, so 12 hours
  (the admin token lifetime) is enough.
- Readiness checks only `database` and `storage`. v1's readiness also
  reported call, TURN, WebSocket and push readiness.
- `start-turn.ps1` still reads `backend\.env` and the v1 variable names.
