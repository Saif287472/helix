# Sweep 12p — `helix_remote_engine`: backup service, ledger, models, options

**Scope.** `backup_service.dart` (409), `state.dart` (422), `models.dart` (286),
`options.dart` (196) read line by line, plus the cross-reads that settle every
finding: `device_transfer.dart` 88-305, 307-500, 553-667 (send, receiver,
pause, cleanUp, senderOrder), `device_service.dart` 1-70 and 120-140 (link
times, the `OwnDevicesChanged` emit), `engine.dart` 620-640 (the inbound hook
that refreshes devices before the event), the app's `backup_gateway.dart`
144-181, `backup_providers.dart` 318-347, `transfer_rows.dart` 40-106 and
`helix_runtime.dart` 225-240, and the engine tests that pin the pauses
(`transfer_test.dart:197`, `support.dart:209-210`, server
`test/client/engine/backup_test.dart:650-651`). ~1,900 lines.

**Verdict.** The backup feature's *state* is careful: every ledger change is a
read-modify-write inside `db.transaction`, every pointer is bounded before it
is fetched, and a restore keeps what it fetched. The defects are all in the
*automation around* the ledger — when the cursor moves, what "fresh" means,
how long an offer claims to live, and what a progress list can honestly say.
Two of the four are latent only because the app hard-codes the two auto
options off (`helix_runtime.dart:231-234`); the offer lifetime one is live in
the default configuration.

## Findings

### AUD-12p-1 An offer stays on the receiving device five days after its relay objects are gone

**Severity** P3 · **Confidence** confirmed

