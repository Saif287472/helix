# Helix Remote — VPS Deployment Handoff

You're picking up infrastructure work on a self-hosted deployment of the "Helix Remote"
messaging app (private repo `github.com/Saif287472/helix`, main branch). This is for
personal/family use only (not public). Backend is already live and working. Below is
everything about the *environment* — you already have full code access, so this doc
intentionally skips code-level detail and focuses on server state, decisions made, and
why, so you don't re-break things that were already debugged.

## Server access
- Provider: InterServer, VPS ID vps3516391
- Public IP: `157.250.207.166`
- OS: Ubuntu 24.04.4 LTS, minimized install
- Access: `ssh root@157.250.207.166` — root password is known only to the user; ask
  them for it or have them run commands for you if you don't have direct SSH tooling.
- Firewall (ufw): active, allows only OpenSSH (22), 80, 443. Nothing else reaches the
  box from the internet.
- fail2ban: installed and running, protecting SSH from brute force.
- Docker: installed via get.docker.com convenience script. `docker compose` (plugin,
  v5.3.1 at time of writing) — note the modern syntax is `docker compose`, not
  `docker-compose`.

## Domain / DNS
- Public hostname: `hr.agiletechbd.com` (a subdomain of the user's own domain,
  `agiletechbd.com`, which has other unrelated apps on a *different* server — don't
  touch the root domain's other DNS records).
- DNS: A record `hr` → `157.250.207.166`, already propagated and confirmed working.
- User said the subdomain name can change later if needed — not locked in.

## What's deployed and running
- Repo cloned at `/opt/helix-remote/helix_remote` on the VPS (cloned from the private
  GitHub repo; the user will re-clone/pull themselves going forward — the one-time
  access token used for initial clone has been revoked).
- Repo top-level layout (for your reference, not to re-derive): `admin/`, `app/`,
  `backend/`, `packages/` (11 sub-packages), `contracts/`, `docs/`, `scripts/`, `tool/`,
  plus root `pubspec.yaml` (Dart pub **workspace** listing all members) and
  `docker-compose.yml`.
- Only the **backend** service is deployed so far, via Docker:
  - `docker-compose.yml` (repo root) — defines service `helix-backend`, port mapped as
    `127.0.0.1:8080:8080` (NOT publicly exposed — only reachable via Nginx, on purpose).
  - `backend/Dockerfile` — **this has been substantially rewritten from what's in the
    repo.** See "Deviations from repo defaults" below before touching it.
  - Container is running (`docker compose ps` shows `helix-backend` Up), confirmed
    responding correctly with `401 Unauthorized` JSON on unauthenticated requests to
    `/` — that 401 is correct/expected, not a bug.
- Nginx reverse proxy: `/etc/nginx/sites-available/hr.agiletechbd.com` (symlinked into
  `sites-enabled/`), proxies `hr.agiletechbd.com` → `http://127.0.0.1:8080`, with
  WebSocket upgrade headers configured (needed for the app's realtime `/api/v1/ws`
  endpoint) and a 3600s proxy read timeout for long-lived connections. **Source of
  truth is now `helix_remote/deploy/nginx/hr.agiletechbd.com.conf` in the repo** —
  see "Deployment workflow" below.
- TLS: real Let's Encrypt certificate via certbot's Nginx plugin, deployed and
  confirmed live over HTTPS. Auto-renewal via `certbot.timer` (systemd), confirmed
  active.
- End-to-end verified: `curl -i https://hr.agiletechbd.com/` returns HTTP over TLS with
  the expected 401 JSON body from the Dart backend.

## Secrets currently in place (already generated, don't regenerate unless rotating)
As of the `.env`-file split (see "Deployment workflow" below), these live in
`/opt/helix-remote/helix_remote/.env` on the server — a gitignored file, never
committed, never touched by `git pull` — rather than inline in `docker-compose.yml`.
Read them from there rather than asking the user to remember them:
- `HELIX_REMOTE_JWT_SECRET` — random 32-byte hex, replaced the repo's unsafe
  placeholder default.
- `HELIX_REMOTE_ADMIN_TOKEN` — random 24-byte hex, added (wasn't in the original
  compose file at all). Needed for the admin console / operability endpoints later.
- `HELIX_REMOTE_SMS_API_KEY` / `HELIX_REMOTE_SMS_SENDER_ID` — BulkSMSBD credentials
  for real OTP delivery, if configured. See `.env.example` in the repo root for the
  full list of what goes in `.env`.

## Deviations from repo defaults (important — read before editing Dockerfile/compose)
The repo's checked-in `backend/Dockerfile` does **not** work as-is in this environment.
Three real bugs were found and fixed; the current on-server Dockerfile reflects the
fixes below. If you regenerate it from the repo's original, you'll reintroduce all
three:

1. **Workspace resolution fails in a Dart-only container.** The root `pubspec.yaml`
   workspace includes `app/` and `admin/` (Flutter packages) and
   `packages/helix_remote_groups` (depends on `flutter_test`). The `dart:stable` Docker
   image has no Flutter SDK, so a workspace-wide `dart pub get` fails. Fix: the
   Dockerfile now `COPY`s only `backend/` and `packages/helix_remote_domain/` (the only
   local dependency the backend actually needs), then strips the
   `resolution: workspace` line from both of those packages' `pubspec.yaml` files with
   `sed` before running `dart pub get`, so they resolve independently of the full
   monorepo.

2. **`sqlite3` vs `sqlcipher` mismatch.** The *root* `pubspec.yaml`'s hook config
   defaults to `sqlite3: source: sqlcipher` (encrypted DB — this is almost certainly
   for the mobile app's on-device local storage). But `backend/pubspec.yaml` overrides
   this with `sqlite3: source: system` (plain SQLite). The backend's Dockerfile
   installs plain `libsqlite3-dev`/`sqlite3`, **not** sqlcipher — this is correct for
   the backend as declared, don't "fix" it to sqlcipher.

3. **`dart compile exe` doesn't support build hooks.** Because `sqlite3` uses a native
   build hook, `dart compile exe` refuses to compile the server (hard SDK restriction,
   not a bug in this project). Fixed by using `dart build cli --target=bin/server.dart
   --output=/app/out` instead, which produces `/app/out/bundle/bin/server` (executable)
   and `/app/out/bundle/lib/` (any dynamic libs). The runtime stage `COPY`s the whole
   `bundle/` directory and runs `/app/bundle/bin/server`.

4. **Runtime `.so` symlink issue.** The FFI hook loader looks for the *unversioned*
   `libsqlite3.so` symlink at runtime, which on Debian bookworm only ships inside the
   `libsqlite3-dev` package, not the plain `sqlite3`/`libsqlite3-0` runtime packages.
   The runtime stage installs `libsqlite3-dev` (yes, a "-dev" package in a runtime
   image — unusual but necessary here) rather than just `sqlite3`.

The current full `backend/Dockerfile` on the server (18 lines) implements all four
fixes together — read it directly from the server rather than assuming, in case it's
changed since this handoff was written.

## TURN relay (coturn) — ready to deploy, co-hosted on this same VPS
As of 2026-08-04 the repo ships a coturn service in `docker-compose.yml` that runs
alongside the backend on this box. It is **not started yet** — it needs `.env` values
and firewall rules first. Full instructions live in
`helix_remote/deploy/coturn/README.md`; the short version:

1. Add to `/opt/helix-remote/helix_remote/.env`:
   ```ini
   HELIX_REMOTE_TURN_URL=turn:hr.agiletechbd.com:3478,turns:hr.agiletechbd.com:5349
   HELIX_REMOTE_TURN_SECRET=<openssl rand -hex 32>
   TURN_REALM=hr.agiletechbd.com
   TURN_EXTERNAL_IP=157.250.207.166
   ```
2. `ufw allow` 3478/tcp+udp, 5349/tcp+udp, and 49160:49200/udp. These are the first
   ports besides 22/80/443 to be opened on this box — TURN cannot work behind the
   reverse proxy, it has to be reachable directly.
3. `docker compose up -d helix-turn && docker compose up -d helix-backend`.
4. Optional but recommended, for `turns:` on 5349:
   `sudo deploy/coturn/certbot-deploy-hook.sh`, then install it into
   `/etc/letsencrypt/renewal-hooks/deploy/` so renewals keep working. It reuses the
   existing `hr.agiletechbd.com` certificate — do not issue a second one.

Notes for whoever runs this:
- `helix-turn` uses `network_mode: host` on purpose (relay port range + real client
  source addresses). It is the only container on this box not behind nginx.
- `HELIX_REMOTE_TURN_SECRET` is shared: the backend signs credentials with it and
  coturn verifies them. If they ever drift, calls fail with a 401 from the relay that
  does not appear in the backend's logs at all. Restart `helix-turn` after changing it.
- `turnserver.conf` denies relaying to private/loopback ranges. That is load-bearing
  here: with host networking, an unrestricted relay could reach the backend on
  `127.0.0.1:8080` directly, bypassing nginx and TLS. Don't remove those lines to
  debug a connectivity problem.
- Verified working before shipping: coturn 4.6.1 accepted a credential in the exact
  format the backend issues and relayed traffic end to end (0 packet loss). The
  format is now pinned by `backend/test/turn_rest_credential_test.dart`.

## Admin console Logs screen (fixed 2026-08-04)
It used to be permanently empty. `/api/v1/ops/logs` tailed `HELIX_REMOTE_LOG_FILE`,
but nothing in the server ever wrote that file — output went to stdout/stderr for
Docker to collect — so the endpoint always found a missing file. The server now
captures its own console output (in memory, plus to the file when
`HELIX_REMOTE_LOG_FILE` is set, rotating at 5MB) and logs one line per request.

Deployment impact: none beyond a `git pull` and rebuild. `.env` already sets
`HELIX_REMOTE_LOG_FILE=/app/data/server.log`, which lands on the `helix-data` volume
and now actually gets written, so logs survive restarts. `docker compose logs` is
unchanged — the capture is additive. The admin token is deliberately excluded from
the captured stream, as are request query strings (they carry invite codes).

## Optional/unconfigured (mentioned in server logs as warnings, not errors)
- `HELIX_REMOTE_FCM_PROJECT_ID` / `HELIX_REMOTE_FCM_ACCESS_TOKEN` — not set. Push wake
  notifications disabled; app presumably still works via direct WebSocket while open/
  backgrounded per its own logic.

## Not yet done
- **Flutter Android APK build** — user is building this themselves on their own
  Windows PC (Flutter SDK + Android Studio installed for the Android SDK toolchain),
  targeting `app/`, via `flutter build apk --release`. Not your task unless they say
  otherwise.
  - Important context: the app has a runtime "enter server URL" flow
    (`RemoteDevelopmentConfig.fromServerUrl` + `ServerUrlStore`, in
    `app/lib/app/remote_config.dart` and `app/lib/services/server_url_store.dart`) —
    users type `https://hr.agiletechbd.com` into the app itself after install. No
    `--dart-define` build flags are needed for a normal HTTPS production deployment
    like this one.
- End-to-end registration/login test through the actual mobile app hasn't happened yet
  (only tested via `curl`, which confirms the server is reachable and enforcing auth —
  not that full app flows work).
- Admin console (`admin/`) not built or deployed anywhere yet.
- No backup strategy for the Docker volume `helix-data` (holds the sqlite DB +
  attachments) — worth setting up periodic backups before there's real family data on
  it.
- No non-root SSH/deploy user — everything has been done as `root` over password SSH.
  Acceptable for this low-stakes personal context but a hardening candidate later
  (e.g. SSH key auth, non-root deploy user, non-root container user).

## Deployment workflow (standard going forward)
As of 2026-07-26, changes should flow **local repo → GitHub → VPS `git pull`**,
not be edited live on the VPS. This applies to code, the Dockerfile, and the
nginx config (now tracked at `helix_remote/deploy/nginx/hr.agiletechbd.com.conf`).

1. Fix/edit locally, commit, push to GitHub.
2. On the VPS: `cd /opt/helix-remote/helix_remote && git pull`.
3. If backend code/Dockerfile changed: `docker compose build && docker compose up -d`.
4. If the nginx config changed: copy `deploy/nginx/hr.agiletechbd.com.conf` to
   `/etc/nginx/sites-available/hr.agiletechbd.com`, then `nginx -t && systemctl
   reload nginx`.

**`.env` split (2026-08-03):** `docker-compose.yml` used to have real secrets
(JWT secret, admin token) hand-edited directly into it on the server, which
permanently diverged it from the repo's placeholder-only version and made
every `git pull` that touched the file conflict (had to `git stash`/`pull`/
`stash pop` around it). Fixed: secrets now live in a separate `.env` file next
to `docker-compose.yml`, gitignored, created once and never touched by git
again — see `.env.example` in the repo root for the full list of keys.
`docker-compose.yml` itself is now identical between the repo and the VPS, so
step 2 above is a plain fast-forward from here on, no stashing needed.

**Known-fixed incident (2026-07-26):** the nginx config unconditionally sent
`Connection: upgrade` on every proxied request (not just `/api/v1/ws`), which
made Dart's `shelf_io` server detach the socket and drop the request body on
every POST — causing every registration/login attempt to fail with a silent,
unlogged `500`. Fixed by scoping the upgrade headers to the `/api/v1/ws`
location only. If you ever rebuild the VPS from scratch, deploy from
`deploy/nginx/hr.agiletechbd.com.conf` (which has the fix), not from memory.

## Useful commands for you
```bash
cd /opt/helix-remote/helix_remote
docker compose ps                          # container status
docker compose logs --tail=100 helix-backend
docker compose build                       # rebuild after Dockerfile changes
docker compose up -d                       # apply changes / restart
docker compose down && docker compose up -d  # full restart
nginx -t && systemctl reload nginx         # after editing nginx config
curl -i https://hr.agiletechbd.com/        # smoke test from the server itself
```
