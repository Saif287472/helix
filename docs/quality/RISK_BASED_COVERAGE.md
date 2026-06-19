# Risk-Based Coverage Plan

Phase 0 does not impose one global coverage percentage. Helix coverage gates are
risk-based because auth, crypto, storage, sync, wipe, and deletion failures have
very different blast radius from presentation-only defects.

## Critical Scenario Inventory

| Area | Critical paths | Required scenario evidence |
|---|---|---|
| Remote auth and identity | registration, challenge login, device key roles, token rotation, revocation | success, replay, expiry, wrong device, wrong purpose, revoked device |
| Remote crypto | X3DH/prekeys, session persistence, message decrypt, tamper/replay/reorder, group epochs | success, malformed input, swapped key type, restart, fail-closed behavior |
| Remote storage | encrypted database open, migrations, corruption handling, backup snapshot handling | upgrade, rollback policy, plaintext sentinel scan, corruption error |
| Remote sync/outbox | enqueue, idempotency, retry, dead letter, inbound cursor, realtime gap recovery | offline send, restart, duplicate op, partial batch failure, reconnect gap |
| Local wipe/storage | panic wipe, storage prefix isolation, secure key deletion, file deletion | complete wipe, partial failure, restart scan, Remote isolation |
| Privacy/deletion | account delete, export, local purge, no plaintext logs/push | server purge, local purge, redaction, external-copy limitation |

## Reporting Rules

- Critical modules must list scenarios before a coverage threshold is raised.
- Branch coverage artifacts are required when the toolchain produces branch
  data; line-only LCOV is accepted as an interim report but does not prove
  branch completeness.
- Coverage artifacts are stored under `build/coverage/` and are not committed.
- A missing scenario row is a failure even if line coverage looks high.
- Later phases may add per-module thresholds after the broken vertical paths are
  repaired and measurable.

