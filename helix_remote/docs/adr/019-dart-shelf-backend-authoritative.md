# ADR 019: Dart/Shelf Backend Is the Authoritative Implementation

Status: accepted  
Date: 2026-06-20

> For the v2 server (`helix_remote/server/`, branch `architecture-v2`), the
> storage and topology parts of this ADR are superseded by ADR-025. This ADR
> keeps describing the live v1 `backend/` until the v2 cutover.

## Context

The repository contains an executable Dart/Shelf backend under
`helix_remote/backend` (originally `services/helix_remote_backend`). Older architecture text described a Go/Chi
backend with PostgreSQL, Redis, and S3 as if those were the current
implementation. Source inspection and tests show those statements are target
state only.

## Decision

Helix Remote retains the current Dart/Shelf modular monolith as the
authoritative backend for the next improvement cycle.

The Go/Chi backend reference, PostgreSQL, Redis, S3, production metrics, and
production deployment statements are superseded as implementation claims. They
may be discussed only as future target-state options until an ADR and
executable migration evidence prove otherwise.

Documentation must not claim that PostgreSQL, Redis, or object storage are
already implemented unless the claim links to production wiring and tests.
(Status 2026-09: Remote E2EE with X3DH and a persisted Double Ratchet is now
wired - `packages/helix_remote_crypto/lib/src/double_ratchet.dart`, used by
`app/lib/app/remote_messaging_service/message_crypto.dart` - but remains
without external review. Production runs SQLite with attachments on the local
filesystem.) SQLCipher database-at-rest encryption is
implemented by P2-01 and must continue to link to the storage tests that prove
wrong-key failure, binary marker absence, and plaintext migration rollback.

## Consequences

- Phase 0 guardrails and evidence ledgers measure the Dart/Shelf code path.
- Backend language rewrites are out of scope for Phases 0-4.
- Future storage or infrastructure changes must follow contract tests and
  migration evidence before docs present them as implemented.
