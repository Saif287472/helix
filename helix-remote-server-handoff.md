# Helix Remote — Local PC Deployment Handoff

You're picking up infrastructure work on a self-hosted deployment of the "Helix Remote"
messaging app (private repo `github.com/Saif287472/helix`, main branch). This is
currently configured for personal/family and development use. The earlier InterServer
VPS (vps3516391 / `157.250.207.166`) has been fully wiped, decommissioned, and cancelled.
All backend and media relay services are now hosted locally on a dedicated Windows PC
with Caddy and WSL2.


## Server & Network Environment
- **Host Machine:** Windows 10/11 PC (User: `Hasan`)
- **Local IP (LAN):** `192.168.0.185`
- **Public IPv4:** `43.230.120.37`
- **WSL2 Instance:** Ubuntu 26.04 LTS (`hasan@DESKTOP-HA14AQF`)
- **Router Port Forwarding (NAT to `192.168.0.185`):**
  - TCP `80` → `80` (HTTP ACME challenge / Caddy redirect)
  - TCP `443` → `443` (HTTPS / Caddy)
  - UDP/TCP `3478` → `3478` (Coturn STUN/TURN signaling)
  - TCP `5349` → `5349` (Coturn TURNS TLS signaling)
  - UDP `49152-49250` → `49152-49250` (Coturn WebRTC media relay range)
  *(Note: Single-mode router inputs can strip dashes. Ensure range forwarding is preserved).*
- **Windows Defender Firewall (Inbound Rules):**
  - `Helix Caddy Web`: TCP 80, 443 (Allow)
  - `Coturn Signaling UDP`: UDP 3478 (Allow)
  - `Coturn Signaling TCP`: TCP 3478 (Allow)
  - `Coturn Relay Media`: UDP 49152-49250 (Allow)



## Domain & Reverse Proxy
- **Public Domain:** `helix.agiletechbd.com`
- **DNS:** Namecheap A record `helix` → `43.230.120.37` (Active & propagated)
- **Reverse Proxy:** Caddy v2 (`J:\Projects\Servers\helix_server\caddy.exe`)
- **Config File (`J:\Projects\Servers\helix_server\Caddyfile`):**
  ```caddy
  helix.agiletechbd.com {
      reverse_proxy 127.0.0.1:8080
  }


* **TLS Certificate:** Automatic ZeroSSL / Let's Encrypt managed by Caddy via `tls-alpn-01` challenge. Verified active and auto-renewing.

## Deployed Services

### 1. Helix Dart Backend Monolith

* **Location:** `J:\Projects\helix\helix_remote\backend`
* **Entry point:** `bin/server.dart` (runs on Dart SDK ^3.12, listening on `127.0.0.1:8080`)
* **Storage:** Local SQLite database at `remote_backend.db`, attachments at `./attachments_storage`
* **Secrets & Configuration:** Sourced from `backend/.env` (parsed and exported before boot):

HELIX_REMOTE_PORT=8080
HELIX_REMOTE_HOST=127.0.0.1
HELIX_REMOTE_DEV_MODE=0
HELIX_REMOTE_JWT_SECRET=a68ef41z68wecf1zefza8cd... (persistent 32+ bytes)
HELIX_REMOTE_DB_PATH=remote_backend.db
HELIX_REMOTE_ATTACHMENTS_DIR=./attachments_storage
HELIX_REMOTE_PUBLIC_BASE_URL=[https://helix.agiletechbd.com](https://helix.agiletechbd.com)
HELIX_REMOTE_TURN_URL=turn:helix.agiletechbd.com:3478?transport=udp
HELIX_REMOTE_TURN_SECRET=4gs6dr84gs6d5g4f9s8er...
TURN_REALM=helix.agiletechbd.com
TURN_EXTERNAL_IP=43.230.120.37




* **Admin Token:** Generated on first run and stored in `backend/ADMIN_TOKEN.txt`. Required for `/api/v1/ops/*` endpoints.

### 2. WebRTC TURN Media Relay (Coturn)

* **Runtime:** Running natively inside WSL2 Ubuntu (`sudo service coturn status`)
* **Config (`/etc/turnserver.conf`):**

listening-port=3478
fingerprint
lt-cred-mech
use-auth-secret
static-auth-secret=4gs6dr84gs6d5g4f9s8er...
realm=helix.agiletechbd.com
external-ip=43.230.120.37
min-port=49152
max-port=49250
no-cli



* **Daemon Flag:** Enabled via `TURNSERVER_ENABLED=1` in `/etc/default/coturn`.


## Health & Verification

Liveness and readiness endpoints confirmed functional:

powershell
# Public readiness probe (returns call_ready: true, turn: configured, websocket_ready: true)
curl.exe -k [https://helix.agiletechbd.com/api/v1/health/ready](https://helix.agiletechbd.com/api/v1/health/ready)

# Ops probe (requires Admin Bearer token)
curl.exe -k -H "Authorization: Bearer <ADMIN_TOKEN>" [https://helix.agiletechbd.com/api/v1/ops/config](https://helix.agiletechbd.com/api/v1/ops/config)



## Client Integration ("Helix Global Server")

* **Target URL:** `https://helix.agiletechbd.com`
* **Default Onboarding Route:** When users tap **Helix Global Server** on the initial launch menu, the client bypasses manual URL typing and automatically routes requests to `https://helix.agiletechbd.com`.
* **Invite Code Policy:**
* For open public signups, keep `HELIX_REMOTE_REQUIRE_INVITE=0` (or omitted) in `backend/.env`.
* If invite protection is enabled, auto-fill `_invitationCodeController.text` in `app/lib/main.dart` with the designated global server invite token so users do not need to input it manually.



## Startup Runbook (Post PC Reboot)

1. **Start Coturn (WSL2):**
bash
wsl -u root service coturn start




2. **Start Caddy (PowerShell Admin):**
powershell
cd J:\Projects\Servers\helix_server
.\caddy.exe run



3. **Start Helix Backend (PowerShell):**
powershell
cd J:\Projects\helix\helix_remote\backend
Get-Content .env | Where-Object { $_ -match '=' -and -not $_.Trim().StartsWith('#') } \vert{} ForEach-Object { $name, $value =$_.Split('=', 2); [System.Environment]::SetEnvironmentVariable($name.Trim(),$value.Trim()) }
dart run bin/server.dart
