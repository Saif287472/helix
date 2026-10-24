# Sweep 12m - engine transfers, part one (MediaService, TransfersService, config, views, settings, storage)

Scope: `packages/helix_remote_engine/lib/src/transfers/` part one - `media_service.dart`
(510), `transfers_service.dart` (67), `transfer_config.dart` (105),
`transfer_views.dart` (167), `media_settings.dart` (54), `media_storage.dart` (39),
plus the queries they depend on (`messages_dao.dart` `storedMediaByKind` /
`detachLocalMedia`, `transfers_dao.dart` `enqueue*` / `claim` / `fail` / `remove`)
and the arrival path (`inbound_media.dart`) to check what these services assume.
~1,050 lines read in full, ~700 cross-read.

Verdict: the service layer is thin and mostly honest - each method is a
transaction or a watch query, the worker owns the bytes, and the cancel/retry
paths match their docs. Four defects, all P3/Idea: the storage page treats the
device's copy of *sent* media as "downloaded" media (and "free up space" deletes
it), `cancel` acts on a stale snapshot of the attachment/job, `retryFailed`
retries inside one long transaction, and the three media-kind classifiers have
already drifted apart.

---

### AUD-12m-1 Storage and "free up space" count and delete sent media, which stops being fetchable 30 days after the upload

