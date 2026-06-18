# Helix Local Release And Rollback Plan

## Release Artifact

The independent Local release artifact is produced by:

```powershell
.\scripts\local_release_gate.ps1 -BuildArtifacts
```

The script runs the full verification pipeline, generates an SBOM, checks Local
release signing material, and builds Local artifacts without building Remote.

## Rollback

1. Record the current release commit hash and artifact checksums.
2. If a release fails before distribution, discard the artifact and rebuild from
   the previous known-good commit.
3. If a release fails after distribution, publish the previous known-good Local
   artifact using the same Local signing identity.
4. Do not roll back across irreversible storage migrations unless the migration
   notes explicitly say the older build can read the newer state.

## Compatibility Notes

- Local message content is RAM-only, so rollback does not need to preserve chat
  history.
- Identity and trust records live in product-scoped secure storage and must not
  be cleared during rollback.
- Panic wipe behavior is one-way by design and cannot be rolled back.
