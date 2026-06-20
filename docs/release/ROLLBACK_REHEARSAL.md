# Rollback Rehearsal

Before release, rehearse and time these rollback paths:

| Path | Rehearsal |
|---|---|
| App rollback | Install previous Local and Remote builds over current release candidate where platform permits |
| API rollback | Route traffic back to previous backend build with compatibility fixtures passing |
| Realtime schema rollback | Verify clients tolerate previous envelope shape within compatibility window |
| DB migration rollback | Restore backup, run `quick_check`, and verify migration status endpoint/readiness |
| Object storage rollback | Repoint to prior encrypted object namespace or restore emulator snapshot |
| Key/config rotation | Rotate JWT, TURN, signing, and feature flag config in staging without committing secrets |

Evidence packet:

- commit and build IDs;
- start/end timestamps and elapsed time;
- backup snapshot identifier;
- compatibility test output;
- artifact checksums and provenance file;
- decision: pass, blocked, or risk-accepted.
