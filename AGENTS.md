# Agent Instructions

## Build artifacts

**Do not build debug APKs unless explicitly asked.** The user builds and
installs them manually on a physical device.

When app or admin code changes, do **not** run `flutter build apk`. Instead,
finish the work, run analysis and tests, and then tell the user plainly whether
a new APK is needed for them to test the change. Wait for them to ask before
building.

This applies to both `helix_remote/app` and `helix_remote/admin`.

## Verification expectations

- Run `flutter analyze` / `dart analyze` and the relevant test suites before
  reporting work as done.
- Distinguish pre-existing failures from ones you introduced. Confirm by
  stashing changes and re-running, rather than assuming.
- Do not commit unexplained binary or asset changes (e.g. `logo.png` changing
  during a build). Flag them and let the user decide.

## Committing

- The user has asked for commits to include all uncommitted work. Stage
  deliberately and review `git status` first, since builds can leave stray
  modifications behind.
