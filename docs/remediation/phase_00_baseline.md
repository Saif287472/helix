# Phase 00 Baseline - Pre-Manual Remediation

Date: 2026-06-20
Agent/model: Codex (GPT-5)
Repository root: `J:\Projects\helix`
Starting branch: `master`
Starting commit: `dd739061baeadf13967e6b5e9e055c698ff0fb6a`

## Working Tree At Start

```text
?? HELIX_PRE_MANUAL_REMEDIATION_PLAN.md
```

The plan file was supplied as untracked workspace content before Phase 00 work
started. No production behavior was changed in Phase 00.

## Toolchain Baseline

- Flutter: `3.44.2`, stable channel, framework revision `c9a6c48423`
  (2026-06-10), engine revision `77e2e94772`, Dart `3.12.2`.
- Dart CLI: `3.12.2 (stable)` on `windows_x64`.
- Java on PATH: Oracle JDK `21.0.10+8-LTS-217`.
- Flutter Android toolchain: Android SDK `36.1.0`, build-tools `36.1.0`,
  emulator `36.5.11.0`, licenses accepted, Android Studio bundled JDK
  `21.0.10+-14961533-b1163.108`.
- Gradle wrapper observed from `apps/helix_remote/android`: Gradle `9.1.0`,
  Kotlin `2.2.0`, Groovy `4.0.28`; wrapper launcher JVM reported
  `1.8.0_301` when invoked directly, while Flutter Android builds used
  Android Studio JBR.
- Windows toolchain: Visual Studio Community 2026 `18.7.0`, Windows 10 SDK
  `10.0.26100.0`.
- Connected build target: Windows desktop available. No Android device was
  connected during baseline; APK debug builds were still produced.

`flutter doctor -v` result: PASS, no issues found.

## Documents Read

- `AGENTS.md`
- `HELIX_PRE_MANUAL_REMEDIATION_PLAN.md`
- `docs/architecture/PHASE_12_20_CLOSURE.md`
- `docs/architecture/CURRENT_STATE_2026-06-20.md`
- `docs/architecture/module_boundaries.json`
- `ownership-blast-radius.yaml`
- `docs/product/local/PRODUCT_CONTRACT.md`
- `docs/product/remote/PRODUCT_CONTRACT.md`
- `docs/security/FORBIDDEN_FILES.md`
- `docs/security/KEY_LIFECYCLE.md`
- `docs/security/THREAT_MODEL.md`
- `docs/security/REMOTE_SECURITY_AND_COMPLIANCE.md`
- `docs/workflows/ENVIRONMENT.md`
- `docs/adr/011-contract-first-remote-apis.md`
- `docs/adr/014-shared-package-eligibility.md`
- `docs/adr/015-app-specific-runtime-namespace.md`
- `contracts/remote-rest-openapi/openapi.yaml`
- `contracts/remote-realtime/envelope.json`
- `packages/remote/helix_remote_api/lib/api/realtime_envelope.dart`
- `scripts/verify.ps1`
- `scripts/verify.sh`

## Reproducible Commands

Root dependency resolution:

```powershell
flutter pub get
```

Full repository verification with all four debug builds:

```powershell
$env:HELIX_VERIFY_BUILD = "1"
.\scripts\verify.ps1
```

Local Windows debug build:

```powershell
Push-Location apps/helix_local
flutter build windows --debug --no-pub
Pop-Location
```

Local Android debug APK:

```powershell
Push-Location apps/helix_local
flutter build apk --debug --no-pub
Pop-Location
```

Remote Windows debug build:

```powershell
Push-Location apps/helix_remote
flutter build windows --debug --no-pub
Pop-Location
```

Remote Android debug APK:

```powershell
Push-Location apps/helix_remote
flutter build apk --debug --no-pub
Pop-Location
```

Remote backend checks:

```powershell
Push-Location services/helix_remote_backend
dart analyze
dart test
Pop-Location
```

## Verification Evidence

`flutter pub get`: PASS. Dependencies resolved; 13 newer package versions are
outside current constraints.

`$env:HELIX_VERIFY_BUILD='1'; .\scripts\verify.ps1`: PASS.

Observed successful gates:

- `dart format --output=none --set-exit-if-changed apps packages services tool`
  PASS, 342 files formatted with 0 changed.
- `flutter analyze --no-pub` PASS.
- `dart analyze services/helix_remote_backend tool` PASS.
- `dart run tool/check_boundaries.dart` PASS.
- `dart test tool/boundary_test.dart` PASS, 7 tests.
- Phase 0 guardrail tests PASS.
- Phase 11 release assurance audit PASS.
- Phase 20 release/governance audit PASS.
- `dart run tool/dep_graph.dart` PASS.
- `dart run tool/check_secrets.dart` PASS.
- `dart run tool/check_release_hardening.dart` PASS.
- `dart run tool/generate_local_sbom.dart --check-only` PASS, 218 packages.
- `flutter test --no-pub` in `apps/helix_local` PASS.
- `flutter test --no-pub` in `apps/helix_remote` PASS.
- All package tests discovered by `scripts/verify.ps1` PASS.
- `dart test` in `services/helix_remote_backend` PASS, 91 tests.
- Dependency health advisory intentionally skipped by local script default.
- Local Windows debug build PASS:
  `build\windows\x64\runner\Debug\helix_local.exe`.
- Local Android debug build PASS:
  `build\app\outputs\flutter-apk\app-debug.apk`.
- Remote Windows debug build PASS:
  `build\windows\x64\runner\Debug\helix_remote.exe`.
- Remote Android debug build PASS:
  `build\app\outputs\flutter-apk\app-debug.apk`.
- Signing credential isolation check PASS.

Build warnings observed but non-blocking:

- Flutter warned that several plugins still apply Kotlin Gradle Plugin directly
  and may need package upgrades before future Flutter releases.

## Baseline Findings

- HXA-001 through HXA-025 are represented in
  `docs/remediation/pre_manual_remediation_ledger.yaml`.
- Each finding has exactly one primary owning phase in the ledger.
- Some findings have secondary coordinated phases where the original plan split
  related work across phases.
- No pre-existing automated verification failure was found at this baseline.
- Physical-device checks remain manual-only and are deferred to Phase 18.

## Secret And Artifact Review

- No forbidden files from `docs/security/FORBIDDEN_FILES.md` were read or
  modified.
- No secrets, local databases, signing material, diagnostic exports, or machine
  private paths were introduced by Phase 00 artifacts.
- The baseline report records tool locations and build outputs only; it does not
  commit build artifacts.
