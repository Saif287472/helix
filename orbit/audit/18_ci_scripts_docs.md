# Sweep 18 — CI, verify scripts, `tool/`, dependency policy and documentation drift

Read-only. Scope: `.github/workflows/ci.yml` (238), `scripts/verify.sh` (128) and
`verify.ps1` (179), `coverage.sh` (89), `remote_release_gate.ps1` (126),
`tool/check_governance_controls.dart` (381), `tool/check_performance_budgets.dart`
(30), `tool/generate_sbom.dart` (48), `tool/pubspec.yaml` (20), the two
dependency documents (`docs/dependencies/WORKSPACE_LOCKFILE_POLICY.md` 66,
`DEPENDENCY_RISK_REGISTER.md` 161), `docs/performance/PERFORMANCE_BUDGETS.md`
(150), `helix_remote/docs/security/REGRESSION_TEST_MATRIX.md` (90) and the
release checklist section that names the gate. Cross-checks: the code's own
`HELIX_*` names against the handoff's environment table, the lockfiles'
tracked state, the action documentation for `dorny/paths-filter`, and the
`sound` half of the PowerShell failure semantics (run, not assumed).

## What is sound

- **Every job that resolves dependencies enforces the lockfile against one
  pinned SDK.** `flutter pub get --enforce-lockfile` in all four resolving jobs
  (`ci.yml:87`, `:133`, `:188`, `:223`) with `flutter-version: 3.44.8`
  (`:82`, `:131`, `:185`, `:221`) and JDK 17 pinned for the Android build
  (`:70-73`); the pin's reason (a floating `stable` turns reproducibility into
  a coin toss) is written down.
- **Database tests fail rather than skip where a database exists.**
  `postgres:17` as a service with a health check (`:106-119`) and
  `HELIX_REQUIRE_TEST_DATABASE=1` (`:123`); the Windows job cannot run Linux
  containers and says so (`:104-105`).
- **Every package must have tests.** Both shells refuse a `packages/*/` folder
  without a `test/` directory instead of silently testing nothing
  (`verify.sh:81-88`, `verify.ps1:107-114`), and both run `flutter test` even
  for pure-Dart packages so the loop needs no second branch.
- **The codegen check runs exactly once, in its own step.** CI sets
  `HELIX_VERIFY_SKIP_CODEGEN=1` for both shell runs (`ci.yml:62`, `:125`) and
  runs the drift check as its own Linux step (`:137-139`), so a stale
  `*.g.dart` cannot merge and the check is not silently doubled.
- **The coverage ratchet measures a number it once actually measured.** The
  script comments record both corrections (55 was 36 points below reality;
  `awk` was reading empty stdin and always reported "No lines instrumented"),
  the lcov file is passed as an operand (`coverage.sh:68-75`), generated
  `*.g.dart` is excluded (`:43`), and the server's absence from the number is
  printed rather than hidden (`:87-88`).
- **The SBOM is complete for this repo.** `dart run tool/generate_sbom.dart
  pubspec.lock` produced 239 components for the 239 packages in
  `helix_remote/pubspec.lock` (verified); the scanner then reads the resolved
  tree directly too (`ci.yml:232-237`), so the SBOM is a record, not the only
  check.
- **Governance controls can assert absence.** `GovernanceControl.absent`
  (`check_governance_controls.dart:28-61`) is what stops a withdrawn claim from
  being re-asserted — the MED-9 shape — and the regression matrix's `.dart`
  paths must exist (`:286-298`), so the matrix cannot describe deleted tests.
- **`verify.ps1` gates on the exit code correctly, and says why.**
  `$global:LASTEXITCODE = 0` before each step and `if ($global:LASTEXITCODE -ne
  0)` after it, with the PowerShell-stderr trap explained (`verify.ps1:29-40`).
  This is the pattern the release gate did not copy (AUD-18-1).
