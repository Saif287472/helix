# Release & Rollback

## Intended Behavior

Releases must preserve identity, trust, storage, protocol compatibility, and
wipe behavior. Rollback must be planned before migrations ship.

## Invariants

- Protocol fixture corpus decodes after codec changes.
- Database migrations are forward-safe and tested from previous schema.
- Signing material is never committed.
- Release notes call out manual checks for Android foreground service, offline
  LAN discovery, groups, files, and future calls.

## Failure Handling

- Failed migration must not silently discard user data.
- Rollback plan must state whether older versions can read newer data.

## Verification

- Full verification pipeline.
- Debug build check with `HELIX_VERIFY_BUILD=1`.
- Manual release checklist before shipping.
