---
name: helix-verify
description: Run Helix Remote's analysis and test suites after a change and report only what matters - new failures versus the known pre-existing ones. Use before saying Helix Remote work is done, or when asked to check/test/verify it.
---

# Verify a Helix Remote change

All commands run from the checkout's `helix_remote/` directory in the Bash tool
(Git Bash). Suites take minutes: run long ones with `run_in_background: true`
and redirect output to a file in the scratchpad, then grep it - never tail a
huge log into context.

## 1. Format only what you touched

```bash
dart format <each changed .dart file>
```

Never `dart format .` - a tree-wide run buries the real diff. If it happened,
revert files whose only change is formatting.

## 2. Analyze

```bash
flutter analyze               # the whole workspace, app and tests included
dart analyze server tool      # when server or tooling changed (also in verify.sh)
```

Infos count: fix them (`dart fix --apply --code=<lint>` scoped to your
files is fine).

## 3. Test what the change can reach

```bash
cd app && flutter test --reporter=expanded > "$SP/app.log" 2>&1   # minutes
cd admin && flutter test > "$SP/admin.log" 2>&1
cd packages/<pkg> && flutter test                                  # always flutter test
cd packages/helix_remote_db && dart run tool/codegen.dart --check  # generated code current
```

Server tests need Postgres. Load the URL without printing it, then run with the
require flag so a missing database fails instead of skipping:

```bash
export HELIX_TEST_DATABASE_URL="$(powershell.exe -NoProfile -Command "[Environment]::GetEnvironmentVariable('HELIX_TEST_DATABASE_URL','User')" | tr -d '\r')"
cd server && HELIX_REQUIRE_TEST_DATABASE=1 dart test --concurrency=3 > "$SP/server.log" 2>&1
```

Never run `dart run tool/codegen.dart` while server or engine tests run: it
rewrites the generated files they compile. Other agents may be running tests on
the same machine, so expect slow runs and the occasional timing-sensitive flake
(rerun the one test alone before calling it a failure).

Targeted first (`flutter test test/<file>.dart`), then the full suite of every
package you touched. The full gate is `scripts/verify.ps1`, but do not set
`HELIX_VERIFY_BUILD=1` (it builds APKs). Also run
`dart run tool/check_governance_controls.dart` after touching docs, CI, the
Android config or the regression matrix.

Failures: `grep -a "\[E\]$" "$SP/app.log" | sort -u`, then read the lines
after the failing test's name for Expected/Actual.

## 4. Separate old failures from new

Compare against **Known pre-existing failures** in `AGENTS.md`. For anything
else, prove whether you caused it - `git stash` the change and re-run that
one test - before calling it pre-existing. Fix what you caused. If a known
failure now passes, update the list in AGENTS.md.

## 5. Report

One line per suite: passed / failed counts, and each failing test named as
*new* or *pre-existing*. Then whether a new APK and/or a server restart (and
`bin/migrate.dart`) is needed (AGENTS.md -> Build artifacts, Deployment).
