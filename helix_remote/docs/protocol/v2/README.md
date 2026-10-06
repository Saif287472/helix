# Helix Remote protocol v2

Status: **specified 2026-10-01 (Phase P1 of
`docs/architecture/ARCHITECTURE_V2_PLAN.md`), implemented, live since the Phase X
cutover; the P1 review items below are still pending the user's review.** This is
the truth for the server (`helix_remote/server/`) and the client stack. The F0-F11
design documents one level up describe the deleted v1 system and are historical.

| Document | Covers |
|---|---|
| [REST_V2.md](REST_V2.md) | Every REST route, conventions, rules |
| [REALTIME_V2.md](REALTIME_V2.md) | WebSocket frames, delivery, acks, close codes |
| [CONTENT_V2.md](CONTENT_V2.md) | Everything inside the encryption: message types, actions, control |
| [CRYPTO_V2.md](CRYPTO_V2.md) | Keys, X3DH, Double Ratchet, Sender Keys, linking, safety numbers, media, backups |
| [METADATA_V2.md](METADATA_V2.md) | What the server can see, v1 vs v2, and the privacy claims v2 supports |

Code: `packages/helix_remote_protocol` (DTOs, frames, content, route catalog).
Golden wire fixtures: `contracts/v2/fixtures/` (regenerate deliberately with
`HELIX_UPDATE_FIXTURES=1 dart test` in the protocol package).

## Review checklist for the user (P1 checkpoint, deferred)

These are the decisions with product or privacy weight that were made while
the user was away:

1. **No server message history.** A new device sees history only by
   device-to-device transfer or the encrypted history backup (ADR-028).
2. **Edits, reactions, receipts, deletes, typing move inside E2EE.** The
   server can no longer enforce the 15-minute edit / 2-day delete windows;
   receivers do.
3. **Encrypted profiles and group names** (profile keys, group master keys).
   Admin console can no longer show users' display names (it shows account
   ids, `~Helix names` and phone last-4).
4. **Attachments expire 30 days after upload** (v1 kept them while
   referenced). Media older than that is only on devices and in backups.
5. **"Contacts" privacy audience** uses a contact list the device uploads
   (phone-book matches), opt-in via choosing "contacts".
6. **Password-number lookup returns decoy parameters** instead of "no such
   account", so it no longer reveals who has a password.
7. **Group add privacy** (`everyone`/`contacts`/`nobody`, WhatsApp-style):
   people who disallow it are invited by link instead.
