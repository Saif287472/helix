# Helix Remote Release Rollback Plan

Remote rollback must preserve account identity, device state, message deletion
semantics, backup envelopes, and server compatibility.

## Before Release

1. Record release commit hash, schema version, OpenAPI version, and artifact
   checksums.
2. Confirm database backups and point-in-time recovery are healthy.
3. Confirm object-storage versioning or equivalent durability is enabled.
4. Confirm `/api/v1/health/ready` and `/api/v1/ops/metrics` are monitored.
5. Confirm the previous known-good backend and client artifacts remain
   available.

## Binary Rollback

Use binary rollback when the database schema is backward compatible:

1. Stop the rollout.
2. Deploy the previous known-good backend binary/container.
3. Publish the previous Remote client artifact if client rollback is needed.
4. Verify health/readiness, message sync, account deletion/export, calls, files,
   and group operations.

## Data Rollback

Use data rollback only when corruption or non-compatible migrations require it:

1. Freeze writes if data loss risk exists.
2. Restore the database to the selected point-in-time in isolated staging first.
3. Verify aggregate counts and schema compatibility.
4. Restore production only with an explicit incident note describing the write
   window intentionally discarded after the restore point.

Never roll back by deleting user data, weakening authentication, weakening
crypto checks, or bypassing account deletion/tombstone semantics.

## Communication

Use the status-page plan from `docs/operations/REMOTE_OPERABILITY_AND_DR.md`.
Updates must be content-free and must never reveal user identifiers, message
content, private media, or provider secrets.
