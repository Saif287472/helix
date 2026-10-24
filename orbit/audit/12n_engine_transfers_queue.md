# Sweep 12n - engine transfer queue and upload path

Scope: `packages/helix_remote_engine/lib/src/transfers/` - `outbound_media.dart`
(779), `transfer_worker.dart` (415), `upload_runner.dart` (283), plus the
cross-reads that settle them: the outbox's ordered claim
(`outbox_dao.dart:171-205`), the transfer queue's `due`/`claim`/`fail`
(`transfers_dao.dart:166-355`), `transfer_failure.dart` (139),
`media_processor.dart` (154), `transfer_files.dart` (86), and the
download-runner slices that share the worker's contract. ~1,900 lines.

Verdict: the bytes side is careful - encryption once into staging, digest of
the ciphertext, bounded resume, a lease renewed every chunk, cancellation at
every step, no plaintext in staging. The defects are all in the *queue's
bookkeeping around* those bytes: `stop()` is not a barrier, a job can be
started twice, and two paths leave a held outbox op that blocks a whole chat.

---

### AUD-12n-1 `stop()` is not a barrier: a job claimed while stopping runs after stop returns

**Severity:** P3
**Confidence:** confirmed
**Where:** [transfer_worker.dart:122-134](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_worker.dart#L122)
(`stop` cancels the tokens of the jobs in `_running` once and waits for those),
[transfer_worker.dart:169-196](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_worker.dart#L169)
(`_fill` keeps claiming while a `claim` it already awaited is in flight, and
`_start` has no `_active` check), [transfer_worker.dart:252-275](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_worker.dart#L252)
(`_execute` runs regardless).

**What:** `stop()` sets `_active = false`, cancels the subscriptions and then
cancels the tokens of the jobs *currently in `_running`*. A `_pump`/`_fill`
that was already awaiting `claim(...)` returns a job after that sweep, calls
`_start`, and the job's token was never cancelled - `_execute` runs the whole
transfer (for an upload: encrypt, `POST /v1/media`, upload every chunk) while
the engine believes the worker is stopped, and `stop()` returns before it ends.

**Trigger:** a stop (sign-out, engine close, backgrounding) that overlaps a
queue change waking `_pump`. The window is one `claim` round trip, but `_poke`
fires on every enqueue/retry/progress change.

**Evidence:** `_fill`'s loop condition is checked before `await claim` and not
after ([transfer_worker.dart:170-186](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_worker.dart#L170));
`_start` registers the job in `_running` unconditionally (189-196); `stop`
iterates `_running.values` at one instant (129-132). `_execute` never checks
`_active`.

**Impact:** a transfer keeps running past sign-out/close: it can upload bytes
with a session that is being revoked, write staging files after the file store
was wiped, and fail against a closed database (the failure is swallowed by
`_failed`'s catch). No local data is lost (the job row survives and resumes on
the next start), but "stopped" is not true, and any caller that relies on it
(sign-out wipe, tests) sees an unexpected concurrent writer.

**Fix sketch:** make `_fill` re-check `_active || _draining` after `await claim`
and release the job if it is false, and have `stop()` loop until `_running` is
empty (claiming is then impossible because the loop exits). Both are local
changes; no schema or wire change.

**Test that proves it:** hold `claim` open (a DAO fake), call `stop()`, then let
`claim` return a job; expect no runner call and the job still `pending`, and
`stop()`'s future to complete after the last job.

**Overlap:** AUD-12a-4 (the engine's worker lifecycle has the same
start/stop-serialisation gap); this is the transfer worker's own instance.

---

### AUD-12n-2 A job whose lease lapsed can be claimed a second time while its first attempt is still running

**Severity:** P3
**Confidence:** likely
**Where:** [transfer_worker.dart:169-187](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_worker.dart#L169)
(`_fill` claims without checking `_running`),
[transfer_worker.dart:254-264](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_worker.dart#L254)
(the heartbeat swallows every renewal error and keeps the attempt alive),
[transfers_dao.dart:166-182](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/daos/transfers_dao.dart#L166)
(`due` treats an `inFlight` job with an expired lease as claimable),
[transfer_worker.dart:402-414](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_worker.dart#L402)
(`progress` renews by id, so the old attempt keeps renewing the new lease).

**What:** the only thing that stops a running attempt is losing its lease
(`renewLease` false → token cancelled). The heartbeat catches every error from
`renewLease` and continues. If renewals fail for a full lease (60 s), the row's
`lease_until` is in the past; `_fill`, running in the same worker and seeing a
free slot in that direction, claims the same job again and starts a second
attempt. The first attempt's next successful renewal then extends the second
attempt's lease, so neither ever learns it lost the job.

**Trigger:** three consecutive lease renewals failing (a database lock held for
~60 s, heavy GC, a device under memory pressure) while the attempt is in a step
that does not call `progress` - notably `_encrypt` of a large file, which only
checks the cancellation token per chunk and never renews.

**Evidence:** `_fill` has no `_running.containsKey(job.id)` filter (179-185);
`_start` overwrites `_running[job.id]` with a new `_Running`, dropping the old
entry from the map so `stop()` and the counts no longer see it (189-191);
`due` includes `inFlight` with `lease_until <= now`
([transfers_dao.dart:170-176](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/daos/transfers_dao.dart#L170));
`renewLease` matches on `id AND state = inFlight`
([transfers_dao.dart:219-227](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/daos/transfers_dao.dart#L219)),
which the second claim just set, so the first attempt's renewal succeeds.

**Impact:** two attempts share one staging file (`up-$jobId` /
`dl-$jobId`, [transfer_files.dart:10-19](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_files.dart#L10)).
For an upload both open the same file for writing (the second re-encrypt
truncates it under the first) and both may complete, one of them with a digest
computed over bytes the other rewrote - the recipient then gets a file whose
digest matches but which does not decrypt. For a download both append at
different offsets and both check the digest, so one fails and the job retries.
The duplicate counts against `maxUploads`/`maxDownloads` twice as well.

**Fix sketch:** skip ids already in `_running` when claiming (`claim` could take
an `exclude` set), and treat a failed renewal as fatal after one retry instead
of swallowing it. A monotonic `claim_token` on the job (S10-2, B13) makes the
older attempt lose on its next `progress`.

**Test that proves it:** expire a claimed job's lease by hand (`leaseUntil` in
the past) while its attempt is blocked in a fake slow step, run `_fill`, then
let the first attempt call `progress`; expect exactly one runner invocation (a
counted fake), today two.

**Overlap:** AUD-10-3 and S10-2 (a claimed job has no identity); AUD-12n-1 (the
same "`_fill` starts what it should not").

---

### AUD-12n-3 A permanent local error is retried for the 30-day max age, and the chat waits behind it

**Severity:** P3
**Confidence:** confirmed
**Where:** [transfer_failure.dart:134-138](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_failure.dart#L134)
(everything unclassified becomes `RetryTransfer('internal')`),
[transfer_worker.dart:319-334](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_worker.dart#L319)
(retry until `maxAge`, 30 days),
[outbound_media.dart:444-452](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/outbound_media.dart#L444)
(the send is queued as a **held** outbox op),
[outbox_dao.dart:171-205](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/daos/outbox_dao.dart#L171)
(a pending op blocks every later op of its conversation).

**What:** an upload that fails for a local, permanent reason - the staging
write hits a full disk (`FileSystemException`), the blob store refuses a write,
the SDK throws an `OSError` - falls into `classifyTransferError`'s default and
is scheduled for another attempt. The attachment message's held op stays
`pending` with `nextAttemptAt = heldAt`, and `claimDueOrdered` treats a chat
with any pending op as blocked: **no later message in that chat is sent** until
the upload succeeds, is cancelled, or hits `maxAge` 30 days later. Only
`TransferFailure.fileMissing` (a file whose length changed) is terminal today.

**Trigger:** a device out of storage (or with a read-only/removed blob store)
sending a photo; every attempt fails at `_encrypt`'s first `sink.add`.

**Evidence:** `_encrypt`'s catch deletes the staging file and rethrows the
original error ([upload_runner.dart:209-213](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/upload_runner.dart#L209));
`classifyTransferError` has no `FileSystemException` case; `_failed`'s
`RetryTransfer` branch reschedules and only gives up after `_config.maxAge`
([transfer_config.dart:45-51](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_config.dart#L45));
the held op blocks its chat by design ([outbox_dao.dart:188-195](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/daos/outbox_dao.dart#L188))
and `reapHeld` only drops ops whose message is gone
([outbound_media.dart:729-742](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/outbound_media.dart#L729)).

**Impact:** one unsendable attachment silently freezes a whole conversation for
up to a month (the queue shows the upload "retrying" with an `internal` code;
later bubbles show as pending and never leave). Recoverable by cancelling the
message, which is not what "retrying" suggests.

**Fix sketch:** classify `FileSystemException`/`OSError` as a terminal local
failure (reuse `fileMissing`, or add `TransferFailure.localIo` with its own
copy) so `_giveUp` fails the message and the chat continues. The backoff is
right for the network, not for the disk.

**Test that proves it:** point a fake blob store's write at an `EACCES`/`ENOSPC`
error, send a photo, drain; expect the message `failed` with a local-error code
and a later message in the same chat to send (today the op stays held).

**Overlap:** AUD-12b-1/AUD-12i-1 (terminal send failures), AUD-5-4 (quota), and
the "held op blocks the chat" contract AUD-12b covered for the general outbox;
this is the engine-side classifier that feeds it.

---

### AUD-12n-4 A presigned (S3) upload loads the whole ciphertext into memory

**Severity:** P3
**Confidence:** likely
**Where:** [upload_runner.dart:116-121](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/upload_runner.dart#L116)
(`readBytes(staging)` then one `upload`).

**What:** when the server answers with a presigned target (`!target.resumable`,
which is how an S3-backed deployment hands out uploads), the runner reads the
entire encrypted staging file into a `Uint8List` and sends it in one request.
There is no client-side upload cap, and `MediaInput` accepts any file size; a
1-2 GiB video means 1-2 GiB of contiguous memory on top of the encryption
buffers and the app's own copy.

**Trigger:** sending a large file against a deployment configured with S3
object storage (the production node uses local storage today, where the target
is resumable).

**Evidence:** the staging file's length is `AttachmentCrypto.ciphertextLength`
of the source ([upload_runner.dart:66-69](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/upload_runner.dart#L66))
with no upper bound checked; `readBytes` returns the whole range
([blob_store.dart](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/blob_store.dart));
on Android an allocation that size is an `OutOfMemoryError`, which
`_execute`'s `catch (Object)` turns into `RetryTransfer('internal')` - so the
device retries the same allocation, and the chat waits (AUD-12n-3).

**Impact:** large media cannot be sent on an S3 deployment; the failure mode is
an OOM loop rather than a clear refutation. Local-storage deployments are
unaffected.

**Fix sketch:** stream the presigned PUT (the API client can send a stream) or
refuse sizes above a client cap before encrypting, with `tooLarge`. No schema
change.

**Test that proves it:** a fake media client that reports a non-resumable
target, with a 100 MiB staging file and a `readBytes` that throws above a
threshold; expect the upload to succeed (streamed) or fail `tooLarge`, not to
read it all.

**Overlap:** AUD-1c-4 (the server's S3 `read` does the same thing in the other
direction).

---

## Verified safe (checked, no finding)

- **One transaction per send**: message row, attachment rows, upload jobs and
  the held op are written together, and a failure before it discards every copy
  the send made ([outbound_media.dart:155-188, 373-465](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/outbound_media.dart#L155)).
- **Attachment order is stable**: `insertMessage` assigns `position` by index
  ([messages_dao.dart:79-85](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/daos/messages_dao.dart#L79)),
  and `attachmentsFor` orders by it, so the job-to-row pairing in `_write` is
  sound.
- **The encryption is done once and is what is measured**: the staging file's
  length must equal `ciphertextLength` before upload, the digest is taken from
  the staged bytes, and a length change of the source is `fileMissing`
  ([upload_runner.dart:60-84, 186-220](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/upload_runner.dart#L60)).
- **Resume is bounded on both ends**: the server's reported offset is clamped
  to the expected length, a conflict with `upload_offset` is followed at most 5
  times, and a server that stores nothing is given up after 3 stalls
  ([upload_runner.dart:136-183](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/upload_runner.dart#L136)).
- **Cancellation reaches every step**: tokens are checked per chunk, passed to
  every request, and `progress` cancels the attempt when the lease is lost
  ([transfer_worker.dart:386-415](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_worker.dart#L386)).
- **A release cannot be duplicated**: `outboxDao.release` only changes a held
  op, so a second completion writes nothing
  ([outbox_dao.dart:109-130](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/daos/outbox_dao.dart#L109)).
- **`completeUpload` and `cancelSend` re-check inside their transactions**
  (job still there, attachment still there), so the common cancel races are
  handled.
- **Forwarding is honest about what it needs**: it refuses a message not
  finished uploading or a view-once message, reuses the object only inside
  `forwardReuseWindow`, and otherwise re-uploads from the local copy or refuses
  with a clear state ([outbound_media.dart:197-305](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/outbound_media.dart#L197)).
- **The file extension is sanitised** to `[a-z0-9]{1,8}` from a name or a fixed
  mime table ([transfer_files.dart:28-61](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_files.dart#L28)).
- **The default media processor only reads a header** (256 KiB) and never
  rewrites the file, so the size measured before it stays correct
  ([media_processor.dart:56-83](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/media_processor.dart#L56)).
- **Worker limits hold per direction**, thumbnails share the download budget,
  and a job of an unhandled standalone purpose is handed back for an hour
  instead of failing ([transfer_worker.dart:169-187, 278-304](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_worker.dart#L278)).

## Coverage notes (not findings)

- `transfer_jobs.kind` documents `delete` as a fourth kind
  ([transfers.dart:20](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/tables/transfers.dart#L20)),
  but no producer enqueues one and the worker's `default` would fail it as
  `unknown`. Dead vocabulary, not dead code.
- `_uploadThumbnail` runs before the source-size check, so a missing source
  still uploads (and pays for) the thumbnail first; the attachment then fails
  and the thumbnail object expires on the server. Waste, not loss.
- `MediaService.cancel` on an upload delegates to `cancelSend`, which deletes
  the server object only by the id recorded on the job; an object created by
  the last in-flight attempt after that read expires on the server instead
  (30 days). Documented behaviour of `_deleteRemote`, same for a crash.
- `stop()`'s `Future.wait` runs while `_stopping` is true; a runner that throws
  during it is handed back as pending with no attempt counted, as documented.
