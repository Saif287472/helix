# Sweep 12r — `helix_remote_engine`: the transfer receiver, `inbox`, `errors`

**Where:** `packages/helix_remote_engine/lib/src/backup/` —
`device_transfer.dart:240-667` (receiver half, `_fetch`, `decline`,
`cleanUp`, `senderOrder`), `inbox.dart` (57), `errors.dart` (109), plus
`state.dart:300-422` and `:198-286` (the ledger it drives);
`packages/helix_remote_db/lib/src/daos/transfers_dao.dart:375-453` (chunks).
Cross-reads: `snapshot.dart:102-172` (what a segment holds),
`backup_service.dart:244-284` and `349-366` (the streams and what resumes),
`transfer_views.dart` (the media views, to keep them apart),
`app/lib/features/backup/application/{backup_providers,transfer_rows,backup_gateway}.dart`,
`app/lib/core/engine/helix_runtime.dart:215-244`, the crypto's
`attachments.dart:25-140`, the api's `transport.dart:418-450` and
`media_client.dart:87-131`, and the tests that are supposed to hold this
(`packages/helix_remote_engine/test/backup/{transfer_test,support}.dart`,
`server/test/client/engine/backup_test.dart:293-352`).

The receiving state machine is careful: a manifest is bounds-checked before
anything is fetched, every object is digest- and size-checked, chunks are
gap-checked before an import starts, a gap means the whole transfer is asked
for again, and a resume is idempotent. The defects are elsewhere: one is a
byte-cap arithmetic error that makes the feature fail at its default
configuration, and the others are the receiving and sending sides of a
transfer having no durable, truthful place to live.

## Findings

### AUD-12r-1 A history transfer over 64 KiB fails on its first segment: the receive cap is computed with the wrong chunk size

