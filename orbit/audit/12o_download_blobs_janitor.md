# Sweep 12o - download runner, blob stores, janitor, failure mapping

Scope: `packages/helix_remote_engine/lib/src/transfers/` - `download_runner.dart`
(336), `blob_store.dart` (165), `memory_blob_store.dart` (196),
`media_janitor.dart` (103), `transfer_failure.dart` (139), plus the cross-reads
that settle them: `media_service.dart`'s retry/cancel/download entry points
(60-203), `outbound_media.dart`'s failure/retry/cancel half (600-779),
`transfers_dao.dart`'s `_enqueue`/`enqueueThumbnail`/`live`/`resetProgress`
(40-305), `inbound_media.dart` (84), `media_settings.dart` (54), the API's
`MediaClient.download` (75-154), and `AttachmentCrypto`'s size arithmetic.
~1,600 lines.

Verdict: the download is well built - the pointer's size bounds everything, the
digest is checked before any decrypt, decryption streams, and the completion
transaction re-checks that the job and the row still exist. The two defects are
both bounds: one bound is *too small* (it is computed with the largest legal
chunk size, not the one the sender used) and one bound does not exist (a failed
upload keeps its whole ciphertext in staging for ever).

---

### AUD-12o-1 The whole-object download cap is computed with the largest chunk size, so a legitimate object can exceed it

