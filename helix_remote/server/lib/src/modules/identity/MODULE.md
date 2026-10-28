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
- **Phone numbers:** `HMAC(HELIX_PHONE_PEPPER, E.164)` (lookup), the
  discovery index and the last four digits are stored. The number from a
  code request exists in memory only while the code is texted (and while an
  account turns discovery back on, below). Since ADR-030 an app reports its
  account's own number once after signing in (`PUT /v1/account/phone-number`,
  `Accounts.setPhoneNumber`): only the number that hashes to the account's
  phone hash is taken, and it is kept in `accounts.phone_sealed` (migration
  3), AES-256-GCM under `HELIX_PHONE_KEY` with the account id as associated
  data (`domain/phone_seal.dart`), for the admin console (`AdminStore`
  opens it) and the account's own export. Without the key nothing is kept.
- **Discovery index:** clients hash contacts as `hex(HMAC(discovery_salt,
  E.164))` under the public salt. The server never stores that: it stores
  and looks up `hex(HMAC(K, client hash))` with `K = HMAC(HELIX_PHONE_PEPPER,
  "helix.v2.discovery-index")` (`discovery_index`, migration 2). A dump
  without the pepper cannot be used to test numbers. Accounts that turn
  discovery off have no index (null); turning it back on needs the account's
  own number, checked against `phone_hash`
  (`IdentityApi.setPhoneDiscoverable`). Pending phone challenges hold the
  same keyed form, never the salted hash.
- **Bearer secrets** (verification, sign-in, link, poll and refresh tokens,
  invite and recovery codes) are stored only as SHA-256 hashes.
- **Dead rows:** `identity.purge_expired` (6 h) deletes refresh tokens 7 days
  past their expiry, phone challenges 2 days past creation, an invite 30 days
  past its expiry when nobody redeemed it, and a recovery code 1 day past its
  expiry or its use (the last two were reachable only from the operator's
  purge button, so a public server accumulated every self-issued invite for
  ever). The operator's purge (`data/admin_store.dart`) counts the same four
  kinds and runs its own harsher token and challenge windows.
- **Revoking a device:** sets `tokens_valid_after`, revokes its refresh
  tokens and deletes its push token, inside one transaction with the
  `onDeviceRevoked` hooks (keys purge prekeys). It also publishes
  `device.revoked` on the bus after commit. A user, operator and inactivity
  revoke all go through `IdentityContext.revokeDevice` (device list change,
  security event and `device_revoked` signal to the account's other
  devices); `revokeAll` revokes in device-id order.
  `IdentityStore.revokeDevice` takes the account and matches on it
  (`WHERE id AND account_id AND status = 'active'`), so a caller that skipped
  its own check cannot revoke another account's device (AUD-2-3).
- **A device limit per plan** (`IdentityContext.maxDevices` is the default,
  ten, owner ruling Q7; with plans on, `EntitlementSource` says two for Free
  and ten for Orbit Premium, ADR-035): `addDevice` takes the account's row
  lock, counts the active devices and refuses one past the limit with
  `quota_exceeded` (`details.max_devices`), so two sign-ins at once cannot
  both take the last place. Nothing is revoked to make room; an account at
  the cap removes a device itself (AUD-2-2). Accounts over the limit (a
  Premium that ended, or Free when plans were switched on) keep their devices
  and cannot add more.
- **A text that did not leave costs nothing:** when the SMS gateway fails,
  `requestPhoneChallenge` deletes the challenge row (the resend gap reads it)
  and refunds the per-number and the daily budget tokens
  (`RateLimiter.refund`). The charge is still taken first, so concurrent
  callers cannot all pass the budget (AUD-2-1).
- **Verification purposes:** `IdentityContext.verificationFor(token,
  purposes:)` is how every flow reads a phone-verification token. Register
  accepts `register` and `sign_in`; recovery redeem `recover`, `register` and
  `sign_in`; a password change or ownership check `sign_in`, `reset_password`
  and `register` (clients still send `register` as the default). A code asked
  for to recover cannot change a password (AUD-2-8).
- **Seen-today write:** `Sessions.device` writes `last_seen_on` once a day per
  device and node (an in-process map, cleared when the day turns), not on
  every authenticated request (AUD-2-4). A link long-poll reads the ephemeral
  store once a second, against the server clock (AUD-2-5).
- **Deliveries lock devices:** `IdentityApi.lockActiveDevices` returns the
  active devices among a set and holds `FOR SHARE` on their rows (in id
  order) until the caller's transaction ends. Messaging stores envelopes
  only for those, so a revoke waits for a delivery in flight and its hooks
  then purge what it stored (review A-09).
- **Inactive devices** (`HELIX_DEVICE_INACTIVE_DAYS`, off by default): every
  6 hours `identity.revoke_inactive` revokes active devices whose last
  authentication (`last_seen_on`, or the day they were added) is older than
  that many days, reason `inactive`, up to 2,000 a run. An account's most
  recently used device is never revoked, so no account is left without one;
  each device is re-checked under its row lock first, so one that signed in
  meanwhile stays. This retires the device that is never opened but never
  signed out (an old PC), which otherwise collects every message to its
  account (review A-01).
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

All 29 identity routes from `Routes` are served. Every public route has a
per-IP policy (`IdentityLimits` in `http/identity_routes.dart`). Codes also
have per-number limits (5/hour, a resend gap of `HELIX_OTP_RESEND_SECONDS`,
default 30) and 5 attempts per challenge. Passwords lock after 5 failures:
15 minutes, doubling up to 24 hours. Password sign-in and password change
(a wrong current auth key) share that counter and lockout
(`IdentityContext.checkPassword`); password changes are also limited to 10
per hour per account.

