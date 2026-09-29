# Module: auth

Status: current. Follows the template in `../messaging.module.md`; see the
[structural upgrade plan](../../../../../../docs/architecture/EARNMINUTE_STRUCTURAL_UPGRADE_PLAN.md)
for why these docs exist.

## Purpose

Account identity and session lifecycle: registration, password sign-in and
password management, the signed-challenge device login, token refresh,
phone-number OTP, invite issue/lookup/redeem, the multi-device linking flow,
device revocation (one device or all others), sign-in alerts, and the
display-name profile.

This module was already split into focused files before the upgrade plan
started — it is the pattern the `groups/` and `calls/` splits copied.

## Owned files

`../auth.dart` holds `AuthModuleBase` (what every mixin may assume exists),
the `AuthModule` class, and the router. Each file below is a `part` of it.

| File | Lines | Holds |
|---|---|---|
| `../auth.dart` | ~305 | Base contract (`_issueDeviceSession`, `_requireActiveDevice`, `_announceNewSignIn`), class, routes |
| `devices.dart` | ~765 | Device list/rename, the whole linking flow, revocation, revoke-others, lost-device |
| `registration.dart` | ~470 | `POST /register` (new account, and the Global SMS-OTP sign-in that moves the account onto the new device) |
| `password.dart` | ~445 | Password params, sign-in, verify, status, set/change, lockout |
| `phone_otp.dart` | ~225 | OTP issue and verify |
| `challenge_login.dart` | ~195 | `GET /challenge` + `POST /login` (Ed25519 device challenge) |
| `invites.dart` | ~140 | Invite lookup and Global auto-issue |
| `recovery.dart` | ~200 | `POST /recovery/lookup`, `POST /recovery/redeem` |
| `profile.dart` | ~110 | Display-name read/write |
| `refresh.dart` | ~65 | `POST /refresh` |

## Sessions

`_issueDeviceSession` (in `../auth.dart`) is the one place a session is minted
(login, refresh, device linking, password sign-in). Access token: 1 hour.
Refresh token: 60 days, sliding - every refresh revokes the used token and
issues a new one, so the 60 days count from the last refresh. Refresh tokens
are stored only as a SHA-256 hash (`refresh_tokens`); presenting an already
rotated token revokes every refresh token of that device. A device whose
refresh token lapsed signs in again with its Ed25519 device key
(`/challenge` + `/login`), not a new SMS code.

## Password sign-in

The server never sees the password. The app (`helix_remote/app/lib/app/password_vault.dart`,
`helix_remote/app/lib/app/composition_root/password_auth.dart`) runs Argon2id with the
salt and cost from `/password/params` (default m=19456 KiB, t=2, p=1, 64-byte
output; `_isAcceptableKdf` refuses anything cheaper) and splits the output with
HKDF into an **auth key**, sent and stored here only as a salted SHA-256
(`_hashAuthKey`), and a **wrap key**, never sent, which AES-256-GCM-encrypts the
account identity private key (AAD bound to the identity public key). That
ciphertext is stored in `account_passwords.wrapped_identity_key` and returned
by `/password/login`, so a new device that knows the password unlocks the same
identity and joins next to the account's other devices; nobody is signed out.
The login request carries an Ed25519 signature over
`passwordLoginTranscript` binding the new device's keys to the phone hash.

Lockout (`_checkPasswordAttempt`, shared by login, verify and change): 5 wrong
attempts lock the account for 15 minutes, doubling with each further failure
up to 24 hours (429 `passwordLocked` with `locked_until`). `/password/params`
and the login/verify routes are also rate limited per IP.

Changing a password needs the current auth key, or a fresh SMS OTP for the
account's number ("forgot password"). When the identity key rotates
(`updateAccountIdentityKey` in `database/accounts_devices_repository.dart`) the
`account_passwords` and `history_backups` rows for the old key are deleted.

## Route table

