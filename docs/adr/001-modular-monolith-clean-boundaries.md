# ADR 001: Modular Monolith With Clean Boundaries

Status: accepted
Date: 2026-06-15

## Context

Helix is growing from a prototype into a larger local-only encrypted
messenger. The current codebase works, but services mix transport, application,
protocol, storage, and platform behavior. Moving directly to many internal
packages would be expensive and risky while the boundaries are still moving.

## Decision

Use a modular monolith with folder-level Clean/Hexagonal boundaries first.
Dependencies should point inward:

```text
Presentation -> Application -> Domain
Infrastructure -------------> Domain
```

Protocol, crypto, and transport become explicit seams before WebRTC and larger
feature growth. Internal Dart packages remain the Stage 7 target, deferred until
folder boundaries stabilize, contracts are documented, and circular dependencies
are removed.

## Consequences

- Refactor stages can keep the app compiling and tests passing.
- Boundary checks can tighten incrementally.
- Security-sensitive areas become easier to review.
- Some current impurity remains temporarily, especially `domain/models.dart`
  importing Flutter-adjacent types.

## Non-Goals

- No immediate monorepo/package split.
- No feature rewrite during documentation stages.
- No change to V4 behavior solely because this ADR exists.
