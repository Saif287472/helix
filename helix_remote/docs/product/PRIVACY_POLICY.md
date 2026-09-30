# Helix Remote Privacy Policy

Status: Phase 18 draft for product/release review  
Date: 2026-06-19

> The canonical, versioned Helix Global Privacy Policy is maintained at
> [`docs/legal/privacy_policy.md`](../legal/privacy_policy.md). This document
> remains an implementation-evidence checklist for the product and is not the
> text shown to Global registrants.

Helix Remote is a persistent internet messenger. This policy describes the
current implementation evidence in this repository. It is not a substitute for
jurisdiction-specific legal review before public launch.

## Data We Process

- Account identifiers: account ID, a salted hash of your phone number
  (`phone_hash`), account status, and public identity key.
  The raw phone number is sent to the server only when requesting an SMS code;
  the server checks it against the hash, passes it to the SMS gateway
  (BulkSMSBD) for delivery, and does not store it from that request.
- Password data (`account_passwords`): Argon2id parameters and salt, a salted
  SHA-256 of an auth key derived from your password, your account identity
  private key encrypted with a separate key derived from your password (the
  server cannot decrypt it), the identity public key, and failed-attempt /
  lockout counters. Your password is never sent to the server.
- Sessions (`refresh_tokens`): SHA-256 hashes of refresh tokens with their
  device and expiry. Access tokens last 1 hour; refresh tokens 60 days,
  rotated on every refresh.
- Chat history backup (`history_backups`): one encrypted, text-only blob per
  account with its size and the identity public key it was made under. It is
  encrypted on your devices with a key derived from your identity key; the
  server cannot read it. Media is not included.
- Device identifiers: device ID, device name, public device key, active/revoked
  state, push-token field when configured, and last-seen timestamp.
- Contacts and safety state: saved contacts, block state, privacy settings,
  abuse reports, and safety/admin actions, plus a record of whom you have
  messaged or called (`account_reach`) - that record is what lets someone you
  contacted see your number. If you opt into contacts sync, salted hashes of
  your phone-book numbers are checked against the server to find people
  already on Helix, and the people found are saved as your contacts - your
  phone-book names and any unmatched numbers never leave your device.
- Messaging metadata: conversation IDs, membership rows, message IDs,
  per-device recipient IDs, server sequence numbers, timestamps, and encrypted
  message envelopes.
- Attachments and backups: encrypted attachment object metadata and opaque
  encrypted backup payloads plus version/KDF metadata.
- Operational security records: redacted audit events for account, device,
  safety, export, deletion, and admin activity.

## Data We Do Not Process

- No mandatory address-book upload.
- No sale of personal data.
- No behavioral advertising or cross-context tracking.
- No plaintext push notification payloads.
- No plaintext message content in server message-send, push, report, or backup
  APIs covered by Phase 18 tests.
- No passwords, backup passphrases, recovery phrases, backup keys, access
  tokens, or private media bytes may be uploaded through supported flows. The
  only private key uploaded is the account identity key, and only encrypted
  under a password-derived key the server never receives.

## Retention and Deletion

Retention and deletion behavior is documented in
[`RETENTION_AND_DELETION.md`](RETENTION_AND_DELETION.md).

## User Controls

- Users can export server-visible account data through the Remote privacy export
  endpoint (`GET /api/v1/privacy/export`). It does not yet include the
  password row or the history backup.
- Users can request account deletion by confirming `DELETE <account_id>`.
- Users can revoke a device, sign out all other devices, or report a lost
  device, and are alerted on their other devices when a new device signs in.
- Users can remove contacts, block accounts, and configure search/presence
  privacy settings.

## Security Limits

- Remote client database-at-rest encryption is implemented with SQLCipher-backed
  local storage; strong E2EE and forward-secrecy claims remain blocked below.
- Independent external cryptographic/security review remains BLOCKED until an
  actual reviewer evaluates the exact implementation/version.
- A Double Ratchet with DH ratchet steps and skipped-message keys is
  implemented (`packages/helix_remote_crypto/lib/src/double_ratchet.dart`) but
  not externally reviewed, so forward-secrecy claims stay blocked.
- Do not describe Helix Remote as production-reviewed or legally compliant until
  the relevant reviews are complete.
