# Dependency Security Checks

Stage 1 verification includes `flutter pub outdated` as a dependency-health
advisory in CI, or when `HELIX_DEPENDENCY_ADVISORY=1` is set locally. Local
verification also passes `--no-pub` to Flutter commands unless that variable is
set, so dependency availability checks do not run during routine local tests.
The advisory flags upgrade pressure but does not replace human review.

## Required Review Before Adding Dependencies

- Package is actively maintained.
- Package has a compatible license.
- Package has no known critical vulnerability.
- Package does not weaken local-only privacy assumptions.
- Package has a clear owner in `docs/ai/ownership-blast-radius.yaml`.

## CI Notes

Helix Remote has a known-vulnerability gate: the `supply-chain` job in
`.github/workflows/ci.yml` generates a CycloneDX SBOM
(`helix_remote/tool/generate_sbom.dart`) and runs OSV-Scanner over
`./helix_remote`. `helix_remote/tool/check_governance_controls.dart` also checks
the lockfile and dependency-policy documents. There is no automated license
audit, and Helix Local changes are not wired into CI yet, so dependency
additions still require explicit manual review and a note in the completion
report.
