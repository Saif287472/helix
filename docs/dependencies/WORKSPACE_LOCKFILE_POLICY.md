# Workspace Lockfile Policy

This repository holds **three independent pub workspaces**, not one. There is no root
`pubspec.yaml`:

| Workspace | Root | Lockfile |
|---|---|---|
| Helix Remote | `helix_remote/pubspec.yaml` (`name: helix_remote_workspace`) | `helix_remote/pubspec.lock` — **committed** |
| Helix Local | `helix_local/pubspec.yaml` | not committed (`helix_local/.gitignore`) |
| Orbit preview | `orbit/flutter/pubspec.yaml` (`name: orbit_flutter_workspace`) | `orbit/flutter/pubspec.lock` — **committed** |

## Helix Remote

`helix_remote/pubspec.lock` is committed as the reproducible dependency snapshot for the client, the
admin console, the server, all `helix_remote_*` packages, and `tool/`. It is authoritative:

- CI resolves with `flutter pub get --enforce-lockfile` in every Helix Remote job, so a resolution
  that drifts from the lockfile fails the build rather than silently building against whatever the
  caret ranges resolve to that day.
- The Flutter SDK version is pinned alongside it (`flutter-version: 3.44.8` in
  `.github/workflows/ci.yml`). `--enforce-lockfile` is only meaningful against a known SDK; bump the
  two together.
- Direct dependencies must use reviewed compatible ranges, not `any`.
- The lockfile is updated only after `flutter pub get` resolves the full workspace cleanly, as a
  deliberate reviewed change — not as an incidental diff in an unrelated pull request.
- EOL, prerelease, or duplicate dependency risks must be listed in
  `docs/dependencies/DEPENDENCY_RISK_REGISTER.md` with an owner and remediation.
- CI generates a CycloneDX SBOM from the lockfile and scans the resolved dependency set for known
  vulnerabilities (`supply-chain` job).

### Reading the lockfile

In a pub workspace the root lockfile classifies every package from the **root package's**
perspective, so a dependency declared by a member package (`app/`, `admin/`, `server/`) is recorded
as `dependency: transitive`. **Do not read direct-versus-transitive off `helix_remote/pubspec.lock`** —
read it off the declaring member's `pubspec.yaml`. Getting this wrong is what produced the incorrect
`file_picker` entry corrected in the risk register.

## Helix Local

Helix Local is a separate product with its own workspace and its own arrangements. It does not commit
a lockfile. That is Helix Local's decision to revisit or keep; this policy does not propose changing
it, and nothing in the Helix Remote CI jobs depends on it.

## Orbit

`orbit/flutter/` holds `apps/orbit_preview`, the Flutter twin of the HTML prototype that runs on fake
data (`orbit/PORT_PLAN.md`). The design system and every screen, `orbit_ui`, moved into the Helix
Remote workspace in Part B step 1 (`helix_remote/packages/orbit_ui`), so `helix_remote/pubspec.lock`
is the one that governs it; the preview depends on it by path.

Its lockfile is committed for the same reason Helix Remote's is: the compare tool (`PORT_PLAN.md`,
Phase 2) renders the same screen twice and diffs the pixels, so the resolved versions are part of
what is being reviewed and must not move underneath the comparison. No CI job runs this workspace yet
— CI starts covering Orbit when Part B lands.

Since Part B step 1 the preview's lockfile describes only the Flutter SDK's own packages, the
preview's dev-only lints and `orbit_ui` as a path package. It adds no hosted dependency of its own;
one that `orbit_ui` needs is declared in `orbit_ui` and so governed by `helix_remote/pubspec.lock`.
The preview's own packages are never shipped.

## Enforcement

`helix_remote/tool/check_governance_controls.dart` runs in CI and fails when a governance document
asserts a control the repository does not implement. Claims in this file about committed lockfiles,
`--enforce-lockfile`, and the SBOM job are covered by it.
