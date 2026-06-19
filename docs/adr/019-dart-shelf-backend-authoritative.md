# ADR 019: Dart/Shelf Backend Is the Authoritative Implementation

Status: accepted  
Date: 2026-06-20

## Context

The repository contains an executable Dart/Shelf backend under
`services/helix_remote_backend`. Older architecture text described a Go/Chi
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

Documentation must not claim that Remote E2EE, Double Ratchet persistence,
SQLCipher database encryption, PostgreSQL, Redis, or object storage are already
implemented unless the claim links to production wiring and tests.

## Consequences

- Phase 0 guardrails and evidence ledgers measure the Dart/Shelf code path.
- Backend language rewrites are out of scope for Phases 0-4.
- Future storage or infrastructure changes must follow contract tests and
  migration evidence before docs present them as implemented.

