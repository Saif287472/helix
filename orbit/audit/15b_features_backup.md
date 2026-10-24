# Sweep 15b - app `lib/features/backup`

Read in full (11 files, 1,809 lines): `application/backup_providers.dart` (621),
`application/backup_gateway.dart` (338), `application/backup_models.dart` (233),
`application/transfer_rows.dart` (106), `application/backup_copy.dart` (73),
`application/restore_step.dart` (18), `backup_routes.dart` (39),
`presentation/restore_history_page.dart` (129),
`presentation/transfer_page.dart` (95), `presentation/backup_page.dart` (80),
`presentation/recovery_backup_page.dart` (77), plus `FEATURE.md`.
Cross-checks: `core/engine/post_sign_in.dart`,
`core/platform/secret_clipboard.dart`, `core/engine/failure_copy.dart`,
`packages/helix_remote_engine/lib/src/backup/{backup_service.dart,state.dart,device_transfer.dart}`,
`packages/orbit_ui/lib/src/screens/you/devices_backup_screens.dart` (the model's
consumer, for copy and confirmations only), `app/test/backup/*` (test names).

## What is sound

- **One gateway, one translation.** Every engine and API failure becomes a
  `BackupProblemException` in `EngineBackupGateway._guard`
  (`backup_gateway.dart:318-337`); nothing above it names an engine type, and
  a closed database or a bug is not mistaken for a backup problem. The
  `BackupProblem` -> sentence table is exhaustive and keyword-free
  (`backup_copy.dart:28-73`).
- **Recovery secret hygiene.** The secret is the engine's 160-bit random
  (`backup_providers.dart:38-44`), shown once, never stored, sent or logged,
  dropped the moment the backup is made (`:583-588`), and a new page gets a
  new one. Clipboard copies are cleared after a minute and only if the
  clipboard still holds it (`secret_clipboard.dart:29-43`).
- **Operations that can be re-entered are guarded** at entry
  (`backUpNow` `:163`, `restore` `:241`, `send` `:351`, `accept` `:418`);
  progress listeners are subscribed *before* the call and cancelled after it,
  and a late event cannot overwrite a final state (`:167`, `:248`).
- **The server's answer beats this device's record** for the recovery backup
  date, and the local record is the documented fallback (`:24-32`,
  `FEATURE.md:33-40`); the two are not conflated into one "yes/no".
- **Delete asks first** on both surfaces
  (`devices_backup_screens.dart:944-953`, `:1490-1500`), and the transfer row
  is built once for both the restore step and the transfer page so the two
  cannot disagree (`transfer_rows.dart:1-106`).
