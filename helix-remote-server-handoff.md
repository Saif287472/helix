# Helix Remote — Local PC Deployment Handoff

> **Status: historical for the backend (Phase X, 2026-10).** This is the handoff of the v1 backend (SQLite, `helix_remote/backend`), which the v2 server replaced; its `HELIX_REMOTE_*` variables, `backend/.env` and SQLite steps no longer apply. The current handoff is [`helix_remote/docs/operations/V2_SERVER_HANDOFF.md`](helix_remote/docs/operations/V2_SERVER_HANDOFF.md). The PC-level parts below (Caddy, the router and Windows Firewall, coturn in WSL1, the dynamic IP) are still accurate; read them with the v2 handoff beside them.

You're picking up infrastructure work on a self-hosted deployment of the "Helix Remote"
messaging app (private repo `github.com/Saif287472/helix`, main branch). This is
currently configured for personal/family and development use. The earlier InterServer
VPS (vps3516391 / `157.250.207.166`) has been fully wiped, decommissioned, and cancelled.
All backend and media relay services are now hosted locally on a dedicated Windows PC
with Caddy, and coturn runs in **WSL1** (not WSL2: WSL1 shares Windows' network stack,
so coturn binds the PC's real LAN address).

The running backend on this PC is live production for Helix Global. Deploying a change
means committing it to this working copy and restarting the backend; never hand-edit
live state. The PC is not always on.


## Server & Network Environment
- **Host Machine:** Windows 10/11 PC (User: `Hasan`)
- **Local IP (LAN):** `192.168.0.185`
- **Public IPv4:** `43.230.120.37`
- **WSL1 distro:** Ubuntu (`start-turn.ps1 -Distro` defaults to `Ubuntu`)
- **Router Port Forwarding (NAT to `192.168.0.185`):**
  - TCP `80` → `80` (HTTP ACME challenge / Caddy redirect)
  - TCP `443` → `443` (HTTPS / Caddy)
  - UDP/TCP `3478` → `3478` (Coturn STUN/TURN signaling)
  - UDP `49160-49200` → `49160-49200` (Coturn relay range; `min-port`/`max-port` in
    `helix_remote/deploy/coturn/turnserver.conf`)
  *(Note: Single-mode router inputs can strip dashes. Ensure range forwarding is preserved.
  Older forwards for `49152-49250` and TCP `5349` are wider than needed.)*
- **Windows Defender Firewall (Inbound Rules):** see "Windows home PC" in
  `helix_remote/deploy/coturn/README.md` (UDP 3478 + 49160-49200, TCP 3478), plus
  `Helix Caddy Web`: TCP 80, 443 (Allow).



## Domain & Reverse Proxy
- **Public Domain:** `helix.agiletechbd.com`
- **DNS:** Namecheap A record `helix` → `43.230.120.37` (Active & propagated)
- **Reverse Proxy:** Caddy v2 (`J:\Projects\Servers\helix_server\caddy.exe`)
- **Config File (`J:\Projects\Servers\helix_server\Caddyfile`):**
  ```caddy
  helix.agiletechbd.com {
      reverse_proxy 127.0.0.1:8080
  }
  ```

* **TLS Certificate:** Automatic ZeroSSL / Let's Encrypt managed by Caddy via `tls-alpn-01` challenge.
* `helix_remote/deploy/nginx/` is legacy from the VPS era and is not used here.

## Deployed Services

### 1. Helix Dart Backend Monolith

* **Location:** `J:\Projects\helix\helix_remote\backend`
* **Entry point:** `bin/server.dart` (Dart SDK ^3.12, listening on `127.0.0.1:8080`)
* **Storage:** Local SQLite database at `remote_backend.db` (schema `PRAGMA user_version` 47),
  attachments at `./attachments_storage`
* **Secrets & Configuration:** `backend/.env`. The server reads it itself at startup
  (`loadEffectiveEnv` in `backend/lib/src/startup_env.dart`); process environment
  variables override `.env`. Never commit or paste its values. The keys this deployment needs are:

```ini
HELIX_REMOTE_PORT=8080
HELIX_REMOTE_HOST=127.0.0.1
HELIX_REMOTE_DEV_MODE=0
HELIX_REMOTE_JWT_SECRET=<32+ bytes, persistent>
HELIX_REMOTE_DB_PATH=remote_backend.db
HELIX_REMOTE_ATTACHMENTS_DIR=./attachments_storage
HELIX_REMOTE_PUBLIC_BASE_URL=https://helix.agiletechbd.com
HELIX_REMOTE_GLOBAL_INSTANCE_MODE=true
HELIX_REMOTE_SMS_API_KEY=<BulkSMSBD key>
HELIX_REMOTE_SMS_SENDER_ID=<BulkSMSBD sender id>
HELIX_REMOTE_TURN_URL=turn:helix.agiletechbd.com:3478?transport=udp,turn:helix.agiletechbd.com:3478?transport=tcp
HELIX_REMOTE_TURN_SECRET=<shared with coturn>
```

  The full variable list is in `helix_remote/docs/operations/REMOTE_OPERABILITY_AND_DR.md`.

* **Admin access:** there is no admin token file any more. The admin password is either
  `HELIX_REMOTE_ADMIN_PASSWORD` in `.env` (break-glass override) or a password created
  from the Helix Admin app on first run and stored hashed in the database; the server
  prints which one applies at startup. `bin/reset_admin_password.dart` resets the stored one.

### 2. WebRTC TURN Media Relay (Coturn)

* **Runtime:** coturn inside WSL1, started by `helix_remote/deploy/coturn/windows/start-turn.ps1`
  and stopped by `stop-turn.ps1`. The script renders `deploy/coturn/turnserver.conf` with
  `deploy/coturn/entrypoint.sh` (the same template the Docker deployment uses), reads
  `HELIX_REMOTE_TURN_SECRET` from the process environment or `backend/.env`, and detects the
  public and LAN IPs. The secret never goes on a command line.
* **Log:** `wsl -d Ubuntu -u root -- tail -f /var/log/helix-turn.log`
* One-time setup (install coturn, port forwards, firewall): `helix_remote/deploy/coturn/README.md`,
  section "Windows home PC".


## Health & Verification

```powershell
# Public readiness probe (call_ready, turn, websocket_ready, push_ready)
curl.exe https://helix.agiletechbd.com/api/v1/health/ready
```

Ops endpoints (`/api/v1/ops/*`, `/api/v1/admin/*`) need an admin session from the Helix
Admin app; use the app rather than hand-crafted requests.


## Client Integration ("Helix Global Server")

* **Target URL:** `https://helix.agiletechbd.com`
* **Default Onboarding Route:** choosing **Helix Global Server** in the app routes to
  `https://helix.agiletechbd.com` without manual URL entry.
* **Invites:** Helix Global has no invite codes. With `HELIX_REMOTE_GLOBAL_INSTANCE_MODE=true`
  an SMS OTP (BulkSMSBD) is the only credential for sign-up; every account must also set a
  password, and a password sign-in adds a device without signing others out. Personal
  (non-Global) servers keep invite-only registration.

> Sign-in (2026-09-28): the app opens on a single Helix Global page (phone number, then password or SMS code, then name/terms for new accounts). A personal server is reached through the hidden advanced mode (three taps in the bottom-right corner reveal an "Advanced mode" button; a fourth opens it) or through a shared link `https://helix.agiletechbd.com/open#HLX-…`. Advanced mode has one code field that tells an invite (`HLX-INV-`) from a recovery code (`HLX-REC-`), then the same phone and password/SMS pages. A recovery code names the server and account; the phone number must match the account (`POST /accounts/recovery/lookup`). With a password it is an ordinary password sign-in - nothing is reset. Without one, or via "Forgot password", `POST /accounts/recovery/redeem` resets the account onto the new device (new identity key, all other devices signed out) and requires the SMS code whenever the server has an SMS provider.
>
> For shared links to open the app directly, set `HELIX_ANDROID_CERT_SHA256` in `helix_remote/backend/.env` to the SHA-256 fingerprint(s) of the APK signing certificate(s), comma-separated; the backend then serves `/.well-known/assetlinks.json`. Without it the link opens a landing page (`/open`) whose button opens the app.


## Startup Runbook (Post PC Reboot)

1. **Start Coturn (WSL1, PowerShell):**
   ```powershell
   cd J:\Projects\helix\helix_remote
   .\deploy\coturn\windows\start-turn.ps1
   ```

2. **Start Caddy (PowerShell Admin):**
   ```powershell
   cd J:\Projects\Servers\helix_server
   .\caddy.exe run
   ```

3. **Start Helix Backend (PowerShell):**
   ```powershell
   cd J:\Projects\helix\helix_remote\backend
   dart run bin/server.dart
   ```
   No manual `.env` export is needed; the server loads `backend/.env` itself.
