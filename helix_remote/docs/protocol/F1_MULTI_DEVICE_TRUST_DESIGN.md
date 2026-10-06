# F1 Multi-Device Trust Design

> **Status: historical (v1 design).** This document records the v1 design and implementation. v1 was deleted at the Phase X cutover (SQLite backend, `helix_remote_storage`, `helix_remote_sync`, `helix_remote_groups`, per-conversation sessions); the last v1 commit is tagged `v1-final`. Schema numbers, file paths and endpoints below are v1. The v2 truth: [`v2/CRYPTO_V2.md`](v2/CRYPTO_V2.md) sections 2 and 2a (device certificates under the account identity key, QR linking) and 11 (password-wrapped identity key), and the identity module (`server/lib/src/modules/identity/MODULE.md`). The trust reasoning here (password sign-in adds a device, every other device is told, any device can revoke) still holds; the mechanisms changed.

Status: implemented for Phase F1. Extended in 2026-09 with password sign-in,
revoke-others, stale-device-list recovery and sign-in alerts (sections below).
The schema version named in the next section is historical: the backend is now
at `PRAGMA user_version` 47 and the app's local database at 31.

## Capability And Schema

Phase F1 adds `helix.remote.multi-device-trust.v1` and advances the backend
schema capability to `helix.remote.backend-schema.v20`.

Schema v20 extends `pending_device_links` with fresh-device signing and
agreement public keys, a request nonce, an expiry timestamp, the approving
trusted device ID, an approval-transcript hash, rejection time, and completion
time. Legacy link rows are backfilled from the old single public-key column.

## Link Protocol

All routes below are under `/api/v1/accounts` (the auth router is also mounted
at `/api/v1/devices`); see `backend/lib/src/modules/auth/MODULE.md`.

A fresh device uses `POST /api/v1/accounts/devices/link/request-new` with its account
ID, new device ID, device name, Ed25519 signing public key, and X25519
agreement public key. The server rejects reused IDs, malformed keys, identical
keys, and accounts that have no active trusted device.

The server creates a ten-minute pending link with a human verification code and
QR payload, logs `DEVICE_LINK_REQUESTED`, and notifies all active trusted
devices with a `pending_device_link` event.

A trusted device approves with `POST /api/v1/accounts/devices/link/verify` or rejects
with `POST /api/v1/accounts/devices/link/reject`. Approval is bound to a transcript
containing account ID, approving old device ID, new device ID, both new public
keys, device name, nonce, expiry, and server audience. The transcript hash is
stored on the link row.

The fresh device completes with `POST /api/v1/accounts/devices/link/complete-new` by
signing the approval transcript with its new Ed25519 key. Completion registers
the device, marks the link consumed, issues access and refresh tokens, logs both
the new and approving device, and notifies sibling devices.

## Safety Properties

- Replay is blocked because completion updates only `APPROVED` links to
  `LINKED`.
- Code guessing is bounded by the short-lived six-digit verifier and the
  ten-minute expiry.
- A fresh device cannot self-approve because approval requires an active bearer
  token from an existing device.
- Completion after revocation or expiry is rejected because the approver must
  still be active and the expiry must be in the future.
- Signed and one-time prekeys can be published only after completion because
  `/prekeys/publish` requires the newly issued bearer token.

## Password Sign-In (Adds A Device Without Approval)

Every account has a password (the app keeps the user on `PasswordRequiredGate`
in `app/lib/screens/password_screens.dart` until one is set). A new device can
join with phone number + password alone: no OTP and no approval from a trusted
device.

1. `POST /api/v1/accounts/password/params` with `phone_hash` returns
   `account_exists`, `has_password`, and the Argon2id salt and cost.
2. The app runs Argon2id (default m=19456 KiB, t=2, p=1, 64-byte output) in an
   isolate and splits the result with HKDF into an auth key and a wrap key
   (`app/lib/app/password_vault.dart`).
3. `POST /api/v1/accounts/password/login` sends `phone_hash`, the auth key, the
   new device ID/name, its Ed25519 and X25519 public keys, and an Ed25519
   signature over `passwordLoginTranscript` (binds the device keys to the phone
   hash). The server checks the auth key against its salted SHA-256, registers
   the device next to the existing ones, and returns a session plus
   `account_identity_public_key` and `wrapped_identity_key`.
4. The app unwraps the account identity private key with the wrap key
   (AES-256-GCM, AAD bound to the identity public key), publishes prekeys as the
   same account, and restores the encrypted history backup before the app opens
   (see `F2_BACKUP_RECOVERY_TRANSFER_DESIGN.md`).

Wrong passwords count toward a lockout (5 failures -> 15 minutes, doubling up to
24 hours) shared with `POST /api/v1/accounts/password/verify` and password
changes. Nobody else is signed out. By contrast, on Helix Global an SMS-OTP
sign-in to an existing account (and "Forgot password") moves the account onto
the new device: the identity key rotates and the other devices are signed out.

## Sign-In Alerts

A password sign-in calls `_announceNewSignIn` (`backend/lib/src/modules/auth.dart`):
each other active device gets a durable `device_linked` device event (seen on
next sync even if offline), a realtime copy if connected, and a `new_sign_in`
push through the outbox. The push carries no device name.

## Fan-Out And Stale Device Lists

A sender encrypts one envelope per active device of every member, including its
own other devices. If a device was added since the sender fetched prekey
bundles, `POST /api/v1/messages/send` answers 409 `device_list_stale` with
`missing_device_ids`; the client (`app/lib/app/remote_sync_gateway.dart`,
`remote_messaging_service/message_crypto.dart`) refetches bundles and rebuilds
the send once. Envelopes addressed to a member's signed-out device are dropped
rather than failing the send, and signed-out devices are excluded from bundles
(`getActiveDevices`).

## Revocation

`POST /api/v1/accounts/devices/revoke-others` signs out every other active
device of the account in one call (returns `revoked_count`).

Device revocation and lost-device reporting now revoke refresh tokens, remove
queued mailbox messages, clear prekeys, clear the push token, expire pending
trust links touching that device, record a revocation row, and notify siblings.

Existing message fan-out already requires envelopes for every active recipient
device, including the sender's other devices. Existing call signaling rings all
eligible devices and marks non-winning devices as answered elsewhere.
