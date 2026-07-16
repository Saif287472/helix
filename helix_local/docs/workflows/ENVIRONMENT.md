# Environment Configuration

## Intended Behavior

Helix is local-first and should run without production service credentials.
Optional local development settings belong in environment files that are never
committed.

Helix Remote is the exception that needs an explicit backend endpoint. The
client must be launched with a named `HELIX_REMOTE_PROFILE`; production does
not default to localhost.

## Invariants

- `.env.example` contains placeholders only.
- Real `.env*` files are ignored.
- Startup should fail fast when a required future config value is missing.
- Production URLs or credentials must not be hardcoded.
- Remote production uses HTTPS/WSS only and rejects cleartext transport.
- Remote development cleartext requires `HELIX_REMOTE_DEV_MODE=1` and a
  development profile.
- Android emulator development uses `10.0.2.2`, not `localhost`.
- Physical Android development uses an explicit trusted HTTPS/WSS LAN or
  staging endpoint. LAN HTTP is not enabled for physical devices.

## Failure Handling

- Invalid config should produce an actionable local error.
- Missing optional config should fall back to local-only behavior.

## Verification

- Secret scan.
- Manual review for config or dependency changes.

## Helix Remote Profiles

| Profile | Target | REST/WS default | Host rule |
|---|---|---|---|
| `production` | Release/staging TLS endpoint | `https` / `wss`, port `443` | `HELIX_REMOTE_HOST` required and must not be localhost |
| `local_windows` | Windows client against local backend | `http` / `ws`, port `8080` | Defaults to `127.0.0.1`; requires `HELIX_REMOTE_DEV_MODE=1` |
| `android_emulator` | Android emulator against host backend | `http` / `ws`, port `8080` | Defaults to `10.0.2.2`; requires `HELIX_REMOTE_DEV_MODE=1` |
| `android_physical` | Physical Android dev | `https` / `wss`, port `443` | `HELIX_REMOTE_HOST` required; trusted LAN/staging TLS only |

Optional values:

- `HELIX_REMOTE_PORT`
- `HELIX_REMOTE_REST_SCHEME`
- `HELIX_REMOTE_REST_BASE_PATH`
- `HELIX_REMOTE_WS_SCHEME`
- `HELIX_REMOTE_WS_HOST`
- `HELIX_REMOTE_WS_PORT`
- `HELIX_REMOTE_WS_PATH`
- `HELIX_REMOTE_STUN_URLS`
- `HELIX_REMOTE_TURN_URL`
- `HELIX_REMOTE_TURN_USERNAME`
- `HELIX_REMOTE_TURN_CREDENTIAL`
- `HELIX_REMOTE_IP_PRIVACY`

## Helix Remote Development Commands

Start the backend for same-PC Windows or Android emulator development:

```powershell
.\scripts\start_remote_backend_dev.ps1 -HostAddress 127.0.0.1 -Port 8080
```

Run Remote Windows against that backend:

```powershell
.\scripts\run_remote_windows_dev.ps1 -BackendHost 127.0.0.1 -BackendPort 8080
```

Run Remote Android emulator against that backend:

```powershell
.\scripts\run_remote_android_emulator_dev.ps1 -BackendPort 8080
```

Run Remote on a physical Android device against a trusted HTTPS LAN/staging
endpoint:

```powershell
.\scripts\run_remote_android_physical_dev.ps1 -TrustedHttpsHost helix-dev.example.test -BackendPort 443
```

Debug Android cleartext is scoped to the debug manifest and to loopback/emulator
hosts only. The main manifest does not set `usesCleartextTraffic` or a
network-security config.
