# DR and rollback rehearsal evidence — 2026-08-07

Scope: repository-level rehearsal, not a claim of production restore.

> **Status: historical (v1).** The tests named below (`backend/test/...`) were deleted with the v1 backend at Phase X (tag `v1-final`). v2 disaster recovery is in `docs/operations/V2_OPERABILITY.md` and has not been rehearsed with a recorded result.

| Check | Evidence | Result |
| --- | --- | --- |
| Transaction rollback | `dart test backend/test/phase10_scalability_test.dart` | Grouped account write rolled back on injected failure. |
| Operational retention recovery | Same test | Bounded completed outbox/tombstone rows purged; pending outbox row retained. |
| Object storage recovery boundary | Same test | Opaque object adapter rejected traversal and retained ciphertext bytes. |
| Release rollback decision | `docs/workflows/RELEASE_ROLLBACK.md` (that file now lives at `helix_local/docs/workflows/RELEASE_ROLLBACK.md`; the Remote plan is `helix_remote/docs/release/REMOTE_RELEASE_ROLLBACK_PLAN.md`) reviewed against expand/contract migration plan | Binary rollback is allowed only while schema remains compatible; otherwise restore/PITR procedure applies. |

The rehearsal did not access a production database, object store, or host and
therefore does not satisfy the 30-day production restore-drill SLO. Before
launch, execute the procedure in `REMOTE_OPERABILITY_AND_DR.md` against an
isolated restored backup and append the restore point, elapsed time, aggregate
counts, operator, and outcome to this evidence record.
