# F1 Multi-Device Trust Design

Status: implemented for Phase F1.

## Capability And Schema

Phase F1 adds `helix.remote.multi-device-trust.v1` and advances the backend
schema capability to `helix.remote.backend-schema.v20`.

Schema v20 extends `pending_device_links` with fresh-device signing and
agreement public keys, a request nonce, an expiry timestamp, the approving
trusted device ID, an approval-transcript hash, rejection time, and completion
time. Legacy link rows are backfilled from the old single public-key column.

## Link Protocol

A fresh device uses `POST /accounts/devices/link/request-new` with its account
ID, new device ID, device name, Ed25519 signing public key, and X25519
agreement public key. The server rejects reused IDs, malformed keys, identical
keys, and accounts that have no active trusted device.

The server creates a ten-minute pending link with a human verification code and
QR payload, logs `DEVICE_LINK_REQUESTED`, and notifies all active trusted
devices with a `pending_device_link` event.

A trusted device approves with `POST /accounts/devices/link/verify` or rejects
with `POST /accounts/devices/link/reject`. Approval is bound to a transcript
containing account ID, approving old device ID, new device ID, both new public
keys, device name, nonce, expiry, and server audience. The transcript hash is
stored on the link row.

The fresh device completes with `POST /accounts/devices/link/complete-new` by
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

## Revocation

Device revocation and lost-device reporting now revoke refresh tokens, remove
queued mailbox messages, clear prekeys, clear the push token, expire pending
trust links touching that device, record a revocation row, and notify siblings.

Existing message fan-out already requires envelopes for every active recipient
device, including the sender's other devices. Existing call signaling rings all
eligible devices and marks non-winning devices as answered elsewhere.
