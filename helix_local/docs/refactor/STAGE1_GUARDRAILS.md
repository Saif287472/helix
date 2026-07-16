# Stage 1 Guardrails

Status: complete
Date: 2026-06-15

Stage 1 adds architecture and safety automation without changing feature
behavior.

## Added Guardrails

- Root agent workflow: `AGENTS.md`
- AI guardrails: `docs/ai/AI_GUARDRAILS.md`
- Ownership/blast-radius classification: `docs/ai/ownership-blast-radius.yaml`
- Module boundary config: `docs/architecture/module_boundaries.json`
- Boundary checker: `tool/check_boundaries.dart`
- Secret scanner: `tool/check_secrets.dart`
- Verification scripts: `scripts/verify.ps1`, `scripts/verify.sh`
- CI workflow: `.github/workflows/verify.yml`
- Forbidden file registry and security policies in `docs/security/`
- Workflow contracts in `docs/workflows/`

## Validation

Commands run:

```powershell
flutter analyze
flutter test
flutter test test\tool\check_boundaries_test.dart test\tool\check_secrets_test.dart
dart run tool\check_boundaries.dart
dart run tool\check_secrets.dart
.\scripts\verify.ps1
```

Result:

- Analyzer: no issues found
- Boundary check: passed
- Secret scan: passed
- Full tests: 93 passed
- Canonical verification: passed
- Debug build: skipped by default; set `HELIX_VERIFY_BUILD=1` to run
  `flutter build windows --debug`

## Advisory Findings

`flutter pub outdated` is now part of verification as a dependency-health
advisory. It currently reports multiple outdated direct dependencies and a
discontinued transitive `js` package. These are not fixed in Stage 1 because the
stage is limited to guardrails and verification, not dependency migration.

## Notes

The boundary rules are intentionally adapted to the current structure. They
prevent obvious back-dependencies now and should tighten after later stages split
domain, protocol, transport, and application seams.
