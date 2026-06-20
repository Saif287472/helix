# External Security Review Gate

Status: required before strong production claims

Helix Local and Helix Remote may not make strong marketing claims about forward
secrecy, cryptographic protocol novelty, production-reviewed cryptography,
complete forensic erasure, or enterprise readiness until independent external
review is complete.

## Required Review Inputs

- Current threat model.
- Protocol frame fixtures and malformed-frame tests.
- Authenticated key-agreement design notes.
- Storage and panic-wipe implementation notes.
- Release signing and rollback instructions.

## Required Review Outputs

- Reviewer name or organization.
- Reviewed commit hash.
- Scope and excluded areas.
- Findings and severity.
- Fixed findings with verification evidence.
- Explicit approval for any strengthened security claim.

## Phase 11 Gate

- Independent cryptographic review: BLOCKED until an external reviewer signs the
  reviewed commit, scope, findings, and closure evidence.
- Penetration test: BLOCKED until an external tester completes app/backend
  coverage and Critical/High findings are closed or explicitly risk-accepted.
- Security marketing claims remain blocked while any Critical/High finding is
  open in auth, crypto, storage, sync, wipe, deletion, or authorization.

## Phase 7 Gate

Phase 7 completes this item by blocking the unsupported claims in code and docs.
The external review itself remains a release prerequisite before public strong
claims are made.
