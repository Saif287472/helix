# Helix Remote Privacy Policy

Status: Phase 18 draft for product/release review  
Date: 2026-06-19

Helix Remote is a persistent internet messenger. This policy describes the
current implementation evidence in this repository. It is not a substitute for
jurisdiction-specific legal review before public launch.

## Data We Process

- Account identifiers: account ID, a salted hash of your phone number
  (`phone_hash` - we never store or see your phone number itself), account
  status, and public identity key.
- Device identifiers: device ID, device name, public device key, active/revoked
  state, push-token field when configured, and last-seen timestamp.
- Contacts and safety state: contact requests, accepted contacts, block state,
  privacy settings, abuse reports, and safety/admin actions. If you opt into
  contacts sync, salted hashes of your phone-book numbers are checked against
  the server to find people already on Helix - your phone-book names and any
  unmatched numbers never leave your device.
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
- No backup passphrases, recovery phrases, backup keys, private keys, access
  tokens, or private media bytes may be uploaded through supported flows.

## Retention and Deletion

Retention and deletion behavior is documented in
`docs/product/remote/RETENTION_AND_DELETION.md`.

## User Controls

- Users can export server-visible account data through the Remote privacy export
  endpoint.
- Users can request account deletion by confirming `DELETE <account_id>`.
- Users can revoke a device or report a lost device.
- Users can remove contacts, block accounts, and configure search/presence
  privacy settings.

## Security Limits

- Remote client database-at-rest encryption is implemented with SQLCipher-backed
  local storage; strong E2EE and forward-secrecy claims remain blocked below.
- Independent external cryptographic/security review remains BLOCKED until an
  actual reviewer evaluates the exact implementation/version.
- Full DH/skipped-key ratchet support remains BLOCKED pending a reviewed
  implementation.
- Do not describe Helix Remote as production-reviewed or legally compliant until
  the relevant reviews are complete.