Mounted **twice** by `server_impl.dart` — at `/api/v1/accounts` and at
`/api/v1/devices` — because the device routes are declared with a
`/devices/...` prefix inside the same router. The public paths below are the
ones `_authMiddleware` exempts by suffix.

| Method | Path | Handler | Auth |
|---|---|---|---|
| POST | `/register` | `_registerHandler` | public |
| POST | `/phone/otp/request` | `_requestPhoneOtpHandler` | public, 5/hour per phone hash |
| POST | `/phone/otp/verify` | `_verifyPhoneOtpHandler` | public; checks without consuming |
| POST, GET | `/invite/lookup` | `_lookupInviteHandler` | public (POST is current; GET kept for old clients) |
| POST | `/invite/auto-issue` | `_autoIssueInviteHandler` | public, Global-instance only, IP rate limited |
| GET | `/challenge` | `_challengeHandler` | public |
| POST | `/login` | `_loginHandler` | public |
| POST | `/refresh` | `_refreshHandler` | public (the refresh token *is* the credential) |
| POST | `/recovery/lookup` | `_lookupRecoveryHandler` | public, IP rate limited; checks a code (and optionally that `phone_hash` is the account's) without using it; returns `valid`, `server_name`, `sms_required`, `phone_matches` |
| POST | `/recovery/redeem` | `_redeemRecoveryHandler` | public; needs the account's `phone_hash` and, when SMS is configured, `otp_code` + `otp_challenge_id`; resets the account onto the new device and signs every other device out |
| POST | `/password/params` | `_passwordParamsHandler` | public, IP rate limited |
| POST | `/password/login` | `_passwordLoginHandler` | public, IP rate limited + account lockout |
| POST | `/password/verify` | `_passwordVerifyHandler` | public, IP rate limited + account lockout |
| GET | `/password` | `_passwordStatusHandler` | session |
| POST | `/password` | `_setPasswordHandler` | session (+ current password or SMS OTP to change) |
| GET | `/devices` | `_listDevicesHandler` | session |
| POST | `/devices/rename` | `_renameDeviceHandler` | session |
| GET | `/devices/security-history` | `_deviceSecurityHistoryHandler` | session |
| POST | `/devices/link/request` | `_requestDeviceLinkHandler` | session (existing device starts the link) |
| POST | `/devices/link/request-new` | `_requestNewDeviceLinkHandler` | **public** — the new device has no session yet |
| POST | `/devices/link/verify` | `_verifyDeviceLinkHandler` | session |
| POST | `/devices/link/reject` | `_rejectDeviceLinkHandler` | session |
| POST | `/devices/link/complete` | `_completeDeviceLinkHandler` | session |
| POST | `/devices/link/complete-new` | `_completeNewDeviceLinkHandler` | **public** — same reason |
| POST | `/devices/revoke` | `_revokeDeviceHandler` | session |
| POST | `/devices/revoke-others` | `_revokeOtherDevicesHandler` | session; signs out every other active device, returns `revoked_count` |
| POST | `/devices/lost-device` | `_lostDeviceHandler` | session |
| PUT | `/devices/push-token` | `_updatePushTokenHandler` | session |
| POST | `/profile` | `_updateProfileHandler` | session |
| GET | `/profile` | `_getProfileHandler` | session |

> Sign-in (2026-09-28): the app opens on a single Helix Global page (phone number, then password or SMS code, then name/terms for new accounts). A personal server is reached through the hidden advanced mode (three taps in the bottom-right corner reveal an "Advanced mode" button; a fourth opens it) or through a shared link `https://helix.agiletechbd.com/open#HLX-…`. Advanced mode has one code field that tells an invite (`HLX-INV-`) from a recovery code (`HLX-REC-`), then the same phone and password/SMS pages. A recovery code names the server and account; the phone number must match the account (`POST /accounts/recovery/lookup`). With a password it is an ordinary password sign-in - nothing is reset. Without one, or via "Forgot password", `POST /accounts/recovery/redeem` resets the account onto the new device (new identity key, all other devices signed out) and requires the SMS code whenever the server has an SMS provider.

## Error codes this module throws

The [`AppError`](../../app_error.dart) shape. `.badRequest` for missing or
malformed fields (400 `discoverySaltStale` when the client's phone hash was
made with an old discovery salt), `.forbidden` for a blocked phone number /
invalid invite / failed OTP / inactive device (`deviceRevoked`,
`accountBlocked`) / wrong password (`passwordIncorrect`, with
`attempts_before_lockout`), `.conflict` for an already-registered phone number
or device id, `.tooManyRequests` for the OTP, auto-issue and password rate
limits, 429 `passwordLocked` during a lockout, 502 `smsDeliveryFailed` when the
SMS gateway rejects a send, and 503 `smsDeliveryFailed` when no SMS provider
is configured.

## Dependencies

- `BackendDatabase` (`../../database.dart`) — accounts, devices, challenges,
  OTP challenges, invite credentials.
- `JwtHelper` (`../../jwt.dart`) — session and refresh token issue/verify.
- `SmsProvider` (`../../sms_provider.dart`) — real OTP delivery (BulkSMSBD).
  Defaults to `NoopSmsProvider`, in which case OTP requests get a 503.
- `phone_hash.dart` — salted phone hashing.
- `invite_codes.dart` — invite code generation and validation.
- `server_name.dart` — the display name an invite lookup returns.
- `notifyDevice` callback — wired to `WebSocketRelay.sendToDevice`, used to
  tell sibling devices about links, revocations and new sign-ins.
- The outbox (`db.enqueueOutbox`) — `_announceNewSignIn` writes a durable
  `device_linked` device event for each other active device and enqueues a
  `new_sign_in` push (no device name in the push) for each.

## Gotchas

- **`_requestNewDeviceLinkHandler` and `_completeNewDeviceLinkHandler` are
  intentionally unauthenticated.** A device being linked has no session yet
  — that is the point of the flow. They are gated instead by the
  verification code and a 10-minute link TTL, and an existing trusted device
  still has to approve. (Password sign-in is the other way to add a device
  and needs no approval.)
- **A device link race resolves by `StateError`.** Two devices completing
  the same link means the loser sees the link already consumed; that branch
  converts it to a 403, and it is why the handler still has a `catch` after
  the blanket ones were removed.
- **The OTP code is never returned in a response.** Without a configured SMS
  provider `/phone/otp/request` refuses with 503. The raw `phone_number` in
  the request is used only to send the SMS and to check it hashes to
  `phone_hash`; it is never stored.
- **The SMS gateway's rejection reason is *not* forwarded to the client.**
  Its raw body can contain the API key, so it goes to the server log only;
  the client gets a stable 502 `smsDeliveryFailed` message.
- **Password sign-in and SMS sign-in differ for other devices.** A password
  sign-in (`/password/login`) adds the device and announces it to the others.
  On Helix Global an SMS-OTP sign-in to an existing account (`/register`
  with a phone that already owns an account) rotates the account identity to
  the new device and revokes the others, which also drops the old password
  and history backup (see "Password sign-in" above).
- **`/password/params` answers `account_exists` for a phone hash.** Phone
  discovery already reveals that; `/password/login` returns the same error for
  an unknown number and a wrong password.
- **`globalInstanceMode` is set once at process startup and is not
  reachable from any HTTP endpoint.** A self-hosted admin token must never
  be able to flip it and bypass that deployment's own invite-only
  registration requirement.
- **`_verifyPhoneOtp` verifies without consuming.** Registration marks the
  challenge consumed atomically with the rest of the account write, so a
  failure part-way through does not burn the user's code.
- **The invite is redeemed last**, after every other check has passed, so a
  wrong OTP guess never burns a scarce invite credential.