**Severity:** P3
**Confidence:** likely (the arithmetic is confirmed; production thumbnails are small)
**Where:** [download_runner.dart:140-144](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/download_runner.dart#L140)
(`maxBytes: AttachmentCrypto.ciphertextLength(size, chunkSize: maxChunkSize)`),
[download_runner.dart:271-279](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/download_runner.dart#L271)
(the thumbnail is fetched whole under the same bound),
[upload_runner.dart:238-243](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/upload_runner.dart#L238)
(the sender encrypts with `_config.encryptionChunkBytes`),
[attachments.dart:25-44](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/attachments.dart#L25)
(`defaultChunkSize` 64 KiB, `maxChunkSize` 1 MiB, one 16-byte tag per chunk),
[media_client.dart:90-114](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/clients/media_client.dart#L90)
(a body longer than `maxBytes` throws `ResponseTooLargeException` while it
streams).

**What:** `ciphertextLength(size, chunkSize)` grows with the number of chunks,
so computing it at the *largest* legal chunk size gives the *smallest* possible
ciphertext for that plaintext. The sender encrypts at `encryptionChunkBytes`
(the default 64 KiB), which is smaller, so the object on the server is longer
than the cap by `16 * (chunksAt64K - chunksAt1M)`. For a 100 KiB thumbnail that
is 16 bytes; for a 2 GiB file ~240 KB. The cap is right for a *range* response
(512 KiB at a time) but wrong wherever the **whole object** is fetched:

- `_fetchThumbnail` requests the thumbnail with no range, so the whole object
  must pass the cap: any thumbnail over 64 KiB (up to the accepted 512 KiB) is
  refused with `ResponseTooLargeException`, which classifies as
  `sizeMismatch` - terminal.
- `_fetch`'s first request (`start: 0`) *may* be answered with the whole object
  by a server that ignores ranges (the client explicitly allows this), and then
  any file over 64 KiB exceeds the cap and the download fails `size_mismatch`.

**Trigger:** an attached thumbnail whose JPEG is larger than 64 KiB (accepted on
send up to `maxThumbnailBytes` = 512 KiB, so a different client or a different
processor setting is enough; the current app's 320 px thumbnails are a few
KiB), or a media server/proxy that answers the first ranged GET with the whole
object.

**Evidence:** the arithmetic is the crypto's own: `chunks = ceil(size /
chunkSize)` ([attachments.dart:36-44](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/attachments.dart#L36)).
`upload_runner._uploadThumbnail` seals with `_config.encryptionChunkBytes`
([upload_runner.dart:238-243](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/upload_runner.dart#L238));
`_ingest` accepts a thumbnail up to `maxThumbnailBytes` = 512 KiB
([transfer_config.dart:22](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_config.dart#L22)).
`download_runner` computes both caps at `maxChunkSize`; the transport throws
rather than truncating ([transport.dart:395](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L395)),
and `classifyTransferError` turns that into a permanent `sizeMismatch`
([transfer_failure.dart:113-116](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_failure.dart#L113)).

**Impact:** a thumbnail held by any client that writes JPEGs over 64 KiB never
appears, and its on-demand job ends failed with a misleading `size_mismatch`;
on a range-ignoring server, every download over 64 KiB fails permanently. Both
failures are silent to the sender and terminal to the receiver.

**Fix sketch:** bound a whole-object fetch with `ciphertextLength(size,
chunkSize: minChunkSize)` (the largest ciphertext that plaintext can have), and
leave the per-range cap as the requested length plus one tag. No schema or wire
change.

**Test that proves it:** encrypt 100 KiB with `defaultChunkSize`, serve it
whole from a fake media client, and run `runThumbnail`: expect the thumbnail to
be stored (today `ResponseTooLargeException` -> `failed`).

**Overlap:** AUD-1c-4 (the server's S3 `read` loads a whole object the other
way); AUD-12n-4 (the upload side's unbounded whole-object read).

---

### AUD-12o-2 A failed upload keeps its whole ciphertext in staging for ever, and nothing counts it

**Severity:** P3
**Confidence:** confirmed
**Where:** [media_janitor.dart:78-93](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/media_janitor.dart#L78)
(the sweep keeps every staging path of a job in `live()`),
[transfers_dao.dart:293-299](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/daos/transfers_dao.dart#L293)
(`live` is "not done", so `failed` counts),
[upload_runner.dart:63-84](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/upload_runner.dart#L63)
(the staging file is the whole ciphertext),
[outbound_media.dart:606-634](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/outbound_media.dart#L606)
(a terminal failure touches the row and the message, not the files).

**What:** an upload first encrypts the file into `up-$jobId` (a full copy of the
ciphertext: the size of the source plus tags). When the job ends `failed` -
quota exceeded, payload too large, rejected, expired, or the 30-day `gaveUp` -
the staging file stays. It is deleted only by `cancelSend` (delete the message)
or overwritten by a retry. The janitor will not take it: `live()` is
"state != done", and a failed job is live, so `TransferFiles.allFor` is kept.
The Storage page counts `attachments.local_path` only, so the bytes are
invisible; nothing ages them out.

**Trigger:** any outgoing media that ends failed and is left in the chat - the
common case being a full account quota or a 30-day network failure. Each such
message keeps ciphertext equal to its file size (a 2 GiB video keeps 2 GiB on
top of the source copy the attachment still holds).

**Evidence:** `live()` is `state != done` ([transfers_dao.dart:293-299](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/daos/transfers_dao.dart#L293))
and its own doc says "everything that may still own staged bytes"; the janitor
keeps those paths without an age test
([media_janitor.dart:79-83](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/media_janitor.dart#L79)).
`_giveUp` -> `fail` -> `uploadFailed` never deletes files
([transfer_worker.dart:356-375](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_worker.dart#L356),
[outbound_media.dart:606-634](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/outbound_media.dart#L606)).
`storageUsage` counts attachment paths only
([media_service.dart:232-250](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/media_service.dart#L232)).

**Impact:** the device keeps one invisible copy per failed send, for as long as
the message exists. On a phone that fills its disk it is the *encrypted* copy
(equal in size to the file) that no screen offers to free, and the user cannot
even see it. Retrying is the only use, and that is what the keep was for.

**Fix sketch:** for **upload** jobs only, have the janitor delete the staging
file of a failed job older than the sweep grace (the source is still in the
media area, so a retry re-encrypts; nothing is lost). Downloads keep theirs:
the fetcher's bytes cost re-downloading, not re-encryption. Alternatively
`uploadFailed` deletes staging at once when the failure is terminal and not
retryable (`tooLarge`, `rejected`, `expired`, `quotaExceeded`), and the janitor
handles `gaveUp`.

**Test that proves it:** fail an upload with `quotaExceeded`, age every file
past `sweepGrace`, sweep; expect `up-<id>` gone and the plaintext source still
present, and a retry to re-encrypt and succeed.

**Overlap:** AUD-12m-1 (what the Storage page counts); AUD-12n-3 (the failure
classifier that decides when a job ends); B13's "a job that stops doing its
work".

---

## Verified safe (checked, no finding)

- **The pointer's size bounds the download from the first byte to the last**:
  `total` comes from the pointer's plaintext size and the file header's chunk
  size (not from the server's Content-Length), every chunk is refused past it,
  and the digest is checked before decrypting
  ([download_runner.dart:126-200](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/download_runner.dart#L126)).
- **A short or reordered file cannot be assembled**: decryption authenticates
  every chunk and the last-chunk flag, the plaintext length must equal the
  pointer's size, and a failure deletes the plaintext (and the ciphertext when
  it cannot get better) before retrying
  ([download_runner.dart:202-238](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/download_runner.dart#L202)).
- **Completion and cancellation are decided inside the transaction**: the job
  and the attachment are re-read, and a file assembled for a message that went
  meanwhile is deleted
  ([download_runner.dart:101-115](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/download_runner.dart#L101)).
- **The thumbnail is a separate, bounded object**: its pointer's size is capped
  at `maxThumbnailBytes`, its decrypted length must match, and a view-once
  message never gets one on arrival
  ([download_runner.dart:252-306](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/download_runner.dart#L252),
  [inbound_media.dart:57-69](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/inbound_media.dart#L57)).
- **The janitor's rule is sound for everything except failed-job staging**: it
  derives what to keep from the rows (attachment paths, live jobs' staging and
  sources), never from the delete call sites, and `sweepGrace` protects a file
  being written while a sweep runs
  ([media_janitor.dart:8-23, 72-102](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/media_janitor.dart#L72)).
- **A sweep cannot run twice at once** (`_sweeping`) and a sweep that fails
  (the database closed) deletes nothing
  ([media_janitor.dart:72-101](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/media_janitor.dart#L72)).
- **`BlobStore`'s contract is tight**: paths are opaque and random, `namedPath`
  is deterministic (so a restart finds the work), `openWrite(keep:)` truncates,
  and `NoBlobStore` throws for anything that would create or read a file while
  making `delete`/`list`/`clear` harmless
  ([blob_store.dart:43-165](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/blob_store.dart#L43)).
- **`MemoryBlobStore` matches the contract**: it refuses `keep` past the end,
  streams in `readChunk` pieces, copies seeded files, and `clear` removes only
  its own areas
  ([memory_blob_store.dart:55-145](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/memory_blob_store.dart#L55)).
- **`classifyTransferError` is exhaustive for the API's error types** and maps
  a range that is not honoured or a body that is too large to a terminal
  failure, not a retry loop
  ([transfer_failure.dart:100-139](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/transfers/transfer_failure.dart#L100)).

## Coverage notes (not findings)

- `enqueueStandalone` and `TransfersService.registerStandalone` have **no
  producer or caller** outside the database tests: the standalone transfer
  machinery (a group avatar, a backup blob) is vocabulary without a user today.
  AUD-10-4 and the `delete` kind's dead vocabulary sit on the same shelf.
- `_enqueue` re-queues a job without clearing `leaseUntil`, so a job retried
  while its old lease is still in the future waits for that lease before
  `due()` offers it again (up to `lease` = 60 s). A delay, not a loss.
- `enqueueThumbnail` returns an existing `download` job's id, so a thumbnail
  request while a download is queued never creates a second job; the download
  fetches the thumbnail itself (and swallows its failure by design).
- `downloadFailed` keeps staged bytes for `gaveUp`/`quotaExceeded` on purpose
  (a UI retry resumes); `cancel` and `cancelSend` delete everything a job owns.
- The janitor's sweep reads every attachment path and lists both areas on every
  attachment-count drop (debounced 200 ms) and every 10 minutes - O(history)
  per sweep, but no measured harm.
