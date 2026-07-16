# Helix Remote Release Notes Template

Release: `vX.Y.Z`
Commit: `commit-hash`
Date: `YYYY-MM-DD`

## Summary

- User-visible changes:
- Backend/API changes:
- Compatibility notes:

## Verification

- `.\scripts\verify.ps1`:
- `.\scripts\remote_release_gate.ps1`:
- Remote Android release build:
- Remote Windows release build:
- Staging E2E:
- Security gates:

## Privacy and Security Claims

- Claims verified against `docs/product/PRIVACY_CLAIM_MATRIX.md`:
- Known blockers retained:
  - SQLCipher-capable database-at-rest encryption.
  - Independent external crypto/security review.
  - Full DH/skipped-key ratchet support.
  - Staging deployment, until real infrastructure exists.

## Rollback

- Previous known-good release:
- Rollback artifact locations:
- Database schema compatibility:
- Operator:
