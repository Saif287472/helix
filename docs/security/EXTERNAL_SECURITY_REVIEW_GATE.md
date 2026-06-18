# External Security Review Gate

Status: required before strong production claims

Helix Local may not make strong marketing claims about forward secrecy,
cryptographic protocol novelty, or complete forensic erasure until an external
security review is complete.

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

## Phase 7 Gate

Phase 7 completes this item by blocking the unsupported claims in code and docs.
The external review itself remains a release prerequisite before public strong
claims are made.
