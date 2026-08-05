# Module: auth

Status: current. Follows the template in `../messaging.module.md`; see the
[structural upgrade plan](../../../../../../docs/architecture/EARNMINUTE_STRUCTURAL_UPGRADE_PLAN.md)
for why these docs exist.

## Purpose

Account identity and session lifecycle: registration, the signed-challenge
login, token refresh, phone-number OTP, invite issue/lookup/redeem, the
multi-device linking flow, device revocation, and the display-name profile.

This module was already split into focused files before the upgrade plan
started — it is the pattern the `groups/` and `calls/` splits copied.

## Owned files

`../auth.dart` holds `AuthModuleBase` (what every mixin may assume exists),
the `AuthModule` class, and the router. Each file below is a `part` of it.

| File | Lines | Holds |
|---|---|---|
| `../auth.dart` | ~165 | Base contract, class, routes |
| `devices.dart` | ~790 | Device list/rename, the whole linking flow, revocation, lost-device |
| `registration.dart` | ~330 | `POST /register` |
| `challenge_login.dart` | ~215 | `GET /challenge` + `POST /login` |
| `phone_otp.dart` | ~170 | OTP issue and verify |
| `invites.dart` | ~115 | Invite lookup and Global auto-issue |
| `profile.dart` | ~105 | Display-name read/write |
| `refresh.dart` | ~100 | `POST /refresh` |

## Route table

Mounted **twice** by `server_impl.dart` — at `/api/v1/accounts` and at
`/api/v1/devices` — because the device routes are declared with a
`/devices/...` prefix inside the same router. The public paths below are the
ones `_authMiddleware` exempts by suffix.

| Method | Path | Handler | Auth |
|---|---|---|---|
| POST | `/register` | `_registerHandler` | public |
| POST | `/phone/otp/request` | `_requestPhoneOtpHandler` | public, 5/hour per phone hash |
| GET | `/invite/lookup` | `_lookupInviteHandler` | public |
| POST | `/invite/auto-issue` | `_autoIssueInviteHandler` | public, Global-instance only, IP rate limited |
| GET | `/challenge` | `_challengeHandler` | public |
| POST | `/login` | `_loginHandler` | public |
| POST | `/refresh` | `_refreshHandler` | public (the refresh token *is* the credential) |
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
| POST | `/devices/lost-device` | `_lostDeviceHandler` | session |
| PUT | `/devices/push-token` | `_updatePushTokenHandler` | session |
| POST | `/profile` | `_updateProfileHandler` | session |
| GET | `/profile` | `_getProfileHandler` | session |

## Error codes this module throws

The [`AppError`](../../app_error.dart) shape. `.badRequest` for missing or
malformed fields, `.forbidden` for a blocked phone number / invalid invite /
failed OTP / inactive device, `.conflict` for an already-registered phone
number, `.tooManyRequests` for the OTP and auto-issue limits, and a bare 502
with `RemoteErrorCode.smsDeliveryFailed` when the SMS gateway rejects a
send.

## Dependencies

- `BackendDatabase` (`../../database.dart`) — accounts, devices, challenges,
  OTP challenges, invite credentials.
- `JwtHelper` (`../../jwt.dart`) — session and refresh token issue/verify.
- `SmsProvider` (`../../sms_provider.dart`) — real OTP delivery. Defaults to
  `NoopSmsProvider`.
- `phone_hash.dart` — salted phone hashing.
- `invite_codes.dart` — invite code generation and validation.
- `server_name.dart` — the display name an invite lookup returns.
- `notifyDevice` callback — wired to `WebSocketRelay.sendToDevice`, used to
  tell sibling devices about links and revocations.

## Gotchas

- **`_requestNewDeviceLinkHandler` and `_completeNewDeviceLinkHandler` are
  intentionally unauthenticated.** A device being linked has no session yet
  — that is the point of the flow. They are gated instead by the
  verification code and a 10-minute link TTL, and an existing trusted device
  still has to approve.
- **A device link race resolves by `StateError`.** Two devices completing
  the same link means the loser sees the link already consumed; that branch
  converts it to a 403, and it is why the handler still has a `catch` after
  the blanket ones were removed.
- **The OTP code is returned in the response body when no SMS provider is
  configured.** That is a documented placeholder for local dev and
  SMS-less self-hosts, not a secure channel. When `smsProvider.isConfigured`
  is true the code is never in the response.
- **The SMS gateway's rejection reason *is* forwarded to the client**,
  unlike every other upstream error in the backend. It is how an operator
  discovers a bad API key or an unapproved sender ID from the app itself,
  and the provider's error text has never contained the API key.
- **`globalInstanceMode` is set once at process startup and is not
  reachable from any HTTP endpoint.** A self-hosted admin token must never
  be able to flip it and bypass that deployment's own invite-only
  registration requirement.
- **`_verifyPhoneOtp` verifies without consuming.** Registration marks the
  challenge consumed atomically with the rest of the account write, so a
  failure part-way through does not burn the user's code.
- **The invite is redeemed last**, after every other check has passed, so a
  wrong OTP guess never burns a scarce invite credential.
