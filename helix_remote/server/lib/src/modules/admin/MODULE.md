# admin module

The operator console's API. Schema `admin`: `admins` (Argon2id password
hash with its parameters, lockout counters, `tokens_valid_after`) and
`audit`. It uses identity's `IdentityAdminApi`, people's report methods and
`OpsApi`. It provides the admin half of authentication
(`ProvidesAuthentication`).

## Sign-in

- **First run:** `GET /v1/admin/setup` reports whether an admin exists.
  `POST /v1/admin/setup` sets the first password, once (a table lock makes
  concurrent setups safe), and returns a session. Alternatively,
  `HELIX_ADMIN_PASSWORD` seeds the first admin at start; it never replaces
  an existing password.
- **Passwords:** 12 to 256 characters. Argon2id at 19 MiB, 2 passes,
  1 lane, run on a separate isolate. Parameters are stored per hash.
  `HELIX_ADMIN_KDF_MEMORY_KIB` can lower the memory cost only in dev mode
  (tests).
- **Sign-in:** `POST /v1/admin/sessions`, limited to 10 per minute per IP.
  After 5 consecutive failures the password locks for 15 minutes, doubling
  per further failure up to 24 hours (`password_locked` with
  `Retry-After`).
- **Tokens:** `HmacJwt` with audience `helix.admin`, type `admin`,
  `sub` = admin id, valid for 12 hours, on the server's JWT key ring. The
  audience and type keep device and admin tokens apart in both
  directions. Changing the password sets `tokens_valid_after`, which ends
  every other session, and returns a new one.

## Actions

Every mutating action writes an `audit` row (action, target id, small
string details) in the same transaction. Codes, tokens and passwords are
never audited, and reasons pass through `redactString`.

| Area | Routes | Notes |
|---|---|---|
| Accounts | list (`status`, `q` = name prefix or last 4 digits, cursor), detail | No phone numbers beyond the last 4 digits. Detail adds open reports. |
| Suspend | `PUT` / `DELETE …/suspension` | The account keeps its devices; only `allowSuspended` routes answer. |
| Ban | `POST …/ban` | Bans the phone hash, then deletes the account. |
| Delete | `DELETE …/{account}` | identity's full deletion (every module's hook). |
| Devices | `DELETE …/devices/{id}` | Full revoke: hooks purge keys and mailbox, and the socket closes. |
| Recovery | `POST …/recovery-codes` | 48 hours, single use, shown once. |
| Invites | list, create (code shown once), cancel | Codes are stored hashed. |
| Reports | list (`status`), resolve or dismiss | |
| Audit | list, newest first | |
| Config | get, patch `server_name`, `maintenance`, `federation_enabled` | |
| Flags | get, set (allow-listed) | |
| Logs | recent lines, WS stream | This node only, already redacted. |
| Purge | `POST /v1/admin/purge` | Dead jobs and expired identity rows. Counts by kind. |

## Review notes

First-run setup is public, as in v1: on a fresh public server the first
caller of `POST /v1/admin/setup` becomes the operator. Set
`HELIX_ADMIN_PASSWORD` before exposing a new server, or run setup
straight away.
