# Workspace Lockfile Policy

Helix uses a single workspace resolution rooted at `pubspec.yaml` and commits
`pubspec.lock` as the reproducible dependency snapshot for both apps, all
packages, backend code, and tooling.

Rules:

- Direct dependencies must use reviewed compatible ranges, not `any`.
- The lockfile is updated only after `flutter pub get` resolves the full
  workspace cleanly.
- EOL, prerelease, or duplicate dependency risks must be listed in
  `docs/dependencies/DEPENDENCY_RISK_REGISTER.md` with an owner and remediation.
- Local verification may skip advisory freshness checks, but CI runs the
  dependency advisory step.