**Where** [options.dart:130-131](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/options.dart#L130-L131),
[options.dart:185-189](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/options.dart#L185-L189),
[device_transfer.dart:633-652](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L633-L652),
[device_transfer.dart:571-575](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L571-L575)

**What** The sender deletes a transfer's relay objects once
`now - createdAt > relayTtl` (48 h by default) and `_discard` also removes its
outgoing entry ([device_transfer.dart:286-290](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L286-L290)).
The receiver drops a `waiting` offer only after `offerTtl` (7 days). Between
hour 48 and day 7 the offer is shown as live ("Ready to receive"), and
accepting it fetches a manifest that is already deleted: `not_found` →
`BackupFailure.expired` → phase `failed`, chunks dropped, and the sender never
learns (its ledger entry is gone too).

**Trigger** Default options. Send history from device A to B, do not accept for
48 h, accept. Also hits a download that is still running at hour 48: the
sender's maintenance deletes the remaining segments underneath it, and the run
ends `expired` after keeping what it had.

**Evidence** `cleanUp`'s outgoing branch deletes on `old` alone
([636-639](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L636-L639)),
the incoming branch's `waiting` case uses `offerTtl`
([643-649](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L643-L649)),
and the two defaults differ by five days ([options.dart:130-131](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/options.dart#L130-L131)).
`_fetch` maps the relay's `not_found`/`expired` to `BackupFailure.expired`
([571-575](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L571-L575)),
and `_accept`'s non-transient branch sets `failed` and drops the chunks
([455-482](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L455-L482)).
The transfer row then offers "Resume", which repeats the same failure
(`app/lib/features/backup/application/transfer_rows.dart:79`).

**Impact** A dead-end offer that looks valid for five of its seven days. No
data loss (the history is still on A and A can resend), but the user's only
recovery is to ask the sender to send again — and the sender's ledger no
longer knows the transfer existed, so it cannot even cancel it.

**Fix sketch** Expire the receiving offer when the relay does: use
`min(offerTtl, relayTtl)` for the `waiting` case in `cleanUp` (the two options
already live in one `BackupOptions` both ends share), or raise `relayTtl` to
`offerTtl` if keeping objects a week is acceptable. Either way, an `expired`
accept should remove the offer rather than leave a Resume that cannot work.

**Test that proves it** Engine test with `relayTtl: 1 s, offerTtl: 1 d`: send,
`cleanUp` on the sender, then on the receiver — the offer is gone (today it is
still `waiting`); with `offerTtl` long, accepting says `expired` and the
`watchOffers` row disappears instead of turning into `failed`.

**Overlap** AUD-12r's transfer receiver (same file, read in 12r); none in the
plan yet.

### AUD-12p-2 The auto-offer cursor moves before the offer is sent, and every failure is swallowed

**Severity** P3 · **Confidence** confirmed

**Where** [backup_service.dart:392-407](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/backup_service.dart#L392-L407),
[device_transfer.dart:98-115](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L98-L115),
[device_transfer.dart:197-209](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L197-L209)

**What** `_offerToNewDevices` writes `backup.transfers.cursor` to the newest
linked device's link time *before* it calls `_transfer.send()`, and its catch
swallows every error. `send` can fail before the offer exists (no stored
device list entry to send to, offline relay, an export or upload error), and
by then the cursor has already passed the new device. The transfer is then
offered by nobody: every other device declines to act because only the
oldest non-fresh device is the designated sender.

**Trigger** `autoTransferToNewDevices: true` (off by default, and the app pins
it off at `helix_runtime.dart:231`) plus a new device linking while the
designated sender is offline or the relay errors. The new device gets no
history and, unless another device links later or the sender is revoked,
never will.

**Evidence** The cursor write is unconditional at
[395-399](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/backup_service.dart#L395-L399),
the send follows at
[403](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/backup_service.dart#L403),
and the catch at
[404-407](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/backup_service.dart#L404-L407)
records nothing. `send` throws `noOtherDevices` before it uploads anything
([113-115](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L113-L115))
and rethrows a relay or export failure after discarding
([197-209](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L197-L209)).
The sender election is `senders.first.isThisDevice`
([400-402](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/backup_service.dart#L400-L402)),
so no other device retries in its place. The write currently doubles as the
duplicate-send guard, which is why moving it is not a one-line change.

**Impact** A promise the option makes ("offer history to a device that has
just joined") silently not kept, with no failure recorded anywhere —
`BackupStatus` says nothing about transfers. Recovers only by accident.

**Fix sketch** Run `send` first; write the cursor only when it returns a
transfer id. To keep duplicate sends out, guard `_offerToNewDevices` with an
in-flight flag (or a `_offering` future) and treat "a transfer whose recipients
are these devices already exists" as done. Leave the cursor where it is when
`send` fails so the next `OwnDevicesChanged` tries again.

**Test that proves it** Engine test with `autoTransferToNewDevices: true` and a
relay fake that throws on `upload` for the first call: fire
`OwnDevicesChanged` (or call the hook), assert no transfer was created and the
stored cursor still precedes the new device's link time; then let the relay
work and fire it again — an offer arrives. Today the second step sends nothing.

**Overlap** AUD-12g-2 (keys after the server call) is the same "commit the
bookkeeping before the thing it describes" shape, but a different seam.

### AUD-12p-3 A paused transfer restarts itself when auto-accept is on

**Severity** P3 · **Confidence** confirmed

**Where** [device_transfer.dart:433-445](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L433-L445),
[device_transfer.dart:622-627](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L622-L627),
[backup_service.dart:303](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/backup_service.dart#L303),
[backup_service.dart:349-366](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/backup_service.dart#L349-L366)

**What** `pause` only cancels the run's token and marks the id in an in-memory
set. The catch turns the cancellation into `waiting` with `clearError: true`
— exactly the shape `_resumeOffers` calls "fresh" — and the run's `finally`
then empties `_paused`. The pause's own ledger write is what triggers
`_resumeOffers` (the service listens to `watchIncoming`), so with
`autoAcceptTransfers` on the offer is accepted again immediately, and the
maintenance pass would restart it even if the stream did not.

**Trigger** `autoAcceptTransfers: true` (off by default; the app pins it off
at `helix_runtime.dart:234`) and a user tapping Pause, which the app offers
while a transfer is downloading or importing
(`transfer_rows.dart:75-78`).

**Evidence** The paused branch sets `waiting` + `clearError`
([433-445](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L433-L445))
and `_paused.remove(id)` runs unconditionally in `finally`
([494-497](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L494-L497)).
`_resumeOffers`'s `fresh` is `waiting && error == null`
([352-359](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/backup_service.dart#L352-L359))
and it is subscribed to every incoming-ledger write
([303](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/backup_service.dart#L303)),
plus called with `retryFailed` on every maintenance pass
([328](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/backup_service.dart#L328)).
`_accept` never looks at `_paused` before fetching
([319-349](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L319-L349)).

**Impact** The one control that exists for "stop using my mobile data" does
nothing in the one configuration where transfers start without the user. The
paused offer is also indistinguishable from a never-started one on the
receiving list ("Accept" vs "Resume" is decided by `done > 0`,
`transfer_rows.dart:67-74`, and `done` is 0 during a download — see
AUD-12p-4), so the UI cannot even show that a pause happened.

**Fix sketch** Make "fresh" mean never started: `waiting && error == null &&
segments == null && imported == 0` — a paused run has the manifest (or an
import count), so it is no longer fresh. Persist the user's intent (a `paused`
flag on `IncomingOffer`) so a restart or a maintenance pass does not undo it,
and have `resume`/`accept` from the UI clear that flag. The in-memory
`_paused` set then only serves the run that is being cancelled.

**Test that proves it** Engine test with `autoAcceptTransfers: true`: accept,
let one segment land, `pauseTransfer(id)`, wait for a maintenance pass and a
ledger tick — the offer stays `waiting`, no further chunk is added, and only
an explicit `acceptOffer` resumes. Today it resumes by itself.

**Overlap** AUD-12p-4 (the `done` count that would let the row say "paused").

### AUD-12p-4 The offers list reports zero segments fetched while a download runs, and the app shows only that list

**Severity** P3 · **Confidence** confirmed

**Where** [backup_service.dart:252-268](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/backup_service.dart#L252-L268),
[models.dart:270-272](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/models.dart#L270-L272),
[backup_providers.dart:331-332](file:///J:/Projects/helix/helix_remote/app/lib/features/backup/application/backup_providers.dart#L331-L332)

**What** `TransferOffer.done` is documented as "segments fetched (while
downloading) or applied (while importing)", but `watchOffers` maps it as
`o.phase == importing ? o.imported : 0`, and the ledger has no fetched count
to offer. The app's receiving rows come only from `watchOffers`
(`incomingOffersProvider`, `backup_gateway.dart:162-181`), while the live
receiving events are thrown away (`TransfersController._onProgress` returns
for anything that is not `sending`). So a receiving transfer's bar sits at
"Receiving (0 of 12)" for the whole download and only moves during import.

**Trigger** Any accepted device-to-device transfer, including after the app is
reopened mid-download (the live stream has no replay).

**Evidence** The mapping is
[262](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/backup_service.dart#L262);
the model's promise is [270-271](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/models.dart#L270-L271);
the app drops receiving progress at
[331-332](file:///J:/Projects/helix/helix_remote/app/lib/features/backup/application/backup_providers.dart#L331-L332)
and renders `done of total` at `transfer_rows.dart:91,99`. The engine already
computes the true count while fetching (`progress(downloading, ++have, total)`,
[374-375](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L374-L375)) —
it just never persists it.

**Impact** Cosmetic but visible: the one long-running operation in Backup
shows no progress until it is nearly done, which reads as a stall. It also
removes the only signal AUD-12p-3's fix needs to tell "paused halfway" from
"never started".

**Fix sketch** Persist `fetched` on `IncomingOffer` (the same `updateIncoming`
write that records `imported` can record the count; one extra JSON field),
report it during `downloading`, and let `done` fall back to it. The app-side
alternative (fold receiving `transferProgress` into `incomingOffersProvider`)
is smaller but loses the count across a restart.

**Test that proves it** Engine test: a relay that stalls after the first
segment, pause or a failed second fetch, then `offers().first.done == 1` and
`total` equals the manifest's segment count. Today `done` is 0.

**Overlap** AUD-12p-3 (the same waiting shape), AUD-15-8 (a transfer's failure
cannot be cleared through `copyWith` — the offer model has the same pattern).

## Verified safe

- **Offer and manifest bounds.** `TransferLedger.maxOffers = 20` caps the
  ledger; `recordOffer` is idempotent and drops the 21st offer rather than
  growing the document; `inbox.dart:34` refuses a manifest whose pointer
  claims more than `maxManifestBytes` (1 MiB); `_fetchManifest` refuses more
  than 4096 segments or a segment over 64 MiB, and checks the transfer id and
  account id inside the manifest. `receivedAt` is stamped locally, so a
  hostile own device cannot pin an offer past `cleanUp` with a future date.
- **A failed or cancelled send leaves no relay objects.** Every `_put` records
  the id in the ledger as it lands and in the local `uploaded` list; `send`'s
  catch discards from that list, and a cancel that races an in-flight upload
  is still covered because the local list holds the id even when the ledger
  entry was removed first.
- **One run per offer.** `accept` shares a single future per transfer id
  (`_accepting`), so a repeat tap, an auto-accept and a resume cannot run two
  imports over the same chunks.
- **A resume is a real resume.** Pausing keeps the fetched chunks and the
  imported count; `_accept` asks `missingSequences` for the gaps only, and a
  chunk is added with a gap check, so an interrupted run neither re-fetches
  nor double-applies.
- **Accepting a finished or withdrawn offer is safe.** `done` returns an empty
  result, `cancelled` throws before touching the database, and `decline` is a
  no-op for an offer that is gone.
- **The backup state recovers from a corrupt document.** Both state documents
  and both ledgers decode failures to defaults/empty rather than throwing, so
  a half-written setting cannot wedge `status()` or `start()`.
- **`forgetBackupState` starts the version over.** It clears the local history
  state and deletes the remote copy best-effort, which is the right side to
  fail on (the server deletes it on a key change anyway).
- **Duplicate auto-offers are prevented by accident of the bug.** Because the
  cursor is written before the send, two `OwnDevicesChanged` events close
  together cannot both send to the same new device; any fix for AUD-12p-2 must
  keep an explicit guard (noted in its fix sketch).
- **The sender election is deterministic.** `senderOrder` sorts by link time
  (nulls first) with a device-id tiebreak, so every device reaches the same
  "who offers" answer.

## Coverage notes

- Both auto options are pinned off in the shipped app (`helix_runtime.dart`
  231-234), so AUD-12p-2 and AUD-12p-3 need a host (or a test) that turns them
  on. This is recorded as latent, not as unreachable: `BackupOptions` is public,
  the CLI takes the engine's defaults, and the server's client tests already
  run both on (`backup_test.dart:650-651`).
- The `pause` engine test runs with both options off (`support.dart:209-210`),
  which is why the auto-accept interaction has no failing test today.
- `ApiRelayStore.upload` (options.dart:84-94) creates a media object with no
  size cap and no "backup" kind; the server's media limits are the only bound.
  Not a finding (the archive budgets bound a segment), but it means a future
  `maxSegmentBytes` change on the receiver is the only place a huge segment is
  refused.
- `runMaintenance` swallows every error from cleanup, resume and the automatic
  backup in one catch (`backup_service.dart:326-342`). Each job records its
  own failure in its state, so this is not silent for a backup; it is silent
  for a transfer, which has no such record — the root of AUD-12p-2's impact.
- `BackupService.status()` reads three settings in three queries, so the
  stream can briefly report a new history state with the old switch value.
  Cosmetic, one frame; not written up.
