# identity module

Accounts, devices, sessions and every way of signing in. Schema `identity`.
Facade: `api.dart` (`IdentityApi`). It is the only file other modules
import.

## Invariants

- **One mint point:** sessions come only from `SessionIssuer.issue`
  (`application/sessions.dart`). An architecture test fails if
  `AccessClaims(` appears anywhere else.
- **The password never arrives:** clients send `auth_key` (HKDF of
  Argon2id). The server stores `HMAC(verifier_salt, label ‖ auth_key)` and
  compares in constant time.
- **Device trust:** a device is added only if its certificate verifies
  under the account's AIK *and* its proof verifies under its own DSK
  (`domain/secrets.dart`, CRYPTO_V2.md §2).
- **Phone numbers:** only `HMAC(HELIX_PHONE_PEPPER, E.164)` (lookup), the
  discovery hash (HMAC with the discovery salt, for the people module) and
  the last four digits are stored. The number exists in memory only while
  a code is texted.
- **Bearer secrets** (verification, sign-in, link, poll and refresh tokens,
  invite and recovery codes) are stored only as SHA-256 hashes.
- **Revoking a device:** sets `tokens_valid_after`, revokes its refresh
  tokens and deletes its push token, inside one transaction with the
  `onDeviceRevoked` hooks (keys purge prekeys). It also publishes
  `device.revoked` on the bus after commit.
- **Refresh rotation:** reusing an old refresh token ends every session of
  that device (theft response), and the cut-off is committed before the
  error is returned.
- **Ending sessions** (sign-out, refresh reuse) goes through
  `SessionIssuer.endSessions`: after commit it publishes
  `identity.sessions_ended` with the device and the cut-off (epoch ms), and
  realtime closes that device's socket (4001) on whichever node holds it.
  Sign-out also signals `signed_out` to the account's other devices.
- **Suspension** (operator): signals `suspended` / `unsuspended` to every
  device; suspending publishes `identity.account_suspended` (sockets close
  with 4004). Topics are in `api.dart` (`IdentityTopics`).
- **Suspended accounts:** they authenticate with `suspended: true`. Only
  routes registered with `allowSuspended` accept them (account info,
  devices, sign-out, security events, push token, revoke).

## Tables

`accounts`, `devices`, `push_tokens`, `refresh_tokens`, `passwords`,
`invites`, `recovery_codes`, `phone_challenges`, `banned_phones`,
`security_events`, `settings` (discovery salt). Short-lived state lives in
the ephemeral store:

| Key | Holds |
|---|---|
| `identity:vt:` | verified phone |
| `identity:st:` | sign-in token → account |
| `identity:lt:` | link token → account |
| `identity:link:` | link state |
| `identity:chal:` | device challenge, by random challenge id (holds the device id and the challenge) |

## Routes and limits

All 28 identity routes from `Routes` are served. Every public route has a
per-IP policy (`IdentityLimits` in `http/identity_routes.dart`). Codes also
have per-number limits (5/hour, a resend gap of `HELIX_OTP_RESEND_SECONDS`,
default 30) and 5 attempts per challenge. Passwords lock after 5 failures:
15 minutes, doubling up to 24 hours. Password sign-in and password change
(a wrong current auth key) share that counter and lockout
(`IdentityContext.checkPassword`); password changes are also limited to 10
per hour per account.

## Hooks (all run inside identity's transaction)

`onDeviceAdded` (keys stores prekeys), `onDeviceRevoked`,
`onIdentityKeyChanged`, `onAccountSignal`, `onDeviceListChanged`,
`onAccountDeleted`. Messaging (S3) turns signals and changes into
envelopes; backup (S4) drops the AIK-keyed history backup on key change.

## Configuration

| Variable | Meaning |
|---|---|
| `HELIX_PHONE_PEPPER` | required: base64url, at least 32 random bytes |
| `HELIX_SMS_PROVIDER` | `none` or `bulksmsbd`, with `HELIX_SMS_API_KEY` and `HELIX_SMS_SENDER_ID` |
| `HELIX_TERMS_VERSION` | current terms (default `2026-09`) |
| `HELIX_OTP_RESEND_SECONDS` | resend gap (default 30) |

Helix Global (`HELIX_GLOBAL_MODE=true`) refuses to start without SMS.

## Operator actions (`IdentityAdminApi`, `api.admin`)

Used only by the admin module: account list and detail (last four digits,
never the number), suspend and unsuspend (status only; suspended principals
reach `allowSuspended` routes), ban (phone hash into `banned_phones`, then
full deletion), device revoke (same hooks and signals as a user revoke,
reason `admin`), recovery codes, invites (list, create, cancel) and purging
expired rows. The account export section comes from
`data/admin_store.dart`: account, devices, push token kinds (never tokens),
password date and security events.

Session cut-offs are compared at millisecond precision (`authState`
truncates `tokens_valid_after`), the precision of a token's issue time.
