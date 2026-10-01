# ADR 028: Protocol v2 — contract reset, mailbox delivery, device-pair sessions, Sender Keys

Status: accepted (2026-09-30). Details are specified in plan Phase P1. Crypto
changes stay **without external review** until one happens, and docs must
keep saying so.

Plan of record: `docs/architecture/ARCHITECTURE_V2_PLAN.md` (§4.4, §4.5, §5).

## Context

In v1:
- The server stores every message per recipient device, plus a
  `device_events` copy, and never deletes either on ack.
- Edits, reactions, receipts and deletes are server routes, so the server
  sees them as metadata.
- The client Double Ratchet performs only symmetric chain steps, with no DH
  ratchet step, so there is no post-compromise security.
- Sessions are keyed per conversation × device pair.
- Group messages are encrypted pairwise for every member device.
- Prekey replenishment is never wired.

There are no real users (plan D2), so the wire contract can be reset instead
of versioned alongside the old one.

## Decision

- **Contract reset:** a new REST surface under `/v1/`, a new OpenAPI file, a
  new realtime protocol negotiated as `Sec-WebSocket-Protocol: helix.v1+json`,
  and all DTOs in the shared `helix_remote_protocol` package. The
  compatibility policy (`remote_compatibility_policy.md`) applies from this
  new baseline forward: ignore-and-ack unknown frames, and no silent semantic
  changes.
- **Mailbox delivery:**
  - The server keeps only *undelivered* envelopes: one row per recipient
    device, including the sender's other devices. A device-level sequence is
    allocated under a row lock. Rows are deleted on ack and expire after
    30 days.
  - One event stream per device carries messages, sender-key distributions,
    roster changes, device-list changes and key changes.
- **End-to-end-encrypted control content:** edits, reactions, receipts,
  replies, deletes, polls, locations, stickers and system notes are content
  types *inside* the encrypted payload. Typing and presence are ephemeral
  frames that are never stored.
- **Sessions:** X3DH plus a full Double Ratchet (DH ratchet steps,
  skipped-key caps), one session per (local device, remote device). The
  conversation id travels inside the ciphertext. The server emits
  `keys.prekeys_low`, and clients replenish.
- **Groups:**
  - Sender Keys, distributed over pairwise sessions, rotated on member
    removal and on device changes. The server fans out one ciphertext per
    member device.
  - Group crypto sits behind `GroupCryptoProtocol`, so MLS can be added later.
- **History for a new device:** only via device-to-device transfer or the
  encrypted history backup (F2). The server keeps no message history.
  *(Resolved 2026-09-30, plan §13.)*

## Consequences

- The server learns less. `METADATA_INVENTORY.md`, `PRIVACY_CLAIM_MATRIX.md`,
  `DATA_FLOW.md` and the F1–F5 protocol docs are rewritten in Phase P1.
- A linked device sees only messages from its link time forward, unless the
  user transfers or restores history. The UI must say so.
- Each crypto change needs test vectors and a note in
  `docs/security/remote_cryptographic_design_review.md`.
