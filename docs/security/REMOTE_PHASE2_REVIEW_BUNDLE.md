# Helix Remote Phase 2 Security Review Bundle

Status: prepared for external review
Date: 2026-06-20

This bundle summarizes the Phase 2 code evidence for Remote local persistence,
key lifecycle, X3DH session establishment, fail-closed messaging, trust state,
and remaining cryptographic limitations.

## Scope

- Remote SQLCipher-backed local database.
- Versioned secure-storage key records and redacted key inventory.
- Signed prekey and one-time prekey publication lifecycle.
- Persisted local crypto-session/trust/prekey database state.
- X3DH signed-prekey verification and transcript binding.
- Outbound messaging fail-closed behavior when secure session material is
  unavailable.
- Message envelope domain separation and AES-GCM AAD fields.

## Primary Code Paths

- `packages/remote/helix_remote_storage/lib/src/database.dart`
- `packages/remote/helix_remote_crypto/lib/src/secure_key_storage.dart`
- `packages/remote/helix_remote_crypto/lib/src/prekey_manager.dart`
- `packages/remote/helix_remote_crypto/lib/src/x3dh.dart`
- `apps/helix_remote/lib/app/remote_messaging_service.dart`
- `apps/helix_remote/lib/app/composition_root.dart`
- `services/helix_remote_backend/lib/src/modules/prekeys.dart`
- `services/helix_remote_backend/lib/src/database.dart`

## Test Evidence

- `packages/remote/helix_remote_storage/test/remote_storage_test.dart`
  - SQLCipher wrong-key failure.
  - Plaintext marker binary scan.
  - Plaintext-to-encrypted copy migration.
  - Migration crash-injection rollback.
  - Persisted crypto session, local prekey, and trust-state reopen test.
- `packages/remote/helix_remote_crypto/test/remote_crypto_test.dart`
  - Signed prekey verification and invalid-signature rejection.
  - X3DH transcript context binding.
  - Versioned secure-key record inventory without private-key disclosure.
  - Signed prekey and one-time prekey generation, signature verification,
    expiry, and replenishment policy.
- `apps/helix_remote/test/remote_messaging_service_test.dart`
  - Missing secure session stores only encrypted local state and enqueues no
    network `SEND_MESSAGE`.
  - Trust decision/key-change state persists.
- `services/helix_remote_backend/test/integration_test.dart`
  - Prekey publication, per-device bundle retrieval, atomic one-time prekey
    consumption, and depleted-prekey behavior.

## Envelope AAD

Remote outbound X3DH message encryption binds AES-GCM AAD to:

- domain: `helix.remote.message.v1`
- message ID
- conversation ID
- sender device ID
- recipient device ID
- protocol version
- content type
- per-session counter

The X3DH master-secret derivation is also bound to protocol version,
conversation ID, sender device ID, and recipient device ID.

## Known Limitations

- P2-06 remains open: the current `DoubleRatchetSession` has authenticated
  symmetric chain ratchet tests and state-preservation checks, but it is not a
  complete Signal-compatible Double Ratchet implementation with DH ratchet
  headers, skipped-key storage limits in the production repository, official
  vectors, and audited interoperability evidence.
- Independent cryptographic review remains blocked until an external reviewer
  evaluates the exact implementation and commit.
- The Remote UI still needs dedicated key-change UX surfaces beyond persisted
  trust-state storage and service events.
- Strong public claims for forward secrecy or production-reviewed E2EE remain
  prohibited until P2-06 and external review are complete.

## Reviewer Inputs

- `docs/security/remote_cryptographic_design_review.md`
- `docs/security/REMOTE_SECURITY_AND_COMPLIANCE.md`
- `docs/product/PRIVACY_CLAIM_MATRIX.md`
- `HELIX_ENTERPRISE_IMPROVEMENT_MASTER_PLAN.md`
- Full verification output for the reviewed commit.

