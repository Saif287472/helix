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
  The raw phone number reaches the server when it sends an SMS code (it hashes
  the number and passes it to the SMS gateway, BulkSMSBD, for delivery) and,
  since ADR-030, once more when your app reports the number it signed in with
  (`PUT /v1/account/phone-number`, checked against the verified `phone_hash`).
  The server keeps that report **sealed** - AES-256-GCM under `HELIX_PHONE_KEY`
  with the account id as associated data (`identity` migration 3) - so a
  database dump or a backup alone does not give numbers up, and the account's
  number is decryptable only by the operator who holds that key. The reason is
  moderation: a report of abuse names an account, and the number is what lets
  the operator tell who it came from, act on it (suspend the account, ban the
  number) and answer the person who reported it. It is shown in the operator's
  admin console and nowhere else: never in a profile, never to another user,
  never in a server log. Without `HELIX_PHONE_KEY` nothing is kept and the
  console falls back to the last four digits.
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
- Plans and payments (only when the operator has switched plans on): your
  plan (Free or Orbit Premium) with its end date and where it came from, and
  each payment request you send - the months, the amount, bKash or Nagad, the
  transaction ID you typed, its state and the operator's short reason if it
  was rejected, a first-week trial marker (a keyed hash of your number, so the trial is once per number; it stays
  after the account is deleted and cannot be turned back into the number), and any limit the operator changed
  for your account. If you are on the Free plan, it also keeps your daily call-time claims and, for each call you
  start, whether it was voice or video and how many minutes it used, for a week after it ends, and who a call
  was offered to for 12 hours (what the server needs to ring them anyway). It never sees what you say or show.
  A transaction ID is not a phone number, and the app never sees
  or stores your wallet details: you pay in the bKash or Nagad app. The
  operator reads the request in the console, with your name and number, to
  match it to the payment. Requests are kept one year after they are decided,
  and everything is removed with the account.
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
- No plaintext phone number anywhere on the server: the number an account
  reports is stored only as ciphertext under `HELIX_PHONE_KEY`, there is no
  number column to read, and no log line contains one (the redacting logger).
- No behavioral advertising or cross-context tracking.
- No plaintext push notification payloads (a wake-up carries only its kind).
  A notification's sender name and text are read on the phone from its own
  encrypted copy; Settings > Notifications can turn them off.
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