**Severity:** P3
**Confidence:** confirmed
**Where:** [media_service.dart:230-250](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/media_service.dart#L230)
(`storageUsage`, "what downloaded attachments take on this device"),
[media_service.dart:253-289](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/media_service.dart#L253)
(`biggestChats`, "the chats whose **downloaded** photos…"),
[media_service.dart:291-315](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/media_service.dart#L291)
(`freeChatSpace`), [messages_dao.dart:578-609](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/daos/messages_dao.dart#L578)
(`detachLocalMedia`: conversation + kind + `transfer = ready` + `local_path IS NOT NULL`,
no `outgoing` condition), [outbound_media.dart:488-512](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/outbound_media.dart#L488)
(sent attachments are inserted with `localPath` = the app's copy) and
[outbound_media.dart:540-543](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/outbound_media.dart#L540)
(they end `transfer: ready`), [transfer_failure.dart:28-30](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_failure.dart#L28)
(`expired`: "the server no longer has the object (30 days after the upload)").

**What:** `storedMediaByKind` counts every attachment with a local file,
including outgoing ones, so the Storage page's per-chat breakdown is dominated by
photos the user *sent*, not by what they downloaded. `detachLocalMedia` frees
the same rows: `freeChatSpace(chat, photosVideos)` clears `local_path` and marks
the attachment `remote` on sent messages too, then deletes the app's copy. The
copy is the only file the bubble owns; re-fetching works only while the server
still has the object.

**Trigger:** open Storage after sending a lot of photos (usage looks inflated),
or use "free up space" on a chat the user mostly wrote in. Nothing warns that
sent media goes too.

**Evidence:** `_companionOf` writes `localPath: Value(p.localPath)` for outgoing
attachments at send time ([outbound_media.dart:512](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/outbound_media.dart#L512)),
and the upload's completion sets `transfer: ready` without touching it
([outbound_media.dart:540-544](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/outbound_media.dart#L540)).
`detachLocalMedia` selects on `transfer = ready` and `local_path IS NOT NULL`
only ([messages_dao.dart:589-594](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/daos/messages_dao.dart#L589)),
so an outgoing ready row qualifies. Re-download after freeing goes through the
same `downloadNow`, whose only failure mode for a message older than the server's
retention is `expired` ([download_runner.dart:61-63](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/download_runner.dart#L61)
raises it; `classifyTransferError` maps 404/expired to `TransferFailure.expired`,
[transfer_failure.dart:125-126](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_failure.dart#L125)).
`TransferConfig` keeps objects for 30 days ([transfer_config.dart:51](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_config.dart#L51)).

**Impact:** the Storage page misreports "downloaded" bytes, and freeing space in
an old chat silently removes a re-fetchable-*then*, unavailable-*later* copy of
the user's own media (the bubble shows "download", which fails with "expired").
No loss of the user's original file outside the app, and nothing on the wire;
the damage is a promise in the UI that stops being true.

**Fix sketch:** exclude outgoing rows from both the count and the detach:
`WHERE a.local_path IS NOT NULL AND m.outgoing = 0`. If sent media should be
freeable, make it a separate action with its own warning, and keep the copy for
messages younger than the server's retention is irrelevant - the file the user
made is the point. One query line plus tests; no schema or app change.

**Test that proves it:** send a photo in a chat, then `storageUsage()` /
`biggestChats()` / `freeChatSpace(chat, photosVideos)`; expect the sent photo's
bytes to be absent/untouched and its `localPath` still set (today all three
include it and the file is deleted).

**Overlap:** AUD-10-2/AUD-10-3 (same DAO surface, different defect); no earlier
finding covers storage accounting.

---

### AUD-12m-2 `cancel` decides from a pre-transaction snapshot: a download that finishes in the gap is marked "not downloaded" while its file stays

**Severity:** P3
**Confidence:** likely
**Where:** [media_service.dart:139-161](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/media_service.dart#L139)
(`cancel` reads `a` and `job` before the transaction, then removes the job and
resets the attachment from the stale `a.transfer`),
[download_runner.dart:103-115](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/download_runner.dart#L103)
(the completion transaction writes `ready` + `localPath`).

**What:** `cancel` is three steps: read attachment + job; in a transaction
`remove(job.id)` and, if the *old* `a.transfer` was `downloading`/`failed`, set
`remote`; then cancel the running job. If the download's own completion
transaction commits between the read and `cancel`'s transaction, the attachment
is already `ready` with the file at `dest`, but `cancel` still sees
`downloading`, so it resets the row to `remote` **without clearing `localPath`**.
A later "download" then re-fetches and overwrites the path; the earlier file is
orphaned (the janitor collects it, but only after `sweepGrace`).

**Trigger:** the user cancels exactly as a download completes - a narrow window
(the runner's completion is one short transaction), but cancel is a UI tap and
the completion is asynchronous.

**Evidence:** the read at lines 140-142 is outside the transaction opened at
148; the update at 151-156 writes only `transfer` ([messages_dao.dart:445-458](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/daos/messages_dao.dart#L445)
leaves `localPath` when the parameter is null); the runner's own cancel check
([download_runner.dart:104](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/download_runner.dart#L104))
only protects the other order (cancel first), which is the common one.

**Impact:** a bubble that says "not downloaded" while the file is on disk and
referenced; tapping download wastes the whole transfer again; one orphaned file
until the next sweep. No data loss.

**Fix sketch:** do the whole decision inside the transaction: re-read the
attachment and the job there, and set `remote` only when the job row still
exists at the moment of removal. The runner's existence check already handles
the opposite order.

**Test that proves it:** complete a download inside a transaction that is not
yet committed, run `cancel` before it commits (or call `cancel` after
`markDone` but with a stale `a`), then assert `transfer == ready` and
`localPath` unchanged; today it becomes `remote` with `localPath` set.

**Overlap:** AUD-10-3 and S10-2 (job identity/lease); this is the service-side
half of the same "no identity on the claimed job" theme.

---

### AUD-12m-3 `retryFailed` retries every failed job inside one transaction, including the send path

**Severity:** P3
**Confidence:** confirmed
**Where:** [transfers_service.dart:26-56](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfers_service.dart#L26)
(`_db.transaction(() async { for (final job in await live()) … _outbound.retry(…) … enqueueDownload(…) })`),
[outbound_media.dart:641-674](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/outbound_media.dart#L641)
(`retry` opens its own transaction and re-holds the outbox op).

**What:** "retry every failed transfer" runs the whole loop - reads of `live()`,
per-job attachment lookups, the upload/send retry (nested transactions,
outbox hold, status advance) and each download enqueue - inside a single outer
transaction. On SQLCipher (one connection) that serialises all writes, including
the transfer worker's `setProgress` after each chunk and every watch query's
scheduler pass, for as long as the sweep takes (N jobs, each a handful of
queries). If any step throws, every retry in the sweep is rolled back.

**Trigger:** a queue with several failed jobs (e.g. after a long offline period),
and the "retry all" button.

**Evidence:** the outer transaction encloses the loop at line 26; `_outbound.retry`
is itself `_db.transaction` ([outbound_media.dart:641](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/outbound_media.dart#L641)),
and `enqueueDownload` + `updateAttachment` are two more writes per download
([transfers_service.dart:39-50](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfers_service.dart#L39)).

**Impact:** a UI freeze or a lost batch rather than corrupt state - each retry
is independently safe, so the outer transaction buys atomicity nobody asked for
at the cost of lock time.

**Fix sketch:** drop the outer transaction; each `_outbound.retry` and each
`enqueueDownload` is already transactional (and a partially retried batch is the
documented behaviour of "retry all" anyway). No schema/wire change.

**Test that proves it:** while a `retryFailed` over k failed jobs is running,
assert a concurrent `setProgress` commits without waiting for the sweep (today
the connection is held); or make job k+1 throw and assert jobs 1..k stay retried.

**Overlap:** none.

---

### AUD-12m-4 (Idea) One media-kind classifier instead of three that already disagree

**Severity:** Idea
**Confidence:** confirmed
**Where:** [media_service.dart:227-228](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/media_service.dart#L227)
(`_photoKinds = {image, video, video_note, gif}`, `_documentKinds = {document, unknown}`),
[media_settings.dart:43-48](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/media_settings.dart#L43)
(`forKind`: `sticker` downloads as an image; everything else is a document),
[media_storage.dart:10-16](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/media_storage.dart#L10)
(`filesBytes` = "documents, and kinds from a newer client").

**What:** three places classify attachment kinds and none agrees. A kind from a
newer client is counted in `filesBytes` (the `else` branch) but is neither in
`_documentKinds` (so `freeChatSpace(documents)` cannot free it) nor in
`biggestChats` (so the totals shown on the Storage page and the per-chat list
disagree). `sticker` is special-cased for auto-download but unreachable as an
attachment kind today, so it is silently in the first group and last group only
in theory.

**Trigger:** a client that adds a kind (the design expects this - the comment in
`media_storage.dart` says so) sends it to this device.

**Impact:** bytes shown as freeable are not, and the two storage views add up
differently. Cosmetic today.

**Fix sketch:** one `MediaKindGroup` mapping (photo / voice / file) in
`media_settings.dart`; `MediaSettings.forKind`, `_photoKinds`/`_documentKinds`
and the storage grouping read from it. A switch statement per consumer is fine
as long as it is the same statement. No behaviour change for today's kinds.

**Test that proves it:** a fixture with a kind of `video_note`, `document` and a
made-up kind; assert `storageUsage().totalBytes == biggestChats().sum +
voice` and that `FreeKind.documents` frees every kind counted in `filesBytes`.

**Overlap:** none.

---

## Verified safe (checked, no finding)

- **Config is all used**: `maxAge` is read in the worker's give-up check
  ([transfer_worker.dart:320](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_worker.dart#L320)),
  `idlePoll` in its timer ([transfer_worker.dart:208](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_worker.dart#L208)),
  `sweepGrace` by the janitor ([media_janitor.dart:84](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/media_janitor.dart#L84)),
  `forwardReuseWindow` in forwarding ([outbound_media.dart:211](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/outbound_media.dart#L211)),
  `maxDownloadBytes`/`maxThumbnailBytes` at arrival and in the runners
  ([inbound_media.dart:41,61](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/inbound_media.dart#L41),
  [download_runner.dart:58,268](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/download_runner.dart#L58)).
- **`downloadNow` cannot be talked into fetching an unbounded or unaccounted
  file**: empty `mediaId` throws, a ready-and-present file is a no-op, the
  worker re-checks `maxDownloadBytes` before the first request.
- **Attachments never auto-download over the cap**: `inbound_media` checks size
  before enqueue (`a.size > 0 && a.size <= maxDownloadBytes`), thumbnails are
  bounded separately, view-once gets no thumbnail.
- **Task deletion cannot strand a job**: `transfer_jobs.attachment_rowid`
  cascades on delete ([transfers.dart:26-32](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/tables/transfers.dart#L26)).
- **The view model is a pure function** with value equality, a thumbnail job
  correctly ignored, `bytesDone` clamped, and `bytesTotal` from the same
  ciphertext-length formula the runners use ([transfer_views.dart:78-135](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_views.dart#L78)).
- **View-once consumption is guarded**: the transaction re-checks the state that
  authorises it (outgoing needs `status == viewed`, incoming `opened`) and
  throws otherwise; files are deleted after commit ([media_service.dart:322-356](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/media_service.dart#L322)).
- **Settings are read at arrival, per attachment** (`settingsDao.get(forKind)`),
  so a policy change applies to the next message, as documented - no cached copy.
- **`retry` cannot throw on an outgoing failed attachment**: a failed upload
  always has an empty `mediaId`, so `_outbound.retry` handles it and returns
  true; `downloadNow`'s `StateError` is unreachable from that path.

## Coverage notes (not findings)

- `TransferPhase.queued` is the catch-all when `transfer == downloading` and no
  live job exists - exactly the state AUD-10-3 produces; the spinner-forever
  symptom lives there, the cause is the DAO.
- `_combine` (`media_service.dart:473-510`) has no `onPause`/`onResume`; a
  paused listener keeps the two DAO watches alive. Drift's own streams do the
  same, so no change is warranted.
- `watchMessage` combines the attachment watch with the whole `watchLive()`
  table, so every job change re-runs `_views` for every open bubble; `distinct`
  limits rebuilds. Fine at today's queue sizes.
- The thumbnail job never used `TransferFiles.downloading` or an offset (the
  thumbnail is fetched whole in memory, [download_runner.dart:244-306](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/download_runner.dart#L244)),
  so converting it into a download job cannot resume at a thumbnail offset -
  the only consequence is AUD-10-3's lost download.
- `isAvailable`/`_requireStore` is a state check, not an error path: the app
  always passes a blob store; a headless host without one throws on send as
  documented.
