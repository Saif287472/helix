# Helix Remote Privacy Claim Matrix

Status: Phase 9 release candidate review
Date: 2026-06-23 (rows updated 2026-09)

This matrix maps every public-facing or internal privacy and security claim to
its implementation status and the evidence that supports it. Claims marked
**Blocked for strong claim** must not appear in marketing, store listings, or
documentation until the evidence column is satisfied.

## How To Read This Table

| Column | Meaning |
| --- | --- |
| Claim | The exact wording used or proposed in user-facing material |
| Status | `Implemented`, `Partial`, `Planned`, or `Blocked for strong claim` |
| Implementation | What exists in code or docs today |
| Gate | What must be true before this claim can be made publicly |

## Messaging and Encryption Claims

| Claim | Status | Implementation | Gate |
| --- | --- | --- | --- |
| Messages are end-to-end encrypted | Implemented | X3DH key agreement + `DoubleRatchetSession` (DH ratchet steps, skipped-message keys, AES-GCM message keys); decrypt-before-auth fixed in Phase 9-11; X3DH sig verification audited | Production-reviewed cryptography confirmed below |
| Only sender and recipient can read messages | Implemented | Server stores only ciphertext envelopes; backend `RedactedLogger` never logs plaintext | Same as above |
| No plaintext push payload | Implemented | `OutboxWorker.enqueueOutbox` rejects payloads containing `plaintext` key (`throwsArgumentError`); backend test `P18 plaintext report and push payloads are rejected` passes | Test in CI |
| No mandatory address-book upload | Implemented | Contacts sync is opt-in (rationale dialog + OS permission prompt, re-askable, degrades gracefully on denial); raw phone numbers are never sent - only salted HMAC-SHA256 hashes via `/contacts/match`, and matching is fully skippable | `PhoneContactsService`/`hashPhoneBookContacts` unit tests; `invites_tab_test.dart`-style fake-server test for the match flow |
| Phone numbers are never stored in plaintext | Partial | `phoneHash()` (client and server, byte-identical) is the only form used for identity and matching. The raw number *is* transmitted once per SMS-code request (`/api/v1/accounts/phone/otp/request`) and handed to the SMS gateway for delivery, but not stored from that request. Registration stores the account's phone number in `accounts.phone_last4` (historical column name) for the admin console, account security and spam protection | `contacts_discovery_salt_test.dart`, `phone_contacts_service_test.dart` known-answer vector |
| Production-reviewed cryptography | Partial | Primitives are `cryptography`/`cryptography_flutter` (well-reviewed library); X3DH/session-envelope implementation is Helix-owned; external review is pending | Full external cryptographic audit (Phase 9-11 blocked item) |

## Data and Storage Claims

| Claim | Status | Implementation | Gate |
| --- | --- | --- | --- |
| No sale of personal data | Implemented | No third-party data-sharing integrations exist; confirmed in `docs/product/PRIVACY_POLICY.md` | Reviewed before any third-party integration is added |
| User can export all their data | Implemented | `GET /api/v1/privacy/export` returns every account-scoped server table as JSON (`exportAccountData` in `backend/lib/src/database/accounts_devices_repository.dart`, `export_version` 2), including password metadata and the encrypted history backup. Credential material (password verifier and wrapped key, token and code hashes, push/link tokens) is withheld and listed in `withheld` | `backend/test/privacy_compliance_test.dart`; manual smoke-test on release build |
| User can delete their account and data | Implemented | `DELETE /api/v1/account/delete` purges account, devices, messages, backups; the password row and history backup go by `ON DELETE CASCADE`; the app then purges local data (`purgeAfterAccountDeletion`); confirmed in `privacy_compliance_test.dart` | Same |
| Backups are encrypted with user-held key | Implemented | `RemoteBackupCrypto` writes v2 Argon2id + AES-256-GCM envelopes, reads legacy PBKDF2 v1 envelopes, and server stores only ciphertext plus metadata. The automatic text-history backup is AES-GCM under a key derived from the account identity key (`app/lib/app/history_backup_codec.dart`) | `remote_backup_restore_test.dart` passes |
| The server never learns the password | Implemented | Argon2id + HKDF on the device; only a derived auth key is sent and stored as a salted SHA-256; the identity key is uploaded only wrapped under a separate password-derived key (`backend/lib/src/modules/auth/password.dart`, `app/lib/app/password_vault.dart`) | External review of the password scheme |
| Locked and ephemeral chats stay out of normal exposure paths | Implemented | Schema v16 stores locked-chat, disappearing, view-once, keep-in-chat, and advanced privacy flags; normal lists/search/backups/export/call/notification paths enforce them | F3 tests in backup, storage, calls, and backend contacts suites pass |
| Advertising ID is not collected | Implemented | No ad-SDK dependency; `AndroidManifest.xml` has no `AD_ID` permission | Verified in `docs/product/APP_STORE_PRIVACY.md` |

## Session and Device Claims

| Claim | Status | Implementation | Gate |
| --- | --- | --- | --- |
| Sessions can be remotely revoked | Implemented | Device revoke, revoke-others and mark-lost endpoints purge tokens and queued messages | `privacy_compliance_test.dart` test passes |
| Each device has independent device keys | Implemented | Each device generates its own Ed25519 signing and X25519 agreement keys; `device_id` is separate from `account_id`. The account identity key is shared by the account's devices | Verified in Phase 4 evidence |
| You are told when a new device signs in | Implemented | Password sign-in writes a durable device event to every other device and enqueues a `new_sign_in` push | Backend auth tests |

## Claims Blocked For Strong Claim

The following claims **must not** appear in external marketing or store copy
until the gate condition is met:

| Blocked Claim | Reason | Gate |
| --- | --- | --- |
| "Military-grade encryption" or equivalent superlatives | Unverifiable and legally risky | Remove from all copy; do not add |
| "Zero-knowledge" | Not accurate: server sees metadata (timestamps, recipient IDs, message sizes) | Add only after metadata minimization work that satisfies ADR-017 scope |
| "Forward secrecy" (as a strong claim) | A DH ratchet with skipped-message keys is implemented but has not been externally reviewed or covered by a multi-device integration test | Add only after full reviewed DH-ratchet multi-device integration test |
| "Open source" | Code is not currently published | Add only after public repository is confirmed |

### Documented exception: onboarding "military-grade AES-256" line

The mobile onboarding screen (`OnboardingSecurityBadge`, added in the phone/
invite/contacts-sync overhaul's Phase 8) displays "Protected by military-grade
AES-256 encryption." This is a **known, explicit exception** to the blocked
claim above, added at the product owner's direct request rather than an
oversight - it is flagged here specifically so it is not silently
rediscovered and "fixed" without context. The same legal-risk reasoning above
still applies and is not resolved by this exception; if this claim is ever
challenged (store review, legal, press), the resolution is to reword the
onboarding copy, not to retroactively justify the superlative. AES-256 itself
is real and accurately named (see `docs/security/remote_cryptographic_design_review.md`
§1); "military-grade" is the unverifiable part.

## Release Gate Summary

Before submitting to Google Play:

- [x] `No plaintext push payload` — backend test passes
- [x] `No mandatory address-book upload` — no contacts permission in manifest
- [x] `Production-reviewed cryptography` (partial) — library-level; Helix implementation pending external review; claim is limited to "uses reviewed cryptographic libraries"
- [x] `Blocked for strong claim` language removed from store listing draft
- [ ] External cryptographic audit — deferred; scope and timeline in Phase 9-11 BLOCKED items
- [ ] Full X3DH multi-device integration test — deferred to post-launch
