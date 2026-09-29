# Phase 10 Disaster-Recovery Drill Runbook

## Scope

Run this drill before a release candidate and after any migration, object-store,
outbox, or backup change. The drill is local/staging evidence only; production
credentials and customer data are never used.

## Required Drills

> Status (2026-09): only the load baseline has a checked-in tool
> (`helix_remote/backend/tool/load_smoke.dart`). The other drills are manual.
> Helix Global runs on the user's PC with SQLite and attachments on local disk
> (no object store); "DB failover" means restoring a copy of
> `helix_remote/backend/remote_backend.db`. Remote-specific DR steps are in
> `helix_remote/docs/operations/REMOTE_OPERABILITY_AND_DR.md`.

| Drill | Pass condition |
|---|---|
| Load baseline | `dart run tool/load_smoke.dart` (from `helix_remote/backend`, see `helix_remote/docs/operations/LOAD_TESTING.md`) completes with zero failed health probes |
| Reconnect storm | WebSocket storm test rejects excess reconnects and keeps healthy clients online |
| Large mailbox | 10k and 100k seeded mailbox pagination stays inside the Phase 10 frame budget |
| Prekey depletion | Send path returns a typed retryable failure when one-time prekeys are exhausted |
| TURN outage | Calls fail closed with no plaintext SDP/ICE logging |
| Object-store outage | Encrypted blob upload/download errors are retried or quarantined without data loss |
| DB failover rehearsal | Backup is restored into a fresh database and `quick_check` passes |
| Retention purge | Completed outbox, old audit, and old tombstone records are purged within bounds |

## Evidence

Capture:

- command, timestamp, commit, and environment;
- before/after table counts for retention and restore drills;
- p50/p95/p99 latency for load runs;
- DLQ count, queue age, reconnect rejection count, and migration status;
- unresolved failures with owner and release-blocking decision.

## Rollback Gate

Stop the release if any of these happen:

- restore cannot meet the documented RTO/RPO;
- `quick_check` fails after migration or restore;
- DLQ remains non-zero after retries drain;
- logs contain plaintext message content, tokens, keys, private media names, or
  full fingerprints.
