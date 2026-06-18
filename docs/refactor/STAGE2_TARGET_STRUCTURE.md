# Stage 2 Target Structure

Status: complete
Date: 2026-06-15

Stage 2 is documentation-only. No app files were moved into the target
structure.

## Added Documents

- `docs/architecture/PROJECT_STRUCTURE.md`
- `docs/adr/001-modular-monolith-clean-boundaries.md`
- `docs/security/THREAT_MODEL.md`
- `docs/security/TRUST_MODEL.md`
- `docs/security/KEY_LIFECYCLE.md`
- `docs/protocol/SECURITY_PROPERTIES.md`

## Added AI Context Files

- `lib/services/AI_CONTEXT.md`
- `lib/services/transport/AI_CONTEXT.md`
- `lib/services/discovery/AI_CONTEXT.md`
- `lib/data/AI_CONTEXT.md`
- `lib/domain/AI_CONTEXT.md`
- `lib/providers/AI_CONTEXT.md`
- `lib/platform/AI_CONTEXT.md`
- `lib/routing/AI_CONTEXT.md`

## Validation

Commands run:

```powershell
dart run tool\check_secrets.dart
dart run tool\check_boundaries.dart
flutter analyze
.\scripts\verify.ps1
```

Result:

- Analyzer: no issues found
- Boundary check: passed
- Secret scan: passed
- Full tests: 93 passed
- Canonical verification: passed

## Notes

The new `lib/routing/AI_CONTEXT.md` documents the future routing target. Runtime
routing remains in `lib/ui/app_router.dart` until a later refactor stage moves
code.
