# Module: admin_pairing

Status: current. Follows the template in `messaging.module.md`.

## Purpose

Lets an operator with terminal access mint a fresh admin token while the
server keeps running, instead of stopping it to run
`bin/reset_admin_token.dart`. The operator generates a short code on the
server, then types it into the admin app.

## Owned files

- `admin_pairing.dart` - `AdminPairingModule` and its router. ~125 lines.

## Route table

Mounted at `/api/v1/admin-pairing`. **`_authMiddleware` skips any path
containing `/admin-pairing/`** - by necessity, since the whole point is
recovering access when you have no admin token.

| Method | Path | Handler | Notes |
|---|---|---|---|
| POST | `/generate` | `_generate` | Loopback (or Docker bridge gateway) callers only. Mints a single-use 16-digit code. |
| POST | `/redeem` | `_redeem` | Network-reachable. Exchanges a valid code for the admin token. Rate limited. |

## Error codes this module throws

The [`AppError`](../app_error.dart) shape: `.badRequest` for a malformed
body and `.unauthorized` for an invalid or expired code.

## Dependencies

- `BackendDatabase`, `ServerIdentity` - the token being handed out.
- `pairing_codes.dart` - code generation and constant-time comparison.
- `docker_host.dart` - resolves the bridge gateway address a
  host-loopback connection is NATed to appear as.
- `RateLimiter` - 10 redeem attempts per 10 minutes per caller.

## Gotchas

- **`/generate`'s gate is the raw TCP peer address, deliberately not
  `X-Forwarded-For`.** `BackendServer._resolveClientIp` honours forwarded
  headers for trusted reverse proxies; that handling is *not* reused here,
  because a header is spoofable and the raw peer address is not.
- **The Docker bridge gateway is accepted as equivalent to loopback**
  because this deployment publishes the port as `127.0.0.1:8080:8080`, so a
  host-loopback connection arrives NATed. Accepting it is what makes the
  flow usable in a container at all - and it is still unreachable from
  outside the host.
- **The 16-digit code space is far smaller than the admin token.** What
  makes it safe is the combination of single use, a 10-minute expiry, and
  per-caller rate limiting - remove any one and it stops being safe.
- **`/redeem` must stay network-reachable.** The admin app calls it from the
  operator's machine, not from the server.
