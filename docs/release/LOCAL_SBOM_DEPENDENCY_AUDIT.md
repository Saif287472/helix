# Local SBOM And Dependency Audit

## SBOM

Generate the Local dependency inventory with:

```powershell
dart run tool/generate_local_sbom.dart --output build/release/helix_local_sbom.json
```

`.\scripts\verify.ps1` runs the same tool in `--check-only` mode and fails if a
non-workspace dependency lacks an obvious license file.

## Dependency Health

`.\scripts\verify.ps1` runs `flutter pub outdated` as an advisory. Dependency
updates still require human review for maintenance, license, privacy, and
security impact.

## Vulnerability Review

Before shipping a public Local release, run a vulnerability audit using the
currently approved ecosystem scanner. Record the scanner, date, database
version, and findings in the release notes.

Until an automated hosted scanner is selected, no new direct dependency may be
added without explicit review in the completion report.