- **The environment table matches the code.** Every `HELIX_*` name read in
  `server/lib/src` and `server/bin` (52) appears in
  `docs/operations/V2_SERVER_HANDOFF.md`; the reverse diff is only the v1→v2
  rename table, which is labelled as history.
- **The lockfile policy's factual claims hold today.**
  `helix_remote/pubspec.lock` and `orbit/flutter/pubspec.lock` are tracked;
  `helix_local/pubspec.lock` is ignored by that product's own `.gitignore`
  (checked with `git ls-files`). Only the *enforcement* claim is wrong
  (AUD-18-4).

## AUD-18-1 The release gate cannot fail: its steps check `$?` after a scriptblock that ends in `Pop-Location`

**Severity:** P2
**Confidence:** confirmed
**Where:** [remote_release_gate.ps1:14-24](file:///J:/Projects/helix/helix_remote/scripts/remote_release_gate.ps1#L14-L24) (the `if (-not $?)` at :23), [remote_release_gate.ps1:35-42](file:///J:/Projects/helix/helix_remote/scripts/remote_release_gate.ps1#L35-L42), [remote_release_gate.ps1:46-55](file:///J:/Projects/helix/helix_remote/scripts/remote_release_gate.ps1#L46-L55), [remote_release_gate.ps1:57-64](file:///J:/Projects/helix/helix_remote/scripts/remote_release_gate.ps1#L57-L64), [remote_release_gate.ps1:100-121](file:///J:/Projects/helix/helix_remote/scripts/remote_release_gate.ps1#L100-L121)

**What:** `Invoke-Step` runs `& $Command` and then asks `$?`. Every step that
does real work wraps its command in `Push-Location … try { … } finally {
Pop-Location }`, so the *last command to execute inside the scriptblock is
`Pop-Location`* — and `$?` after `& $Command` reflects that cleanup, not the
command it was meant to watch. A non-zero exit from a native command does not
throw (`$ErrorActionPreference = "Stop"` covers cmdlets, not `LASTEXITCODE`),
so a failing `flutter test`, `dart test` or `flutter build apk --release` is
reported as success and the gate continues to the next step, ending with exit
code 0.

**Trigger:** An operator runs `.\scripts\remote_release_gate.ps1` (or
`-BuildArtifacts`) as `REMOTE_RELEASE_CHECKLIST.md:14` requires, on a tree
where one of the four steps fails: a server suite that needs the database, an
API client suite, a client suite, or either release build.

**Evidence:** Run on this machine, with the exact shape of the script:

```
$ErrorActionPreference="Stop"; function T { param([scriptblock]$C) & $C; "success=$?" }
T { Push-Location app; try { cmd /c "exit 7" } finally { Pop-Location } }
→ success=True
```

The first step ("Full verification") is safe only because `verify.ps1` throws,
and a terminating error propagates; the four steps that follow it — client
tests (`:35-42`), server tests with `HELIX_REQUIRE_TEST_DATABASE=1` and
`--concurrency=3` (`:46-55`), API tests (`:57-64`) and both release builds
(`:102-121`) — are not. The sibling `verify.ps1` already does this correctly
(`:29-40`), so the defect is a copy that dropped the one line that mattered.
`REGRESSION_TEST_MATRIX.md:48` (MED-10) claims the governance checker protects
"the release gate script cannot run"; the only control on the script asserts it
still contains `--obfuscate` (`check_governance_controls.dart:79-83`), which
protects LOW-1 and would not notice a returning `$?`-style bug.

**Impact:** The mandatory release gate is a rubber stamp. A release can be
tagged after a red server suite or a failed release build, with the operator
having seen "no error", and the checklist's own instruction is what produced
that confidence. The build half is the worse one: `-BuildArtifacts` silently
keeps going after `flutter build … --release` fails, so the next step may
package or ship a stale `build/` tree.

**Fix sketch:** Mirror `verify.ps1:29-40`: set `$global:LASTEXITCODE = 0`
before `& $Command` and throw on `-ne 0` afterwards (native commands set it even
through `finally`). Optionally also `if (-not $?)` is never useful here. No
wire, schema, server or app change. Then correct the MED-10 row in
`REGRESSION_TEST_MATRIX.md:48` to point at the exit-code check rather than
`--obfuscate`.

**Test that proves it:** A Pester (or plain PowerShell) test that dot-sources
the script's `Invoke-Step` and runs a step whose scriptblock is `Push-Location
<dir>; try { cmd /c "exit 7" } finally { Pop-Location }`: today it returns
without throwing; after the fix it throws. There is no test of any `scripts/`
PowerShell file today.

**Overlap:** AUD-18-5 (the checklist's other unrunnable item); the MED-10 row
of the regression matrix (sweep 18, "what is sound" note).

## AUD-18-2 A scheduled or manually dispatched CI run verifies only the tip commit's diff, not the tree

**Severity:** P3
**Confidence:** likely
**Where:** [ci.yml:8-10](file:///J:/Projects/helix/.github/workflows/ci.yml#L8-L10) (the `schedule` and `workflow_dispatch` triggers), [ci.yml:29-47](file:///J:/Projects/helix/.github/workflows/ci.yml#L29-L47) (the `changes` job, `dorny/paths-filter@v3` with no `base`/`ref`), [ci.yml:51-53](file:///J:/Projects/helix/.github/workflows/ci.yml#L51-L53), [ci.yml:94-96](file:///J:/Projects/helix/.github/workflows/ci.yml#L94-L96), [ci.yml:174-176](file:///J:/Projects/helix/.github/workflows/ci.yml#L174-L176), [ci.yml:206-208](file:///J:/Projects/helix/.github/workflows/ci.yml#L206-L208), [ci.yml:194-202](file:///J:/Projects/helix/.github/workflows/ci.yml#L194-L202) (the green `no-source-changes` job)

**What:** Every verify job is gated on `needs.changes.outputs.*`. On `push` and
`pull_request` that filter is computed from the push range or the PR file list.
On the weekly `schedule` and on `workflow_dispatch` there is no such range:
`dorny/paths-filter` documents that for an event other than push/PR, when `base`
equals the triggering branch (its default is the repository default branch,
which is also what a schedule/dispatch checks out), "changes are detected from
the last commit" — the filter describes the tip commit, never "the whole tree".
So a scheduled run exercises the gates only when the last commit on `main`
happens to touch `docs/**` or `helix_remote/**`; otherwise all three filters
are false and the run consists of the `no-source-changes` echo, which is a
success.

**Trigger:** The Monday cron (`:8-9`), or an operator pressing "Run workflow"
(`:10`) to re-check `main` — the two occasions on which nothing has changed and
the point is to re-run anyway.

**Evidence:** `dorny/paths-filter` README, "Supported workflows": a base equal
to the triggering branch is documented only for `push` ("against the most
recent commit on the same branch before the push") and for other events with a
base equal to the triggering branch it says "changes are detected from the last
commit"; the `base` input's default is "repository default branch". The
workflow supplies neither `base` nor `ref` (`ci.yml:37-47`). The failure path
is visible in the same file: `no-source-changes` runs when all three outputs
are false and prints "No Helix Remote source, docs, or CI changes detected"
(`:194-202`).

**Impact:** The schedule exists for exactly the things that change without a
commit — a new OSV advisory against an unchanged `pubspec.lock`, a runner image
bump, an expired pinned action — and for those it reports green having run
nothing, including the `supply-chain` job that is the only unattended
vulnerability scan. A manual dispatch gives the same false green. (Day-to-day
PR and `main` pushes are unaffected.)

**Fix sketch:** Bypass the path filter for these two events, e.g. give the
`changes` job a fourth output `forced: ${{ github.event_name == 'schedule' ||
github.event_name == 'workflow_dispatch' }}` and OR it into each job's `if:`;
or set `base` to a commit that predates the tree (not to `main`). No other
change. The `no-source-changes` job must not run when `forced` is true.

**Test that proves it:** Not expressible in the repo's suites; the proof is one
dispatched run: today its job list contains only `changes` and
`no-source-changes` when the tip commit is unrelated; after the fix
`verify-linux`, `verify-windows`, `supply-chain` and `performance-budgets` all
run. Add a workflow comment stating the invariant so the next editor of `if:`
sees it.

**Overlap:** MED-12 in the regression matrix (`REGRESSION_TEST_MATRIX.md:50`)
treats the CI gates as present; this is the case where they are present and
not run.

## AUD-18-3 The dependency register's version check silently skips nine of its rows, while the register says "any table"

**Severity:** P3
**Confidence:** confirmed
**Where:** [DEPENDENCY_RISK_REGISTER.md:79-81](file:///J:/Projects/helix/docs/dependencies/DEPENDENCY_RISK_REGISTER.md#L79-L81) (the claim), rows [23](file:///J:/Projects/helix/docs/dependencies/DEPENDENCY_RISK_REGISTER.md#L23), [24](file:///J:/Projects/helix/docs/dependencies/DEPENDENCY_RISK_REGISTER.md#L24), [25](file:///J:/Projects/helix/docs/dependencies/DEPENDENCY_RISK_REGISTER.md#L25), [27](file:///J:/Projects/helix/docs/dependencies/DEPENDENCY_RISK_REGISTER.md#L27), [45](file:///J:/Projects/helix/docs/dependencies/DEPENDENCY_RISK_REGISTER.md#L45), [66-71](file:///J:/Projects/helix/docs/dependencies/DEPENDENCY_RISK_REGISTER.md#L66-L71); [check_governance_controls.dart:324-326](file:///J:/Projects/helix/helix_remote/tool/check_governance_controls.dart#L324-L326) (the row regex), [:330-354](file:///J:/Projects/helix/helix_remote/tool/check_governance_controls.dart#L330-L354) (the loop), [:355](file:///J:/Projects/helix/helix_remote/tool/check_governance_controls.dart#L355) (the only completeness guard)

**What:** `registerVersionFailures` recognises a row only when it looks like
`` | `pkg` | `version` | `` — one ticked package, one ticked version, pipes as
separators. The register writes several rows as comma or plus lists
(`` `shelf`, `shelf_router`, `http` ``), uses `+` (`aws_signature_v4` +
`aws_common`), adds a parenthetical after the version (`image` `4.10.1`
"(already resolved transitively)"), and keeps its "Deferred major upgrades"
table in a "Held at" form with *un-ticked* range cells (`^18.0.0`). None of
those lines match, so none of those 17 packages is compared with the
lockfile. The `rows == 0` guard (`:355`) catches a totally unrecognisable
register, but not a new row in a layout the regex does not know.

**Trigger:** A dependency in one of those rows moves without the register being
updated — e.g. `http` (documented as `1.2.x`, a placeholder that could never
match a resolved version), `crypto`, `shelf*`, `googleapis_auth`,
`web_socket_channel`, `stream_channel`, `aws_common` — or a new register row
is written in the same comma style.

**Evidence:** Running the checker's own regex over the register with
`grep -P` matches 21 rows and omits exactly those nine; the checker itself
passes today ("27 controls"), so the omissions are silent. The register states
at :79-81: "`tool/check_governance_controls.dart` fails when a version in this
register (in any table) differs from the lockfile." The "in any table" half is
false.

**Impact:** The gate that exists because review G-01 found the register holding
a stale version (line 152, "the register said 'held at ^18' while the app had
moved to 22") does not cover the rows most likely to drift, and it cannot tell
the difference between "checked and correct" and "not recognised". The register
is a policy document; a confidently wrong one is the failure mode it was
written against.

**Fix sketch:** Split the name and version cells on `/`, `,` and `+` and strip
trailing parentheticals before comparing; treat an un-ticked second cell as an
explicit exemption only in the "Held at" table (matched by its header), and
fail on any other un-ticked version cell. Add a completeness assertion: the
number of package names checked must equal the number of backticked package
cells in the file. No wire/schema change; `tool/` only.

**Test that proves it:** Add a row `` | `http`, `crypto` | `1.6.0` / `0.0.0` | ``
to a copy of the register and run the checker: today it passes; after the fix it
fails naming `crypto`. Also assert the completeness count, so a future layout
cannot reintroduce the gap.

**Overlap:** AUD-18-4 (the same checker's coverage claims), and the governance
self-claims in `07_ops_admin_compliance.md` (the checker was born from the
enterprise audit).

## AUD-18-4 The lockfile policy says the governance checker covers claims it does not check

**Severity:** P3
**Confidence:** confirmed
**Where:** [WORKSPACE_LOCKFILE_POLICY.md:62-66](file:///J:/Projects/helix/docs/dependencies/WORKSPACE_LOCKFILE_POLICY.md#L62-L66) (the claim), [check_governance_controls.dart:191-198](file:///J:/Projects/helix/helix_remote/tool/check_governance_controls.dart#L191-L198) (the only lockfile control)

**What:** The policy's "Enforcement" section says: "runs in CI and fails when a
governance document asserts a control the repository does not implement. Claims
in this file about committed lockfiles, `--enforce-lockfile`, and the SBOM job
are covered by it." The only control touching this file requires it to
*contain the string* `enforce-lockfile` (`:191-198`). Nothing asserts that
`helix_remote/pubspec.lock` and `orbit/flutter/pubspec.lock` are tracked
(a `.gitignore` edit could untrack them with every gate still green), that
`ci.yml` actually passes the flag, or that the SBOM job exists. The same
section also still says the Orbit workspace is uncovered "yet — CI starts
covering Orbit when Part B lands" (`:52-55`), though Part B landed on
2026-10-19 and no CI job looks at `orbit/` at all.

**Trigger:** Someone edits `helix_remote/.gitignore` (the `pubspec.lock`
exemption there is a comment, not a rule) or deletes the `supply-chain` job;
the policy keeps asserting the guarantee.

**Evidence:** The controls list (`:64-281`) has no entry whose path is
`helix_remote/.gitignore` or whose marker is `generate_sbom.dart`; the only
ci.yml control asserts the drift codegen step (`:224-232`). The self-reference
is the loophole: the check is that the policy mentions the word.

**Impact:** This is the exact failure mode the checker was created to stop —
"a document that is confidently wrong" — reproduced one level up, in the
document that promises the coverage. The current facts are true (both
lockfiles are tracked; the flag and the SBOM job are present), so nothing is
broken today; the guarantee is simply unowned.

**Fix sketch:** Add three controls: `.gitignore` must not contain `pubspec.lock`
(absent), `ci.yml` must contain `dart run tool/generate_sbom.dart` and
`--enforce-lockfile`, and the Flutter version in `ci.yml` must equal the one
the policy names. Reword `:62-66` to name those controls. For the Orbit
sentence, either add `orbit/**` to CI or state plainly that the preview has no
job and why.

**Test that proves it:** Extend the checker (the test is the checker's own run)
and then, in a scratch copy, delete the SBOM step from `ci.yml`: after the fix
the checker fails naming it; today it passes.

**Overlap:** AUD-18-3 (same checker, same class of unowned guarantee).

## AUD-18-5 The performance-budget document's runnable commands name files that do not exist

**Severity:** P3
**Confidence:** confirmed
**Where:** [PERFORMANCE_BUDGETS.md:134](file:///J:/Projects/helix/docs/performance/PERFORMANCE_BUDGETS.md#L134), [:136-141](file:///J:/Projects/helix/docs/performance/PERFORMANCE_BUDGETS.md#L136-L141), [:160](file:///J:/Projects/helix/docs/performance/PERFORMANCE_BUDGETS.md#L160), [:166-169](file:///J:/Projects/helix/docs/performance/PERFORMANCE_BUDGETS.md#L166-L169), [:174-181](file:///J:/Projects/helix/docs/performance/PERFORMANCE_BUDGETS.md#L174-L181)

**What:** The doc's "How to record baselines" block tells the reader to run
`flutter test app/test/phase4_performance_budget_test.dart` (`:134`),
`flutter test app/test/phase10_isolate_compute_test.dart` (`:137`), `cd
backend; dart test test/phase10_scalability_test.dart` (`:138`) and `cd
backend; dart run tool/load_smoke.dart` (`:141`). None of those paths exists:
the real test is `helix_remote/app/test/performance_budget_test.dart` (the one
`ci.yml:192` runs), the load harness is `helix_remote/server/tool/load.dart`
with `server/tool/load/` beside it, and there is no `backend/` directory. The
same wrong name appears in the CI-status note (`:160`) and three gate rows name
tools that were never built (`:166-169`), while the status note above them
(`:122-127`) says so — so the section contradicts itself, and the release
checklist at `:174-181` still asks for the unbuildable ones.

**Trigger:** A release manager or a developer follows the doc's policy line
("No performance-sensitive change is accepted without before/after evidence
against these budgets") and copies the commands.

**Evidence:** `ls helix_remote/app/test` lists `performance_budget_test.dart`,
`chat_performance_test.dart`, `people_performance_test.dart`; `helix_remote/backend`
does not exist; `helix_remote/server/tool` contains `load.dart` and `load/`.
`tool/check_performance_budgets.dart:8-23` only asserts three metric *names*
are still in the document — it never checks a path, a number or a measurement.

**Impact:** The only documented way to produce the evidence the policy demands
does not work, and the gate that would notice ("Verify declared performance
budgets", `ci.yml:189-190`) verifies three strings. A reviewer cannot tell an
unmeasured budget from a met one; the §1 numbers are unenforced and the
baseline table is still empty (`:154-158`).

**Fix sketch:** Point the block at the files that exist (`flutter test
app/test/performance_budget_test.dart` from `helix_remote/app`,
`dart run tool/load.dart` in `server/`), mark the §4.1 rows "not built" in the
table itself rather than in a note above it, and extend
`check_performance_budgets.dart` to require each `.dart` path the doc names to
exist (the same trick `check_governance_controls.dart:286-298` uses for the
regression matrix). No wire/schema change.

**Test that proves it:** Extend the budget checker with the path-existence rule
and add a unit case for a doc naming a missing file. Today the checker passes
on a document whose every command fails.

**Overlap:** AUD-18-1 (the release checklist's other unrunnable instruction),
`07_ops_admin_compliance.md` (governance documents asserting controls).

## Coverage gaps (read, not findings)

- `helix_local/**` triggers no job; the workflow says so in the
  `no-source-changes` message (`ci.yml:202`). Dormant product, declared.
- `integration_test` journeys are not run in CI (no device on the runner); the
  comment at `ci.yml:143-157` explains why and the matrix lists it as a gap.
  The comment says "today's two files" while `app/integration_test/` now holds
  one journey plus its README — cosmetic.
- **No job sets `timeout-minutes`.** GitHub's default is six hours, so a hung
  suite (the engine's documented lock-order hazard, or a test waiting on a
  socket) holds a runner for the afternoon; `concurrency` only cancels
  superseded runs of the same ref.
- `check_performance_budgets.dart` is a name-presence check; the §1 client
  budgets (startup, memory, package size) have no measurement in CI, and the
  baseline table is empty by design.
- The register's "Deferred major upgrades" table is un-checked on purpose
  (ranges, not resolutions); AUD-18-3 asks that the exemption be explicit
  rather than accidental.
- `orbit/flutter` (the preview) has no CI job; its lockfile is committed and
  its pixel comparison is run by hand. The lockfile policy's sentence about it
  is stale (AUD-18-4).
- No test exercises any file under `scripts/`; AUD-18-1 is what that costs.
- The Windows job's server run has no database, so its database suites skip
  (by design; Linux covers them with the require flag).
- `ci.yml` pins `osv-scanner-action@v2.3.8`; its existence was not verified
  here and there is no evidence of it failing, so it is not a finding.

## Considered and dropped

- **`HELIX_VERIFY_BUILD`/`HELIX_VERIFY_BUILD_ONLY` accept only the literal
  `1`** in both shells (`verify.sh:43-48`, `verify.ps1:11-14`, `:148`), unlike
  every other flag, which also accepts `true`/`yes`. `HELIX_VERIFY_BUILD=true`
  would silently skip the builds — but `1` is the documented usage in
  `AGENTS.md` and the CI env, and the skip is printed. Not a finding.
- **`coverage.sh` re-runs every suite that `verify.sh` just ran**, roughly
  doubling the Linux job's wall time. Cost, not a defect; noted for the
  remediation plan's "don't change behaviour" batch only.
- **`generate_sbom.dart` drops components with no `version:` line.** Checked:
  all 239 lockfile entries have one (workspace members are not in the
  lockfile), so nothing is dropped today.
- **`check_performance_budgets.dart` reading `../docs/...`** depends on being
  run from `helix_remote/`; both CI and the shells do that. Fragile, not
  broken.
- **The `changes` job's `common` filter covers `docs/**` and `ci.yml` only** —
  a root-level `README.md` edit runs nothing, which is intended (the echo job
  says so).
- **The Windows job's skipped DB tests** and **the missing Pester suite** are
  already named above; the first is declared, the second is AUD-18-1's test.

## Structural proposal — one gate list, three hand-kept copies

**Current shape.** The same ten gates are written out three times by hand:
`verify.sh:57-110`, `verify.ps1:47-146`, and a subset again in
`remote_release_gate.ps1:31-79`, with `coverage.sh:48-53` repeating the suite
list a fourth time. Each copy carries its own failure detection (bash `set -e`,
`LASTEXITCODE`, `$?`), its own skip variables (`HELIX_VERIFY_SKIP_CODEGEN` in
two shells) and its own comments.

**Hazard.** The copies have already diverged where it matters: the release
gate's failure probe is broken (AUD-18-1) while `verify.ps1`'s is correct, and
the coverage script's suite list is independent of the two shells', so a new
package is picked up automatically by the loop but the release gate's explicit
list (app, server, api) is not. A gate added to one copy is invisible to the
other two, and nothing tests any of them.

**Proposed shape.** One declarative list (a Dart file in `tool/`, e.g.
`tool/gates.dart`, which both shells invoke as `dart run tool/gates.dart
--suite=…`), holding the step name, the working directory, the command and the
skip flags. `verify.sh`/`verify.ps1` shrink to "call the runner, propagate its
exit code"; the release gate calls the runner with its extra steps
(applied as a flag) instead of keeping its own copies. `coverage.sh` keeps its
own collection logic but asks the runner for the package list.

**Migration path.** Expand: add `tool/gates.dart` and a `--list` mode, run it
beside the existing shells in CI (two green paths for one release). Migrate:
point `verify.sh` and `verify.ps1` at it; delete their step bodies. Contract:
fold `remote_release_gate.ps1`'s steps into the list and remove the duplicate
blocks. Three commits, each independently revertible.

**Risk.** Low-to-moderate: the runner becomes a single point of failure for
every gate, so it needs the same `set -e`-equivalent (non-zero exit on the
first failure) and a self-test. Windows and Linux both have Dart, so the
runner is portable; the risk is in the shell glue, which is what shrinks.

**Rough size.** ~150 lines of new Dart, ~40 lines of shell glue replacing ~180
lines of duplicated shell, plus one small test for the runner.
