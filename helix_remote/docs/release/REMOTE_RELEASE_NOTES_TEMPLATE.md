# Helix Remote Release Notes Template

Release: `vX.Y.Z`
Commit: `commit-hash`
Date: `YYYY-MM-DD`

## Summary

- User-visible changes:
- Server/API changes (new migrations, new `.env` lines):
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
  - Independent external crypto/security review (so no "audited" or strong
    forward-secrecy claims).
  - Staging deployment, until real infrastructure exists.

## Rollback

- Previous known-good release:
- Rollback artifact locations:
- Database schema compatibility:
- Operator:
