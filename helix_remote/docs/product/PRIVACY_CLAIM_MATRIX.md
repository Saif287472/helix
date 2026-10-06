# Helix Remote Privacy Claim Matrix

Status: rewritten at Phase X (2026-10) for the v2 architecture, from
[`../protocol/v2/METADATA_V2.md`](../protocol/v2/METADATA_V2.md). The v1 matrix is in git history
(tag `v1-final`). Nothing here has had an external cryptographic review.

This matrix maps every public-facing or internal privacy and security claim to its
implementation status and the evidence that supports it. Claims marked **Blocked for strong
claim** must not appear in marketing, store listings, or documentation until the gate is met.
Test paths are relative to `helix_remote/`.

## How to read this table

| Column | Meaning |
| --- | --- |
| Claim | The wording used or proposed in user-facing material |
| Status | `Implemented`, `Partial`, `Planned`, or `Blocked for strong claim` |
| Implementation | What exists in code or docs today |
| Gate | What must be true before this claim can be made publicly |

## Messaging and encryption claims

| Claim | Status | Implementation | Gate |
| --- | --- | --- | --- |
| Messages are end-to-end encrypted | Implemented | One session per (local device, remote device): X3DH and a full Double Ratchet with DH steps and bounded skipped keys (`packages/helix_remote_crypto/lib/src/v2/`, `docs/protocol/v2/CRYPTO_V2.md`); group messages use Sender Keys. Known-answer and tamper tests: `packages/helix_remote_crypto/test/v2/session_test.dart`, `vectors_test.dart` | Production review of the cryptography, below |
| Reactions, receipts, edits, deletes, replies, typing, view-once and disappearing timers are end-to-end encrypted | Implemented | They are encrypted content types, not server routes (`docs/protocol/v2/CONTENT_V2.md`); the server routes only `message`, `roster_change`, `device_list_change`, `key_change`, `account_signal`. `server/test/client/engine/messaging_test.dart` ("reactions, edits and deletes travel both ways") | Same |
| Only sender and recipient can read messages | Implemented | The server stores ciphertext envelopes and public keys; the redacting logger never logs content (`server/test/platform/infra_test.dart`) | Same |
| The server keeps a message only until it is delivered | Implemented | The mailbox row is deleted on the device's acknowledgement; undelivered rows expire after 30 days (`server/test/modules/realtime_test.dart` "ack over the socket deletes them"; `server/test/modules/messaging_test.dart`) | A real-phone soak test |
| Forward secrecy and post-compromise security for one-to-one messages | Partial | Implemented (DH ratchet steps) and covered by the crypto tests; not claimable as a strong public claim until externally reviewed | External review of the ratchet and a multi-device soak |
| Group names, pictures and profiles are end-to-end encrypted | Implemented | Group state is a blob under the group master key; profiles are sealed with the owner's profile key (`server/test/modules/groups_test.dart`, `server/test/modules/people_test.dart` "profiles are opaque ciphertext") | Same |
| Calls are encrypted end to end and signalled in the dark | Implemented | WebRTC media is DTLS-SRTP; SDP, ICE candidates, caller name and audio/video are sealed pairwise, the server sees only the call id, parties and signal kind; calls are relay-only so peers never learn each other's addresses (`server/test/modules/calls_test.dart`, `packages/helix_remote_calls/test/ice_config_test.dart`) | Real-phone call tests |
| No plaintext push payload | Implemented | Push is data-only (`{t: message|call|call_ended}` plus a call id) and the app fetches and decrypts after waking (`docs/operations/V2_SERVER_HANDOFF.md`, "Push") | Test in CI |
| No mandatory address-book upload | Implemented | Contact sync is opt-in (the app explains first, then asks the OS), re-askable, and degrades gracefully on denial; only salted client hashes are sent, rate limited to 5,000 a day (`app/test/phone_book_test.dart`, `server/test/modules/people_test.dart`) | Same |
| Phone numbers are never stored in plaintext on the server | Partial | The server keeps `HMAC(pepper, number)` for lookup, a pepper-keyed discovery index, and the last four digits. The raw number reaches the server once per code request, to hash it and hand it to the SMS gateway, and is not persisted (`server/lib/src/modules/identity/MODULE.md`; `server/test/modules/people_test.dart` "a database dump holds nothing a phone number can be tested against without the pepper") | The SMS gateway necessarily sees the number |
| Production-reviewed cryptography | Partial | Primitives are the `cryptography` and `crypto` Dart packages (well-reviewed libraries); the protocol construction, session manager and Sender Keys implementation are Helix-owned and **not externally reviewed** | Full external cryptographic audit (`docs/security/EXTERNAL_SECURITY_REVIEW_GATE.md`) |

## Data and storage claims

| Claim | Status | Implementation | Gate |
| --- | --- | --- | --- |
| No sale of personal data | Implemented | No third-party data-sharing integrations; see `docs/product/PRIVACY_POLICY.md` | Reviewed before any third-party integration is added |
| The user can export their data | Implemented | `GET /v1/account/export` is one repeatable-read snapshot with a section per module; credential material (password verifier, token and code hashes, push tokens) is withheld (`server/test/modules/ops_admin_test.dart` "export holds every module section and no secrets") | Manual smoke test on a release build |
| The user can delete their account and data | Implemented | `DELETE /v1/account` needs fresh proof of ownership (password, a fresh phone verification, or a device-key signature) and purges every module's rows by event; the app then wipes local data (`server/test/modules/ops_admin_test.dart` "deleting the account needs the confirmation and purges it", `server/test/client/engine/security_test.dart`) | Same |
| Backups are encrypted with a user-held key | Implemented | The full backup is a v3 envelope (Argon2id + AES-256-GCM); the history backup is AES-GCM under a key derived from the account identity key; the server stores only ciphertext and refuses an envelope carrying a recovery phrase, passphrase or backup key (`server/test/modules/media_backup_test.dart`, `packages/helix_remote_engine/test/backup/`) | Same |
| The server never learns the password | Implemented | Argon2id and HKDF on the device; only a derived auth key is sent and the server stores an HMAC verifier; the AIK is uploaded only wrapped under a separate password-derived key (`server/lib/src/modules/identity/MODULE.md`; `server/test/modules/identity_test.dart` "password: set, decoys for strangers, sign in on a new device, lockout") | External review of the password scheme |
| Disappearing and view-once messages | Partial | Timers and view-once state are inside the encrypted content and enforced by the recipient's app (`server/test/client/engine/messaging_test.dart` "disappearing messages start counting when first displayed"). A recipient can still screenshot or keep a copy | State the limit in user copy |
| Locked chats stay out of normal exposure paths | Planned | **Not built in v2.** The plan's decision (a UI gate plus hiding the chat, no extra key beyond SQLCipher) has no implementation yet | Build it, then test |
| The local database is encrypted at rest | Implemented | SQLCipher with a 32-byte key in the platform keystore; the database fails closed rather than opening plaintext (`packages/helix_remote_db/test/encryption_test.dart`) | Same |
| Advertising ID is not collected | Implemented | No ad-SDK dependency; the manifest has no `AD_ID` permission (`docs/product/APP_STORE_PRIVACY.md`) | Verified in the store checklist |
| Crash reports are opt-in and contain no content | Implemented | The report is the exception type, the app version and the platform, sent only when the person turned it on and the server flag is on, at most one a minute; the server logs it redacted and never stores it (`app/test/settings/a3b_rules_test.dart`, `server/test/modules/ops_admin_test.dart`) | Same |

## Session and device claims

| Claim | Status | Implementation | Gate |
| --- | --- | --- | --- |
| Sessions can be remotely revoked | Implemented | Revoking a device ends its session, deletes its push token and prekeys and closes its socket on whichever node holds it (`server/test/modules/identity_test.dart` "revoking a device ends its session and removes it from bundles", `server/test/e2e/two_node_test.dart`) | Real-phone check |
| Each device has independent device keys | Implemented | Each device generates its own identity and signing keys; its certificate is signed by the account identity key and verified by the server and by peers (`packages/helix_remote_crypto/test/v2/layout_test.dart`) | Same |
| You are told when a new device signs in or a contact's key changes | Implemented | Security events and `device_list_change` signals reach the account's other devices; a changed identity key is announced in the chat and resets "verified" (`server/test/client/engine/security_test.dart`, `server/test/client/engine/devices_test.dart`) | Same |

## Claims blocked for strong claim

The following claims **must not** appear in external marketing or store copy until the gate
condition is met:

| Blocked claim | Reason | Gate |
| --- | --- | --- |
| "Military-grade encryption" or equivalent superlatives | Unverifiable and legally risky | Remove from all copy; do not add |
| "Zero-knowledge" or "anonymous" | The server sees who talks to whom while a message is delivered, plus timing and padded size | Only after sealed sender and a reviewed metadata design |
| "Externally audited" or "audited cryptography" | No external review has happened | A completed external audit |
| "Forward secrecy" and "post-compromise security" as strong public claims | Implemented and tested, but the construction is Helix-owned and unreviewed | External review |
| "Open source" | Code is not currently published | Only after the public repository is confirmed |

The v1 onboarding line "Protected by military-grade AES-256 encryption" (a documented
exception added at the product owner's request) does not exist in the v2 app. If it is ever
re-added, the rule above still applies and the exception must be recorded here again.

## Release gate summary

Before submitting to Google Play:

- [x] No plaintext push payload (data-only wake-ups)
- [x] No mandatory address-book upload
- [x] "Production-reviewed cryptography" is limited to "uses reviewed cryptographic libraries"
- [x] Blocked-for-strong-claim wording stays out of store copy
- [ ] External cryptographic audit: not done; the claims above stay limited until it is
- [ ] Multi-device soak on real phones (including calls and lock-screen behaviour)
