# Helix Remote Privacy Policy

Status: updated at Phase X (2026-10) for the v2 server; still a draft for product/release review

> The canonical, versioned Helix Global Privacy Policy is maintained at
> [`docs/legal/privacy_policy.md`](../legal/privacy_policy.md). This document
> remains an implementation-evidence checklist for the product and is not the
> text shown to Global registrants. The table-by-table inventory is
> [`METADATA_INVENTORY.md`](METADATA_INVENTORY.md).

Helix Remote is a persistent internet messenger. This policy describes the
current implementation evidence in this repository. It is not a substitute for
jurisdiction-specific legal review before public launch.

## Data We Process

- Account identifiers: account ID, a keyed hash of your phone number
  (`phone_hash`, under the server's secret pepper), the last four digits of the
  number, a pepper-keyed discovery index (absent if you turn phone discovery
  off), your `~Helix name`, account status, and public identity key.
  The raw phone number is sent to the server only when requesting an SMS code;
  the server hashes it, passes it to the SMS gateway (BulkSMSBD) for delivery,
  and does not store it from that request.
- Password data (`passwords`): Argon2id parameters and salt, an HMAC verifier of
  an auth key derived from your password, your account identity private key
  encrypted with a separate key derived from your password (the server cannot
  decrypt it), and failed-attempt / lockout counters. Your password is never
  sent to the server.
- Sessions (`refresh_tokens`): SHA-256 hashes of refresh tokens with their
  device and expiry. Access tokens last 15 minutes; refresh tokens 60 days,
  rotated on every use.
- Chat history backup (`history_backups`): one encrypted, text-only blob per
  account with its version and size. It is encrypted on your devices with a key
  derived from your identity key; the server cannot read it. Media is not
  included. The optional recovery backup (`full_backups`) is encrypted under a
  secret only you hold.
- Device identifiers: device ID, device name, platform, public device keys and
  certificate, active/revoked state, push token when configured, and the date
  (not the time) the device was last seen.
- People and safety state: blocks, privacy settings (discovery, presence, last
  seen), your encrypted profile, abuse reports and operator actions. There are no
  contact requests and no record of whom you have messaged. If you opt into
  contacts sync, salted hashes of your phone-book numbers are checked against the
  server to find people already on Helix (at most 5,000 a day) - your phone-book
  names and any unmatched numbers never leave your device.
- Messaging metadata: while a message is undelivered, the server holds the
  encrypted envelope with the recipient device, a per-device sequence number,
  the sending account and device, and timestamps. The envelope is deleted when
  the device acknowledges it (at most 30 days). The server keeps no
  conversation list and no message history.
- Attachments and backups: encrypted objects with random ids and sizes, which
  expire after 30 days (backup media 90 days), and opaque encrypted backup
  payloads plus version metadata.
- Operational security records: redacted logs, and an audit record of operator
  actions.

## Data We Do Not Process

- No mandatory address-book upload.
- No sale of personal data.
- No behavioral advertising or cross-context tracking.
- No plaintext push notification payloads (a wake-up carries only its kind).
- No plaintext message content in server message-send, push, report, or backup
  APIs.
- No passwords, backup passphrases, recovery phrases, backup keys, access
  tokens, or private media bytes may be uploaded through supported flows. The
  only private key uploaded is the account identity key, and only encrypted
  under a password-derived key the server never receives.

## Retention and Deletion

Retention and deletion behavior is documented in
[`RETENTION_AND_DELETION.md`](RETENTION_AND_DELETION.md).

## User Controls

- Users can export server-visible account data (`GET /v1/account/export`). It
  holds one section per module, metadata only: no secrets, tokens, ciphertext or
  other people's numbers.
- Users can delete their account by confirming with `DELETE` and proving
  ownership (password, a fresh phone verification, or a device-key signature).
- Users can revoke a device, sign out all other devices, or mark a device lost,
  and are alerted on their other devices when a new device signs in.
- Users can block accounts and configure discovery and presence privacy
  settings.

## Security Limits

- Remote client database-at-rest encryption is implemented with SQLCipher-backed
  local storage.
- Independent external cryptographic/security review has not happened. Until an
  actual reviewer evaluates the exact implementation/version, strong E2EE and
  forward-secrecy claims stay blocked (`PRIVACY_CLAIM_MATRIX.md`).
- Per-device-pair X3DH, a Double Ratchet with DH ratchet steps and bounded
  skipped keys, and Sender Keys for groups are implemented
  (`packages/helix_remote_crypto/lib/src/v2/`) but not externally reviewed.
- Do not describe Helix Remote as production-reviewed or legally compliant until
  the relevant reviews are complete.
