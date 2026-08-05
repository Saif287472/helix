# Module: operability

Status: current. Follows the template in `messaging.module.md`.

## Purpose

Everything the Helix Admin console and a load balancer need: liveness and
readiness probes, server metrics, config read/write, log tailing, user
administration, invite management, backup triggering, and the federation
worldwide-mode toggle.

Also serves the one authenticated server fact ordinary clients read - the
admin-chosen server name.

## Owned files

- `operability.dart` - `OperabilityModule` and three separate routers.

## Route table

This module exposes **three** routers, mounted at different prefixes.

### `healthRouter` - `/api/v1/health` (public)

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET | `/live` | `_live` | Process is up. Public - `_authMiddleware` exempts it. |
| GET | `/ready` | `_ready` | Dependencies are usable. Also public. |

### `serverRouter` - `/api/v1/server` (session required)

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET | `/info` | `_serverInfo` | The admin-set server name. Deliberately authenticated: it adds no new unauthenticated surface, and someone still joining gets the same name from `/accounts/invite/lookup`. |

### `opsRouter` - `/api/v1/ops` (admin token required)

Every route calls `_isAdmin(request)` first and throws
`AppError.forbidden('Admin privileges required')` otherwise.

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET | `/metrics` | `_metrics` | CPU/RAM, DB size, connection counts, capability registry. |
| GET | `/support-diagnostic` | `_supportDiagnostic` | Bundled diagnostic export. |
| GET | `/config` | `_config` | Effective configuration, secrets excluded. |
| POST | `/config/server-name` | `_setServerName` | Validated by `server_name.dart`. |
| POST | `/backup` | `_backup` | Triggers a snapshot. |
| GET | `/users` | `_users` | Paginated. |
| POST | `/users/<accountId>/suspend` | `_suspendUser` | |
| POST | `/users/<accountId>/unsuspend` | `_unsuspendUser` | |
| POST | `/users/<accountId>/delete` | `_deleteUser` | |
| POST | `/users/<accountId>/block` | `_blockUser` | Blocks the phone hash, not just the account. |
| GET | `/logs` | `_logs` | See gotchas. |
| POST | `/invites` | `_createInvite` | |
| GET | `/invites` | `_listInvites` | Paginated. |
| POST | `/invites/<inviteId>/cancel` | `_cancelInvite` | 409 if already redeemed or cancelled. |
| GET | `/federation` | `_federationStatus` | |
| POST | `/federation/worldwide` | `_setWorldwideMode` | Opt-in directory registration. |

## Error codes this module throws

The [`AppError`](../app_error.dart) shape. Overwhelmingly `.forbidden`
('Admin privileges required' - 16 call sites, one per admin route),
plus `.badRequest` for invalid pagination or config values, `.notFound` for
an unknown account, `.conflict` for an invite that cannot be cancelled, and
`.serviceUnavailable` when server identity is not initialized.

## Dependencies

- `BackendDatabase`, `ServerIdentity`, `FederationClient`, `RateLimiter`,
  `OutboxWorker`, `WebSocketRelay` - it reports on all of them.
- `CallsModule.resolveTurnUrls` - so the console's TURN status reflects
  exactly what the call path would accept, rather than a second opinion.
- `ServerLogSink` (`../server_log.dart`) - the log tail's real source.

## Gotchas

- **`GET /logs` reads the in-memory ring buffer, not just a file.** Before
  2026-08-04 it tailed `HELIX_REMOTE_LOG_FILE`, which nothing ever wrote -
  output went to stdout for Docker to collect - so the console's Logs screen
  was permanently empty. The server now captures its own console output;
  the file is written too when the env var is set, rotating at 5 MB.
- **The admin token and request query strings are excluded from the
  captured log stream.** Query strings carry invite codes.
- **`_isAdmin` accepts the admin API token**, which `_authMiddleware` maps
  to a synthetic `account_id: 'admin'` claim. There is no per-admin user
  model.
- **Health probes are the only genuinely public routes in this module.**
  `/server/info` looks like it should be public and deliberately is not.