- **Restore is additive and repeatable** (doc and code: "adds what is missing,
  never replaces", `restore_history_page.dart:12-19`), and the after-sign-in
  step cannot be escaped with system Back (`PopScope(canPop: !afterSignIn)`),
  so the router condition it clears is always cleared.

## Findings

### AUD-15-6 A flow controller writes state after its page has disposed it

**Severity:** P3
**Confidence:** confirmed
**Where:** [backup_providers.dart:576-595](file:///J:/Projects/helix/helix_remote/app/lib/features/backup/application/backup_providers.dart#L576-L595) (`create`), [:597-611](file:///J:/Projects/helix/helix_remote/app/lib/features/backup/application/backup_providers.dart#L597-L611) (`restore`), [:613-620](file:///J:/Projects/helix/helix_remote/app/lib/features/backup/application/backup_providers.dart#L613-L620) (`deleteBackup`), [:240-282](file:///J:/Projects/helix/helix_remote/app/lib/features/backup/application/backup_providers.dart#L240-L282) (`RestoreFlowController.restore` and its progress listener)
**What:** Both providers are `autoDispose` (:231-234, :518-521). Their
operations await the engine, and every completion path then assigns `state`
(or reads `state.stage` inside the progress callback, :248). If the page is
gone by then, the notifier is unmounted, and Riverpod 3.4.3 throws
`UnmountedRefException` from the `state` setter (`riverpod-3.4.3/lib/src/core/ref.dart:232-242`,
via `Notifier.state`). The same file already guards `_generate`, `copy` and
`share` with a `_disposed` flag (:524-544, :549-574) - the three newer methods
do not, and `RestoreFlowController` has no guard at all.
**Trigger:** Start a restore (or a recovery-backup create/delete) and leave
the page while it runs: Back from Settings > Backup > Restore history
(`restore_history_page.dart:78` pops), any route pushed over it (a
notification, a deep link), or a system Back on the non-sign-in variant
(`PopScope(canPop: !afterSignIn)`).
**Evidence:** `state = ...` sits after `await` in all four paths; the engine
call keeps running (it is app-scoped), so the failure is deterministic when the
page is popped mid-operation. `backupRunProvider` - the one flow that is *not*
`autoDispose` - has the same shape and does not fail, which is why the bug only
appears on the two page-scoped flows.
**Impact:** An unhandled async exception (reported by the app's error zone) on
a normal gesture; the operation itself completes in the engine, so the person
gets no success or failure UI and nothing is lost. No data loss.
**Fix sketch:** App only: guard each completion with `if (!ref.mounted) return;`
(Riverpod 3, already used in `post_sign_in.dart:28` and
`read_tracker.dart`), and cancel the progress subscription on dispose; or adopt
S15-3. No wire, schema or server change.
**Test that proves it:** A widget test that starts `restore()`, pops the page,
then completes the fake gateway's future; today it throws
`UnmountedRefException` from the test zone, after the fix it completes quietly.
**Overlap:** S15-3.

### AUD-15-7 The backup feature's own doc says the recovery secret is made by the app and can be typed

**Severity:** P3
**Confidence:** confirmed
**Where:** [FEATURE.md:19-24](file:///J:/Projects/helix/helix_remote/app/lib/features/backup/FEATURE.md#L19-L24) against [FEATURE.md:57-64](file:///J:/Projects/helix/helix_remote/app/lib/features/backup/FEATURE.md#L57-L64) and [backup_providers.dart:36-44](file:///J:/Projects/helix/helix_remote/app/lib/features/backup/application/backup_providers.dart#L36-L44), [:514-517](file:///J:/Projects/helix/helix_remote/app/lib/features/backup/application/backup_providers.dart#L514-L517)
**What:** The overview bullet still describes the replaced design: "The secret
is generated in the app (24 characters, no lookalikes) or typed". The same
file's "Recovery secret (changed)" section says the engine generates 160 bits
and it cannot be chosen, which is what the code and the UI do (there is no
field to type a *new* secret; only the restore tab takes one).
**Trigger:** A maintainer or reviewer reading the overview as current, e.g. to
audit the "no lookalikes" encoding that no longer exists.
**Evidence:** Two paragraphs of the same file contradict each other;
`generateRecoverySecret()` is the gateway's only source (`backup_gateway.dart:210-211`),
and the Orbit screen shows it read-only.
**Impact:** Stale security documentation in the feature a reviewer is most
likely to read before touching recovery; the risk is a wrong assumption about
entropy or about which code path makes the secret.
**Fix sketch:** Docs only: rewrite the bullet to "made by the engine (160
bits), shown once, never chosen; the restore tab accepts a typed secret".
**Test that proves it:** None (doc); the existing
`backup_pages_test.dart:629-641` ("the person cannot choose their own secret")
already pins the code's half.
**Overlap:** AUD-15-5 (same kind of doc/code drift in sign-in).

### AUD-15-8 A transfer's failure cannot be cleared through `copyWith`

**Severity:** P3
**Confidence:** confirmed
**Where:** [backup_models.dart:203-217](file:///J:/Projects/helix/helix_remote/app/lib/features/backup/application/backup_models.dart#L203-L217) (`TransferView.copyWith(problem:)`), used at [backup_providers.dart:331-347](file:///J:/Projects/helix/helix_remote/app/lib/features/backup/application/backup_providers.dart#L331-L347) (`_onProgress`)
**What:** `copyWith` uses `problem ?? this.problem`, so passing `null` - which
is what the engine sends once a transfer is retried successfully - keeps the
old failure. `_onProgress` merges each new event into the previous view and so
carries a failure across a resume. `TransfersState.copyWith` in the same file
has a `clearError` flag for exactly this reason (`:302-311`); `TransferView`
does not.
**Trigger:** A send that fails (network drop) and is retried/resumes; every
later progress event for that transfer keeps `problem` set.
**Evidence:** Today the stale value is invisible because `transferRow` only
renders `problem` when `stage == TransferStage.failed`
(`transfer_rows.dart:59-65`); `TransferView.fraction`/`isFinished` do not read
it. It becomes visible the moment any surface shows a problem pill, or when a
row is reused after a failure.
**Impact:** Latent UI-state corruption in the transfer list; no data effect.
**Fix sketch:** App only: `TransferView.copyWith({..., bool clearProblem = false})`
mirroring `TransfersState.copyWith`, and have `_onProgress` pass
`clearProblem: view.problem == null`.
**Test that proves it:** A unit test: start with `problem: offline`, apply a
`done` view whose `problem` is null, assert `outgoing[id]!.problem == null`.
**Overlap:** None.

## Structural proposals

(Inline with sweep 15a: S15-1 failure copy, S15-2 numbers, S15-3 page-scoped
flows. Backup adds no fourth proposal.)

## Coverage gaps

- No test pops a page mid-restore / mid-create (AUD-15-6).
- No test resumes a failed send (AUD-15-8).
- `backupPageViewProvider`'s two-source recovery date (`:65-87`) is tested
  only through the page, not for the "server answered, label differs" case.
- `transferRow`'s button matrix is tested at the page level
  (`backup_pages_test.dart:499-542`) but not for `sending` + `waiting`.
- The Backup page draws a server-backup *delete* as a run
  (`deleteServerBackup` sets `running: true`, `:187-195`), so the ring and the
  disabled "Back up now" belong to a delete; cosmetic, not counted.
