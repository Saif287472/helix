# admin module

The operator console's API. Schema `admin`: `admins` (Argon2id password
hash with its parameters, lockout counters, `tokens_valid_after`) and
`audit`. It uses identity's `IdentityAdminApi`, people's report methods,
`OpsApi`, billing's facade (`BillingApi`) and the calls facade (`turnConfigured`, `turnUrlCount`). It provides the admin half of authentication
(`ProvidesAuthentication`).

## Sign-in

- **First run:** `GET /v1/admin/setup` reports whether an admin exists.
  `POST /v1/admin/setup` sets the first password, once (a table lock makes
  concurrent setups safe), and returns a session. Alternatively,
  `HELIX_ADMIN_PASSWORD` seeds the first admin at start; it never replaces
  an existing password, and while an admin exists a start with it still set
  logs `admin_seed_still_set` (remove it from `.env`).
- **Forgotten password:** `dart run bin/admin_tool.dart reset-password`
  on the server's machine (it reads `server/.env`) asks for a new password
  twice without echo and calls `AdminModule.resetPassword`: it sets the
  password (or creates the operator), ends every admin session, clears
  every address lock and writes an `admin.password_reset` audit row.
- **Passwords:** 12 to 256 characters. Argon2id at 19 MiB, 2 passes,
  1 lane, run on a separate isolate. Parameters are stored per hash.
  `HELIX_ADMIN_KDF_MEMORY_KIB` can lower the memory cost only in dev mode
  (tests).
- **Sign-in:** `POST /v1/admin/sessions`, limited to 10 per minute per IP.
  Lockout is per client address (`sign_in_failures`, migration 2): after 5
  failures that address locks for 15 minutes, doubling per further failure
  up to 24 hours.
  A global safety cap on `admins.failed_attempts`: 100 failures from
  addresses outside the local network since the last success lock sign-in
  from those addresses for 15 minutes, then the count restarts. Loopback
  and LAN addresses (`domain/local_address.dart`) neither count towards it
  nor are stopped by it, so an attacker on the internet cannot lock out the
  operator at home; one signing in from the internet can still be locked
  out by it (with the hardened Caddyfile the admin API is LAN-only anyway).
  This relies on `HELIX_TRUSTED_PROXIES` naming the proxy: otherwise every
  request looks like loopback and only the per-address lock applies. A peer
  that is not a trusted proxy but sends `X-Forwarded-For` or `X-Real-IP` is
  taken for exactly that misconfiguration (`HelixRequest.clientIpUntrusted`):
  it is not exempted as a LAN host, and sign-in logs `admin_untrusted_proxy`
  (AUD-7-1) - fix the setting when you see it. Each attempt is counted in SQL *before* the password is
  checked, with the admin row locked, so parallel requests get no extra
  guesses (`password_locked` with `Retry-After`). A success clears both.
  Quiet unlocked addresses are purged after two days
  (`admin.purge_sign_in_failures`).
- **Tokens:** `HmacJwt` with audience `helix.admin`, type `admin`,
  `sub` = admin id, valid for 7 days, on the server's JWT key ring. The
  audience and type keep device and admin tokens apart in both
  directions. Changing the password sets `tokens_valid_after`, which ends
  every other session, and returns a new one.
- **Sign-out:** `DELETE /v1/admin/sessions` sets `tokens_valid_after` to
  now: every token of the operator stops working, the caller's and any
  copy of it (the way to cut off a token that may have leaked). The console's
  "Sign out" calls it.
- **Log stream:** `GET /v1/admin/logs/stream` keeps the token it was opened
  with and checks it again every 60 s and at once after a sign-out or a
  password change; a token that no longer verifies closes the stream with
  4001. Client messages over 1 KiB close it (`limitWebSocketFrames`). It
  closes with 4503 at shutdown.

## Actions

Every mutating action writes an `audit` row (action, target id, small
string details) in the same transaction, sign-in and sign-out included
(recovery codes and invites go through identity's facade with the caller's
transaction). Codes, tokens and passwords are never audited, and reasons
pass through `redactString`. Rows older than a year are deleted daily
(`admin.purge_audit`); they hold account ids, which therefore outlive a
deleted account by at most a year.

| Area | Routes | Notes |
|---|---|---|
| Accounts | list (`status`, `q` = Helix name prefix or last 4 digits, cursor), detail | Each account's own name (people's `displayNames`) and full phone number (identity, opened from `phone_sealed` with `HELIX_PHONE_KEY`) once its app reported them (ADR-030), else the last 4 digits. Detail adds open reports. |
| Suspend | `PUT` / `DELETE …/suspension` | The account keeps its devices; only `allowSuspended` routes answer. |
| Ban | `POST …/ban` | Bans the phone hash, then deletes the account. |
| Delete | `DELETE …/{account}` | identity's full deletion (every module's hook). |
| Devices | `DELETE …/devices/{id}` | Full revoke: hooks purge keys and mailbox, and the socket closes. |
| Recovery | `POST …/recovery-codes` | 48 hours, single use, shown once. |
| Invites | list, create (code shown once), cancel | Codes are stored hashed. |
| Reports | list (`status`), resolve or dismiss | The record holds two account ids; each row is answered with both people named (their own name, else their `~Helix name`) and numbered the way Accounts does, joined at read time from people and identity (ADR-030). |
| Payment requests | list (`status`, default `pending`), approve, reject (with a short reason) | billing's queue (ADR-035). Each row is answered with the person's name and number as Accounts does (ADR-030), so the operator can match a bKash or Nagad sender. Approve adds the months after the current end. |
| Plan | `PUT` / `DELETE …/accounts/{id}/plan` | Gives Premium time without a payment (1 to 36 months), or ends it now. |
| Billing settings | get, put | Prices (taka) and the bKash and Nagad numbers. The audit row says only whether a number is set. |
| Audit | list, newest first | |
| Config | get, patch `server_name`, `maintenance`, `federation_enabled` | `get` also says which outside services are set up (`integrations`: push, SMS, TURN), as a yes/no with the provider name or an address count. Never a key, address or secret; it cannot say whether a provider accepts its key. |
| Flags | get, set (allow-listed) | |
| Logs | recent lines, WS stream | This node only, already redacted. |
| Purge | `POST /v1/admin/purge` | Dead jobs and expired identity rows. Counts by kind. |

## Review notes

First-run setup is public, as in v1: on a fresh public server the first
caller of `POST /v1/admin/setup` becomes the operator. Set
`HELIX_ADMIN_PASSWORD` before exposing a new server, or run setup
straight away.

## Clients

The operator console is `helix_remote/admin` (Phase AD), on `HelixAdminApi` from
`helix_remote_api/v2.dart`. Its screens are tested against a fake in `admin/test/`;
`test/client/admin_console_v2_test.dart` drives the same calls against this module
(setup, lockout, session rules, paging, one-time codes, redaction).