**Texts.** A code goes only to a number whose calling code is in
`HELIX_SMS_COUNTRIES` (checked first; 503 `sms_unavailable` otherwise), and
the whole server texts at most `HELIX_SMS_DAILY_LIMIT` a day
(`identity.sms_daily`, one bucket). The budget is charged last, after the
ban, resend-gap and per-number checks, so a refused request spends nothing.

**Decoys.** A number without a password answers like one with a password:
a 32-byte salt derived from the pepper (`IdentityContext.decoyPasswordSalt`;
every client salt is 32 bytes), and a sign-in that runs the same transaction
against an id no account can have and locks after 5 failures on the same
schedule (`decoyPasswordFailure`; the counter is in the ephemeral store under
`identity:pwdecoy:`, compare-and-set, 25 hours).

**Account status (ADR-032).** `POST /v1/auth/account-status` answers
`account_exists` and `has_password` for a number before any code is texted, so
the app can send a new number to the code and an account with a password to the
password. That is a deliberate exception to the deniability the decoys above
protect: 30 per hour per IP, no account id and no last four digits, and it
grants nothing - `register` still demands a phone verification, password
sign-in still demands the auth key, and the sealed identity key is only ever
released to one of those two proofs. So there is no sessionless password reset:
the AIK seed exists only inside `passwords.wrapped_identity_key`, sealed under
the old password, and a code cannot open it. A number whose password is
forgotten either links from a device that still has it, or comes in through
`register` with `replace_existing` and starts a new identity.

**Recovery lookup** (`POST /v1/auth/recovery/lookup`, 10 per hour per IP) tells the
holder of a valid code whether a phone verification must accompany the redeem
and which account the code belongs to (`account_id`): the new device's
certificate must name the account, and a code names none. That is not
an enumeration oracle: the code is a 256-bit bearer secret, the account id is
not secret (discovery gives it to anyone who knows the number), and an unknown,
used or expired code gets the same bare `{"valid": false}`. The redeem itself
still demands the SMS verification of the account's own number when SMS is
configured, so the id alone (or the code alone) takes nothing over.

**Ownership proof** (`IdentityApi.confirmOwnership`, used by compliance
before `DELETE /v1/account`): a session token alone is not enough. An
account with a password gives `current_auth_key` (shared failure counter and
lockout), or a fresh phone verification token as for a password change. An
account with a verified number on a server that texts gives a single-use
`verification_token` for that number. Any other account (no password, and no
number or no SMS: personal servers) gives a `device_proof`: the answer to a
`POST /v1/auth/challenges` challenge, signed by the calling device's DSK
over `deleteAccountSignatureBody` (its own label, so a sign-in signature
confirms nothing). The weaker proof is never accepted where a stronger one
exists. Refusal is `invalid_credentials` with `details.accepted` naming the
proofs that would do.

## Hooks (all run inside identity's transaction)

`onDeviceAdded` (keys stores prekeys), `onDeviceRevoked`,
`onIdentityKeyChanged`, `onAccountSignal`, `onDeviceListChanged`,
`onAccountDeleted`. Messaging (S3) turns signals and changes into
envelopes; backup (S4) drops the AIK-keyed history backup on key change.

## Configuration

| Variable | Meaning |
|---|---|
| `HELIX_PHONE_PEPPER` | required: base64url, at least 32 random bytes |
| `HELIX_PHONE_KEY` | optional: base64url, exactly 32 random bytes; seals reported numbers for the admin console (ADR-030). Unset: none are kept |
| `HELIX_SMS_PROVIDER` | `none` or `bulksmsbd`, with `HELIX_SMS_API_KEY` and `HELIX_SMS_SENDER_ID` |
| `HELIX_TERMS_VERSION` | current terms (default `2026-09`) |
| `HELIX_OTP_RESEND_SECONDS` | resend gap (default 30) |
| `HELIX_SMS_DAILY_LIMIT` | codes texted per day by the whole server, 1 to 1000000 (default 500) |
| `HELIX_SMS_COUNTRIES` | calling codes that may get codes, `880,971` style, or `*` for all (default `880`) |
| `HELIX_DEVICE_INACTIVE_DAYS` | revoke devices unused for longer (14 to 3650); 0 or unset, the default: never |

Helix Global (`HELIX_GLOBAL_MODE=true`) refuses to start without SMS.

## Operator actions (`IdentityAdminApi`, `api.admin`)

Used only by the admin module: account list and detail (the `~Helix name`, the
last four digits and, where `HELIX_PHONE_KEY` opens `phone_sealed`, the full
number the app reported - ADR-030), `phoneNumbers` (the same numbers by account
id, for a report row's two people) and `helixNames` (the `~Helix name` by
account id, for naming a person whose app never reported a name), suspend and
unsuspend (status only;
suspended principals reach `allowSuspended` routes), ban (phone hash into
`banned_phones`, then full deletion), device revoke (same hooks and signals as
a user revoke,
reason `admin`), recovery codes, invites (list, create, cancel) and purging
expired rows. The account export section comes from
`data/admin_store.dart`: account, devices, push token kinds (never tokens),
password date and security events.

Session cut-offs are compared at millisecond precision (`authState`
truncates `tokens_valid_after`), the precision of a token's issue time.
