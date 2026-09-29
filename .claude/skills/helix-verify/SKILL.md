---
name: helix-verify
description: Run Helix Remote's analysis and test suites after a change and report only what matters - new failures versus the known pre-existing ones. Use before saying Helix Remote work is done, or when asked to check/test/verify it.
---

# Verify a Helix Remote change

All commands run from `J:\Projects\helix\helix_remote` in the Bash tool
(Git Bash). Suites take minutes: run long ones with `run_in_background: true`
and redirect output to a file in the scratchpad, then grep it — never tail a
huge log into context.

## 1. Format only what you touched

```bash
dart format <each changed .dart file>
```

Never `dart format lib` / `.` — much of the tree is not formatted with the
current formatter, and a tree-wide run buries the real diff. If it happened,
revert files whose only change is formatting (compare each against
`git show HEAD:<path>` formatted the same way).

## 2. Analyze

```bash
cd app && flutter analyze            # app + tests
cd admin && flutter analyze          # when admin changed
cd backend && dart analyze lib test  # when backend changed
cd packages/<pkg> && dart analyze    # when a package changed
```

Infos count: fix them (`dart fix --apply --code=<lint>` scoped to your
files is fine).

## 3. Test what the change can reach

```bash
cd backend && dart test > "$SP/backend.log" 2>&1                 # ~10 min
cd app && flutter test --reporter=expanded > "$SP/app.log" 2>&1  # ~10 min
cd admin && flutter test > "$SP/admin.log" 2>&1
cd packages/<pkg> && flutter test                                # always flutter test
```

Targeted first (`flutter test test/<file>.dart`), then the full suite of
every package you touched. The full gate is `scripts/verify.ps1`, but do not
set `HELIX_VERIFY_BUILD=1` (it builds APKs).

Failures: `grep -a "\[E\]$" "$SP/app.log" | sort -u`, then read the lines
after the failing test's name for Expected/Actual.

## 4. Separate old failures from new

Compare against **Known pre-existing failures** in `AGENTS.md`. For anything
else, prove whether you caused it — `git stash` the change and re-run that
one test — before calling it pre-existing. Fix what you caused. If a known
failure now passes, update the list in AGENTS.md.

## 5. Report

One line per suite: passed / failed counts, and each failing test named as
*new* or *pre-existing*. Then whether a new APK and/or a backend restart is
needed (AGENTS.md → Build artifacts).
