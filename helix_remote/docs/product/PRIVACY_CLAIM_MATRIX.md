# Helix Remote Privacy Claim Matrix

Status: Phase 9 release candidate review
Date: 2026-06-23

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
| Messages are end-to-end encrypted | Implemented | X3DH key agreement + per-message HKDF/AES-GCM session envelopes; decrypt-before-auth fixed in Phase 9-11; X3DH sig verification audited | Production-reviewed cryptography confirmed below |
| Only sender and recipient can read messages | Implemented | Server stores only ciphertext envelopes; backend `RedactedLogger` never logs plaintext | Same as above |
| No plaintext push payload | Implemented | `OutboxWorker.enqueueOutbox` rejects payloads containing `plaintext` key (`throwsArgumentError`); backend test `P18 plaintext report and push payloads are rejected` passes | Test in CI |
| No mandatory address-book upload | Implemented | Contacts sync is opt-in (rationale dialog + OS permission prompt, re-askable, degrades gracefully on denial); raw phone numbers are never sent - only salted HMAC-SHA256 hashes via `/contacts/match`, and matching is fully skippable | `PhoneContactsService`/`hashPhoneBookContacts` unit tests; `invites_tab_test.dart`-style fake-server test for the match flow |
| Phone numbers are never stored or transmitted in plaintext | Implemented | `phoneHash()` (client and server, byte-identical) is the only form a phone number takes off-device; see ADR-017's phone/OTP/invite redaction addendum | `contacts_discovery_salt_test.dart`, `phone_contacts_service_test.dart` known-answer vector |
| Production-reviewed cryptography | Partial | Primitives are `cryptography`/`cryptography_flutter` (well-reviewed library); X3DH/session-envelope implementation is Helix-owned; external review is pending | Full external cryptographic audit (Phase 9-11 blocked item) |

## Data and Storage Claims

| Claim | Status | Implementation | Gate |
| --- | --- | --- | --- |
| No sale of personal data | Implemented | No third-party data-sharing integrations exist; confirmed in `docs/product/PRIVACY_POLICY.md` | Reviewed before any third-party integration is added |
| User can export all their data | Implemented | `/api/v1/account/export` returns all server-held data as JSON | Manual smoke-test on release build |
| User can delete their account and data | Implemented | `/api/v1/account/delete` purges account, devices, messages, backups; confirmed in `privacy_compliance_test.dart` | Same |
| Backups are encrypted with user-held key | Implemented | `RemoteBackupCrypto` writes v2 Argon2id + AES-256-GCM envelopes, reads legacy PBKDF2 v1 envelopes, and server stores only ciphertext plus metadata | `remote_backup_restore_test.dart` passes |
| Locked and ephemeral chats stay out of normal exposure paths | Implemented | Schema v16 stores locked-chat, disappearing, view-once, keep-in-chat, and advanced privacy flags; normal lists/search/backups/export/call/notification paths enforce them | F3 tests in backup, storage, calls, and backend contacts suites pass |
| Advertising ID is not collected | Implemented | No ad-SDK dependency; `AndroidManifest.xml` has no `AD_ID` permission | Verified in `docs/product/APP_STORE_PRIVACY.md` |

## Session and Device Claims

| Claim | Status | Implementation | Gate |
| --- | --- | --- | --- |
| Sessions can be remotely revoked | Implemented | Device revoke and mark-lost endpoints purge tokens and queued messages | `privacy_compliance_test.dart` test passes |
| Each device has an independent identity key | Implemented | Device key generated at registration; `device_id` is separate from `account_id` | Verified in Phase 4 evidence |

## Claims Blocked For Strong Claim

The following claims **must not** appear in external marketing or store copy
until the gate condition is met:

| Blocked Claim | Reason | Gate |
| --- | --- | --- |
| "Military-grade encryption" or equivalent superlatives | Unverifiable and legally risky | Remove from all copy; do not add |
| "Zero-knowledge" | Not accurate: server sees metadata (timestamps, recipient IDs, message sizes) | Add only after metadata minimization work that satisfies ADR-017 scope |
| "Forward secrecy" (as a strong claim) | Current X3DH/session-envelope path does not yet implement the complete DH-ratchet/skipped-key behavior needed for this claim | Add only after full reviewed DH-ratchet multi-device integration test |
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
