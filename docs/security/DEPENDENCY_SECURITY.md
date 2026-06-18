# Dependency Security Checks

Stage 1 verification includes `flutter pub outdated` as a dependency-health
advisory. It flags upgrade pressure but does not replace human review.

## Required Review Before Adding Dependencies

- Package is actively maintained.
- Package has a compatible license.
- Package has no known critical vulnerability.
- Package does not weaken local-only privacy assumptions.
- Package has a clear owner in `docs/ai/ownership-blast-radius.yaml`.

## CI Notes

Known-CVE and license audits should be wired into hosted CI when a chosen tool is
available for the project. Until then, dependency additions require explicit
manual review and a note in the completion report.