**Severity:** P1  **Confidence:** confirmed
**Where:**
[device_transfer.dart:561-570](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L561-L570)
(the cap),
[device_transfer.dart:227-232](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L227-L232)
(how the segment was sealed),
[attachments.dart:25-44](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/attachments.dart#L25-L44)
(the constants and the size formula),
[transport.dart:421-442](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L421-L442)
(where the cap is enforced).
**What:** `_put` seals each segment with `AttachmentCrypto.encryptBytes(plain,
key, random: …)` and no `chunkSize`, so the writer uses
`defaultChunkSize` (64 KiB) and the ciphertext is
`16 + S + ceil(S/65536)·16` bytes. `_fetch` bounds the download with
`ciphertextLength(pointer.size, chunkSize: AttachmentCrypto.maxChunkSize)`,
i.e. `16 + S + ceil(S/1048576)·16` — four tags for a 4 MiB segment where the
object actually carries 64. The API reads the body with
`_readCapped(streamed, maxBytes)` and throws `ResponseTooLargeException` as
soon as the streamed length passes the limit (or at once, from
`content-length`). Every segment larger than 65 536 bytes therefore exceeds
its own cap; the default `segmentBytes` is 4 MiB
([options.dart:127](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/options.dart#L127)),
so any transfer of more than ~64 KiB of history dies on segment 0, after the
manifest (a few hundred bytes) has been fetched successfully.
**Trigger:** Link a new phone and send it the history (the restore step's
"Send history to this device", or Settings > Backup > Transfer). Any history
over 64 KiB — a few hundred messages — is enough.
**Evidence:** `encryptBytes`'s default is `defaultChunkSize`
(attachments.dart:25, 127); `_fetch` passes `maxChunkSize` (device_transfer
565-568); `maxChunkSize` is 1 MiB (attachments.dart:27). For S = 4 MiB the
object is 4 195 344 bytes and the cap is 4 194 384 — 960 bytes short;
for S = 100 000 it is 16 bytes short; for S ≤ 65 536 the two agree, which is
exactly why every test passes: the engine transfer test runs
`segmentBytes: 3000` (transfer_test.dart:21), the server's "large history
moves in segments through the real relay" test runs `segmentBytes: 20000`
(backup_test.dart:299-303), and the engine's `FakeRelay.download` ignores its
`maxBytes` argument altogether (support.dart:136-150). The app and the CLI
never override `segmentBytes` (helix_runtime.dart:227-243), so production runs
the 4 MiB default.
**Impact:** The device-to-device restore — the only in-app way to move a
history to a new phone without the recovery secret — fails for every real
history. The receiver shows "Receiving (0 of N)" and then
`BackupProblem.unknown` ("Something went wrong",
backup_gateway.dart:334-335), because `ResponseTooLargeException` is not one
of the types `BackupException.translate` knows (errors.dart:81-108); the
offer is left in `downloading` (see AUD-12r-2). No data is lost — the old
phone still holds the history — but the person has no way to complete the
flow, and the sender is told nothing (AUD-12r-3).
**Fix sketch:** Make the reader's bound match the writer's by construction: in
`_fetch`, compute the cap from the chunk size the segment was sealed with
(pass `AttachmentCrypto.defaultChunkSize`, or seal segments with
`chunkSize: maxChunkSize` so the cap is right), or add the tag slack:
`ciphertextLength(size, chunkSize: defaultChunkSize)`. Adding a ceiling on
the whole transfer's size belongs in the same change (see Structure).
**Test that proves it:** A transfer with the *default* `segmentBytes` and a
history over 64 KiB, through a relay that enforces `maxBytes`:
`FakeRelay.download` should throw `ResponseTooLargeException` when the bytes
exceed `maxBytes` (it currently ignores it), and the existing server e2e
"large history" test should stop pinning `segmentBytes: 20000` to a value
below 64 KiB. A unit test asserting
`ciphertextLength(S, chunkSize: maxChunkSize) >= ciphertextLength(S,
chunkSize: defaultChunkSize)` for S = `segmentBytes` would have caught it.
**Overlap:** AUD-12o-1 is the same arithmetic at the media download's call
site (a thumbnail sealed at 64 KiB against a cap built from 1 MiB); this is
the same root cause reached through the transfer path, where it affects every
default-configuration transfer rather than one thumbnail. Both belong in B9.

### AUD-12r-2 A receive interrupted by a process kill (or an error the engine does not classify) is never resumed and has no button that can move it

**Severity:** P3  **Confidence:** confirmed
**Where:**
[device_transfer.dart:345-346](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L345-L346)
and
[:381](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L381)
(the phases are persisted before the work),
[:430-497](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L430-L497)
(the only places that leave them),
[backup_service.dart:349-366](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/backup_service.dart#L349-L366)
(what is resumed),
[transfer_rows.dart:66-86](file:///J:/Projects/helix/helix_remote/app/lib/features/backup/application/transfer_rows.dart#L66-L86)
(the buttons).
**What:** `accept` writes `downloading` before the first byte and `importing`
before the first frame, and the only code that moves an offer out of those
phases is the in-process `catch` (`waiting`, `failed`, `cancelled`). Nothing
on start-up resets them, and `_resumeOffers` only touches
`phase == waiting` (`backup_service.dart:353-358`). The row for
`downloading` or `importing` offers exactly one button, **Pause**
(transfer_rows.dart:75-78), and `pause` is a no-op when the process has no
live run for the id (`_receiving[transferId] == null`,
device_transfer.dart:622-627). The same dead end is reached by any error
`BackupException.translate` does not map: in the catch, `code == null` runs
none of the branches (455-491), so the offer is left exactly where it was.
`ResponseTooLargeException` (AUD-12r-1) and `MalformedResponseException` are
both such errors today.
**Trigger:** Android kills the app while it is receiving or importing a
history (the import of a large history is many seconds of transactions), or a
receive hits an error the classifier does not know.
**Evidence:** the persisted phases at 346/381 have no counterpart outside the
catch; `_resumeOffers` filters `waiting`; `transfer_rows` maps
`TransferStage.downloading`/`importing` to a lone Pause; `pause` returns
silently without a token. `cleanUp` then removes the offer at `offerTtl`
(seven days, device_transfer.dart:641-651) with its chunks, so the only
recovery is the old phone sending the history again — after its own relay
objects are deleted at 48 h.
**Impact:** A killed restore leaves a row that looks alive ("Receiving (k of
N)") but can never advance, and cannot be declined, dismissed or restarted
from the new phone. The person is stuck for a week, then the offer vanishes.
**Fix sketch:** Treat `downloading`/`importing` as resumable states, not as
liveness: in `BackupService.start()` (or the first `runMaintenance`), any
incoming offer in one of those phases with no entry in `_receiving` goes back
to `waiting`, keeping `imported` and the chunks; `translate` gains the
transport's other exceptions (`ResponseTooLargeException` → `tooLarge`,
`MalformedResponseException`/`RangeNotHonoredException` → `corrupt`); and the
`code == null` path in `_accept` records `failed` with the error's type name
so the row offers Resume instead of nothing.
**Test that proves it:** A second `BackupService` over the same database (a
simulated restart) finds the offer in `waiting` and `acceptOffer` finishes it;
a relay that throws `ResponseTooLargeException` leaves the offer `failed`
with a failure named, not `downloading`.
**Overlap:** None. AUD-12p-3 and AUD-12p-4 concern a paused/waiting offer;
this is the two phases that have no live run behind them.

### AUD-12r-3 The sending side of a transfer lives only in memory and never learns the receiver's answer

**Severity:** P3  **Confidence:** confirmed
**Where:**
[backup_providers.dart:286-347](file:///J:/Projects/helix/helix_remote/app/lib/features/backup/application/backup_providers.dart#L286-L347)
(the sending rows),
[backup_service.dart:244-284](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/backup_service.dart#L244-L284)
(no outgoing stream),
[state.dart:411-421](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/state.dart#L411-L421)
(where the answer goes),
[device_transfer.dart:416-422](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/device_transfer.dart#L416-L422)
(the receiver's `done`).
**What:** The receiver's `done`/`declined` answer arrives at the sender's
`TransferInbox` and is written to the outgoing ledger's `answered`
(state.dart:412-421), where it is read by exactly one thing: `cleanUp`'s
`allAnswered` (device_transfer.dart:637). `BackupService` exposes offers only
for the *incoming* ledger (`watchOffers`, 252-268); sending progress is a
broadcast stream that "does not replay it" (backup_providers.dart:286-288),
and the app's `TransfersController` builds its sending rows from those live
events alone (331-347). So the sender's row stops at "Sent. Your other device
chooses whether to add it" (transfer_rows.dart:94-97) whatever the other
phone did; `TransferStage.declined`'s "Your other device declined it."
(transfer_rows.dart:102) is unreachable for a sending row. After an app
restart there is no sending row at all, and its id is not kept anywhere the
UI can reach, so an outstanding offer cannot be cancelled and its relay
objects stay until `relayTtl` (48 h).
**Trigger:** Send history to a new phone, then finish or decline it on the new
phone; or simply close and reopen the app while the offer is outstanding.
**Evidence:** `recordAnswer` writes only the ledger; `watchOffers` reads only
`watchIncoming`; the controller subscribes only to `transferProgress`; the
receiving answer body is sent (device_transfer.dart:416-422) and `decline`
sends its mirror (604-610), but nothing in the app renders `answered`. The
answer has only three states (`done`, `declined`, `cancelled`), so a receive
that *failed* is reported to the sender as `declined` (455-481) — the one
case where "send it again" is the fix (AUD-12p-1's `expired`) is the case the
sender is told was a refusal.
**Impact:** The person who sent the history cannot tell whether it arrived;
"Done" is never shown on the old phone, and an abandoned offer keeps its
relay objects for 48 h with no way to withdraw it. When the transfer fails,
the old phone would say "Your other device declined it" if anything were
shown at all.
**Fix sketch:** Give the outgoing ledger the same live view the incoming one
has (`watchOutgoing`, mapping each entry to a `TransferView` with its
answered set), seed the app's transfers list from it and overlay progress;
add a `failed` answer state (or carry the failure name) so a failed receive is
not reported as a decline; keep the last few finished sends in the ledger a
day so a restart still shows them.
**Test that proves it:** A sending row shows "Done" after the other device
imports and "Declined" after it declines (engine: `offers()`/a new
`outgoing()` stream reflects `answered`; app: the transfers page shows it
after a simulated restart); a tampered segment makes the sender say the
history could not be received, not that it was declined.
**Overlap:** AUD-12p-4 is the receiving rows reading the wrong stream; this is
the sending rows having no stream at all. Both are B13.

### AUD-12r-4 The twenty-first unanswered offer is dropped in silence

**Severity:** P3  **Confidence:** confirmed
**Where:**
[state.dart:322-342](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/state.dart#L322-L342)
(`maxOffers`),
[inbox.dart:30-42](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/inbox.dart#L30-L42)
(where the refusal is swallowed).
**What:** `recordOffer` refuses a new offer when the incoming ledger already
holds `maxOffers` (20) entries, returning `false` — the same value it returns
for a duplicate, which `TransferInbox.apply` passes back as "ignored". The cap
counts every entry, including `done`/`failed` ones that `cleanUp` keeps for
one or two days (device_transfer.dart:641-651). Nothing tells the receiver's
UI, and nothing tells the sender, whose entry stays `offered` with
"Your other device chooses whether to add it" until its relay objects are
deleted at 48 h.
**Trigger:** Twenty unanswered or failed transfers inside the cleanup window —
a person retrying "Send history" while the new phone keeps failing (which,
per AUD-12r-1, it does). The twenty-first, the one that would have worked, is
the one dropped.
**Evidence:** `offers.length >= maxOffers` returns `false` (331-333);
`apply` returns that boolean unchanged (37-42) and the applier's only action
on it is to stop; no progress event, ledger note or log line is written;
`watchOffers` simply never lists the transfer. `maxOffers` is 20
(state.dart:285).
**Impact:** A restore offer can vanish with no trace on either device. The
sender cannot distinguish "not delivered yet" from "discarded"; the receiver
cannot see that anything was offered.
**Fix sketch:** Distinguish duplicate from full (return an enum), evict the
oldest finished entry before refusing, and when a genuinely fresh offer must
be refused, record that in the ledger (an error on the sending entry, or a
one-off note the offers list can show) so both ends can say "the other device
could not take the offer".
**Test that proves it:** With 20 entries in the incoming ledger, a 21st offer
is either recorded (oldest finished entry evicted) or refused with a visible
reason on both sides; a duplicate still changes nothing.
**Overlap:** AUD-12p-2 swallows a failed *send*; this swallows a refused
*receive*.

## Verified safe (read, not findings)

- `inbox.apply`'s gate: a stranger's offer is refused by the account check, a
  device's own offer by the device check, an addressed offer by the audience
  check, and a withdrawal is honoured only from the device that made the
  offer (inbox.dart:24-28, 46-54).
- Manifest bounds: version, transfer id, account id, an empty or oversized
  segment list, and per-segment size are all checked before anything else is
  fetched (device_transfer.dart:529-546).
- Every object is digest-checked and size-checked, and decryption failures
  become `corrupt` rather than escaping (556-591); the tests tamper with a
  segment and the manifest and get `corrupt` (transfer_test.dart:218-260).
- Chunks are gap-checked (`missingSequences`, `isComplete`) before an import
  starts, and a gap aborts before the importer is opened (device_transfer
  360-379; transfers_dao.dart:405-430).
- Resumption is idempotent: the ledger's `imported` pointer plus the
  importer's merge-only application means a segment re-applied after a crash
  changes nothing, and re-applying frames is safe (snapshot.dart's importer).
- One run per offer: `_accepting` shares and clears the future; `_receiving`
  holds the token `pause` cancels; `_paused` is cleared in `finally` even
  when the accept fails (313-317, 494-497).
- A terminal failure drops the chunks and answers the sender, so a failed
  transfer leaves no relay objects or rows behind (455-481; `removeIncoming`
  drops chunks in the same transaction, state.dart:359-366).
- `errors.dart` names every failure the engine can see in terms the app can
  act on, and `detail` carries no content, keys or codes (8-108).
- `senderOrder` is deterministic: oldest `linkedAt` first, device id as the
  tie-break (654-666).
- `cleanUp` ages out terminal offers by phase (1 day / 2 days) and everything
  else by `offerTtl`, removing the chunks with the entry (633-652).

## Coverage notes

- `AttachmentCrypto.ciphertextLength` is called at four sites with three
  choices of chunk size: `download_runner.dart:141-144` and `:271-274` and
  `device_transfer.dart:565-568` use `maxChunkSize`; `people_service.dart:325`
  uses the default. Only the last happens to match how its object was sealed.
- The transfer's export has no byte budget (`_exporter.export` is called
  without `maxBytes`, device_transfer.dart:153-158), unlike the history
  backup's 16 MiB. That is a design choice; the receiver's only bound is
  `maxSegments × maxSegmentBytes` (4096 × 64 MiB), and the per-chunk insert
  has no total-size check.
- `RestoreResult.version` is always 0 for a transfer (device_transfer 327,
  424-429); the app reads only `added` (the same shape as AUD-12q-2).
- `RestoreResult.invalid` (bad records skipped by the importer) is reported
  and never shown.
- A crash between `addChunk` and the `imported` update is safe: the ledger
  pointer only decides where the *import* starts, and a chunk is discovered
  from the table, not the ledger.
- `waitingForWifi` is produced by the app's `PolicyBackupRemote`
  (app/lib/core/engine/backup_policy.dart:28), not the engine — the failure
  enum is not dead.
- `transfer_test.dart`'s `FakeRelay` ignoring `maxBytes`, and every test
  pinning tiny segments, is the reason AUD-12r-1 is invisible to the suite;
  fixing the fake is part of the finding's test.

## Structural proposals

### S12r-1 One way to say how long a sealed object may be

**Current shape:** Four call sites guess a ciphertext's maximum length from a
*plaintext* size and a chunk size: three pass `AttachmentCrypto.maxChunkSize`
(the largest legal, which produces the shortest ciphertext) and one passes the
default — while the objects are sealed by three different writers that do not
all use the same chunk size (`_put` uses the default; the media upload runner
uses `_config.encryptionChunkBytes`; `people_service`'s photo uses the
default). Nothing ties a pointer to the chunk size its object was sealed
with, so every reader is guessing, and the only correct guess is correct by
coincidence.
**Why it matters:** One wrong guess is AUD-12o-1 and another is AUD-12r-1;
the next writer that changes its chunk size breaks the reader silently.
**Shape:** Let the producer record the chunk size (a `MediaPointer` field, or
a reader that takes the object's header into account), and offer one
`AttachmentCrypto.maxCiphertextLength(pointer)` used by every reader — so
the bound is a property of the object, not of the caller. Until the wire
changes, a single helper that always computes with `defaultChunkSize` and
adds the tag slack removes the whole class.
**Test:** A property test over sizes 0, 64 KiB ± 1, 1 MiB, `segmentBytes`:
the computed cap is ≥ the real ciphertext for every object the writers
produce, and the relay's cap is never the reason a download fails.

### S12r-2 A transfer is one ledger-backed row with two directions, not two streams and an in-memory map

**Current shape:** An incoming offer is durable and streamed (`watchIncoming`
→ `watchOffers` → the app's offers list), but its progress is a separate
event stream that reports zero while downloading (AUD-12p-4) and is lost on
restart (AUD-12r-2). A sending transfer is the mirror image: durable in the
ledger (`outgoing`, with `answered`) but streamed only as events that are not
replayed, and never rendered from the ledger at all (AUD-12r-3). The phase
enum mixes sender and receiver phases, and the terminal states have no room
for "the other side could not take it".
**Why it matters:** Three of this sweep's four findings and two of 12p's are
consequences of the same split: a row that is real in one place and an event
in another, with the UI reading whichever half it happens to have.
**Shape:** One `TransferView` per ledger entry, built by the engine from
`incoming` and `outgoing` (phase, progress, answer, failure), streamed by one
`watchTransfers()`, and taken by both pages; progress events only update the
row they belong to. Add the terminal states the flow actually has
(`failed`/`expired` as an answer, not a decline) at the same time.
**Test:** Every state a row can be in is reachable from a fresh process
holding the same database, and both sides of a transfer show the same
terminal answer.
