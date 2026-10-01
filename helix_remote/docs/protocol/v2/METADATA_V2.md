# Helix Remote v2 — What the server knows

Status: **specified 2026-10-01 (Phase P1), pending user review.** This is the
v2 counterpart of `docs/product/METADATA_INVENTORY.md` and the claims in
`PRIVACY_CLAIM_MATRIX.md`. Those product documents describe the live v1
system and are rewritten from this one at cutover (Phase X), once v2 is what
users run.

## Server-visible data, v1 → v2

| Data | v1 server | v2 server |
|---|---|---|
| Message content | ciphertext, kept until sender delete or device revoke (acks never deleted it) | ciphertext, **deleted on ack**, 30-day maximum |
| Conversation membership and per-chat sequence | yes (direct and group) | **no direct-chat table**; groups: roster only |
| Reactions, receipts, typing, edits, deletes | plaintext or server routes | **inside E2EE content** |
| View-once, disappearing deadlines | sent in the clear | **inside E2EE content** |
| Group name, picture, description | plaintext | **encrypted** with the group master key |
| Display name, about, avatar | plaintext profile | **encrypted** with the profile key |
| Call SDP, ICE candidates, caller name, audio/video | plaintext | **sealed pairwise**; server sees call id, parties, signal kind (offer/update/end) |
| Attachment ↔ message link | yes (`register-reference`) | **no**; random object ids, 30-day expiry |
| Attachment ids | content hash (links equal uploads) | random UUIDs |
| Phone number | hash + plaintext/last-4 paths | keyed hash + last 4 digits; plaintext only in memory while texting a code |
| Discovery salt | public endpoint | authenticated |
| Sibling devices' push tokens | listed to every device | never listed |
| Sender of a message | yes | yes (sealed sender reserved for later) |
| Recipients of a message | yes | yes, until delivered |
| Timing and size | yes | yes; sizes padded to 160-byte blocks |
| IP addresses | request logs | request logs (redacted per `redacted_logger`); no IP in the database except rate-limit buckets (TTL) |
| Federation (sender and recipient on different servers) | both servers see sender, recipients, devices, timing, size | the same: the sender's server sees the qualified recipient and device ids; the recipient's server sees the qualified sender and device. Ciphertext only. Undelivered relays wait in the sender server's job queue (at most 12 retries). Each server keeps a peer cache: domain, key, API base, last seen. |

## Claims v2 can make (once implemented and tested)

1. Message content, reactions, receipts, edits, deletes, typing, view-once
   and timers are end-to-end encrypted.
2. The server stores a message only until every recipient device has it
   (at most 30 days).
3. Group names and pictures, and profiles, are end-to-end encrypted.
4. Forward secrecy and post-compromise security for one-to-one messages
   (full Double Ratchet with DH steps). *Not claimable in v1.*
5. The server never learns the password (only an HKDF-derived key).
6. Each device has its own keys, certified by the account identity key;
   a changed identity key is announced and shown.
7. Push notifications carry no content.

Still not claimable: "externally reviewed cryptography", "zero-knowledge",
"anonymous" (the server sees who talks to whom), "military-grade".
