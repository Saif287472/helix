# Sweep 12q — `helix_remote_engine`: the backup archive (export, import, envelopes)

**Scope.** `snapshot.dart` (894), `full_backup.dart` (344), `history_backup.dart`
(333) and `archive.dart` (247) read line by line, with the cross-reads that
settle the findings: `HistoryStore` (export pages, `mergeConversation`,
`fillSelfProfile`), `messages_dao`'s `insertMessage`/`markReadUpTo`/
`editMessage`/`deleteForEveryone`/`removeMessages`, `chats_service`'s
`deleteForMe`/`clearChat`/`deleteChat`, the DB's `removeExpired`, the app's
`recovery_backup_page.dart`, `backup_providers.dart` 490-600 and
`backup_gateway.dart` 200-241, and the server client test that restores a full
backup after a takeover (`backup_test.dart:495-561`). ~1,900 lines.

**Verdict.** This is the most careful code in the backup feature: the writer
bounds every frame, every record and every inflated frame; the reader treats
damage as corruption rather than input to repair; the importer is
transaction-per-frame and merge-only; and the full envelope binds its id and
version into the AEAD. Three things fall outside that care: the archive has no
memory of what this device *deleted*, it does not say when it was trimmed, and
the full-backup identity check runs after the merge it is meant to guard.

## Findings

### AUD-12q-1 A restore — and the automatic catch-up inside a backup — brings back what this device deleted

**Severity** P2 · **Confidence** confirmed

**Where** [snapshot.dart:179-215](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/snapshot.dart#L179-L215),
[snapshot.dart:687-730](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/snapshot.dart#L687-L730),
[history_backup.dart:174-179](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/history_backup.dart#L174-L179),
[history_backup.dart:198-219](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/history_backup.dart#L198-L219),
[messages_dao.dart:163-181](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/daos/messages_dao.dart#L163-L181)

**What** "Delete for me", "clear chat" and "delete chat" remove rows from this
device's database and leave no trace of the removal. A backup from *another*
device of the account still contains them (that device never deleted them).
The importer treats every absent message as new and inserts it, so any merge
puts them back: a version-conflict catch-up during an ordinary automatic
backup, or the restore button. For an incoming message the re-insertion also
sets `unread + 1` (`insertMessage`), so a conversation the user cleared comes
back with an unread badge.

**Trigger** Two devices, daily auto-backup on. Delete a message (or clear a
chat) on A; B's next backup lands first; A's next backup gets
`version_conflict` → `_catchUp` merges B's backup → the message (or the whole
chat) is back on A, and A's following upload makes it permanent again. A manual
restore on the same device does the same.

**Evidence** Local deletion is a row delete with no tombstone
([messages_dao.dart:163-181](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/daos/messages_dao.dart#L163-L181);
`chats_service.dart:449-451` delete for me, `:556-560` clear chat, `:562-564`
delete chat). The export filter has no notion of "removed here"
([snapshot.dart:79-88](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/snapshot.dart#L79-L88)),
and the exporter pages every row that exists
([179-215](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/snapshot.dart#L179-L215)).
The importer's only existing-row test is `find(id, sender: from)`; a missing
row is inserted with the archive's content
([687-730](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/snapshot.dart#L687-L730)).
The conflict path merges before it retries the upload
([174-179](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/history_backup.dart#L174-L179),
[198-219](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/history_backup.dart#L198-L219)).
(Expired messages do not come back: the importer skips a past `exp_at`,
[snapshot.dart:677-678](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/snapshot.dart#L677-L678)).
The tests do not exercise deletion plus a merge.

**Impact** A deliberate local privacy action is silently undone, most often
without the user asking for a restore at all (the catch-up runs inside the
nightly backup). The deleted chat reappears in the chat list, and the deleted
message reappears unread — exactly the signal that makes a user think the app
ignored them. On a *fresh* device this is the intended behaviour (recover
everything); the defect is that the device that deleted cannot say so.

**Fix sketch** Keep a local-only tombstone for removals and consult it on
import: one small table of `(messageId, author)` plus deleted conversation ids,
written by `deleteForMe`/`clearChat`/`deleteChat`, never exported (it is this
device's choice, not the account's), pruned by the same maintenance that ages
out anything else. The importer skips a `msg` whose id is tombstoned and a
`conv` whose id was deleted; `_ensureChat` must not recreate a tombstoned chat
from a message record. Schema 5 with a step migration and codegen.

**Test that proves it** Engine test with two devices and a shared backup: A
and B hold a message; B's backup reaches version 2; A deletes the message for
me; A's `backUpNow()` hits the conflict, catches up and uploads — the message
is absent from A's database afterwards and absent from A's new backup. A
`clearChat` variant leaves the chat empty and out of the chat list.

**Overlap** None in the plan. AUD-12m-1 (freed media) is the opposite direction
of the same "the local copy is not the account's copy" question.

### AUD-12q-2 A trimmed history looks complete to the device that restores it

**Severity** P3 · **Confidence** confirmed

**Where** [snapshot.dart:123-136](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/snapshot.dart#L123-L136),
[models.dart:46-67](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/models.dart#L46-L67),
[models.dart:159-173](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/models.dart#L159-L173)

**What** When the history backup hits its 16 MiB budget the exporter stops at
the frame that would pass it and sets `ExportStats.truncated`, which reaches
`BackupResult`, `BackupProgress` and `BackupStatus` — all on the device that
*wrote* the backup. The archive itself carries no such mark (the header is
written before the message loop), so a second device that restores it reports
"Restored N messages" with no way to know that every message older than a
cut-off is missing, and no way to tell the user.

**Trigger** Any history over the server's limit, restored on a new device (the
main reason the automatic backup exists).

**Evidence** The cut happens in `admit` and only sets the local stats flag
([123-136](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/snapshot.dart#L123-L136));
`BackupResult.truncated`/`BackupStatus.truncated` exist
([models.dart:67](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/models.dart#L67),
[95](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/models.dart#L95))
but `RestoreResult` has only version, added, existing and invalid
([159-173](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/models.dart#L159-L173)),
and `finish()` checks only that a header was seen
([snapshot.dart:462-466](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/snapshot.dart#L462-L466)).
The app's restore copy reads `RestoreOutcome.added` alone
(`backup_gateway.dart:204-207`).

**Impact** A user who restores on a new phone believes they have their history
and the sending device really kept the rest; nothing will ever prompt them to
copy the older half from the device that still has it. This is the class of
silence the audit treats as data loss, without the loss being new.

**Fix sketch** Write a trailing record before `finish()`
(`{'t': 'end', 'truncated': true}`) — unknown record types are already skipped
by older readers, so no format-version bump is needed — and have
`ImportSession` capture it into `RestoreResult` and `RestoreProgress`. The
app's restore result then says "the oldest messages were not in this backup".
(The catch-up path can ignore it: it only merges.)

**Test that proves it** Engine test with `maxHistoryBytes` small enough to cut
the archive: the exporting device's state says truncated **and** a second
device's `restoreHistory()` result reports the same flag; an archive with
everything carries no flag.

**Overlap** Q3 (the owner's question about exports being honest about their
bounds) is the same principle on the server's export; this one is client-side
and needs no decision, only a field.

### AUD-12q-3 The full-backup identity check runs after the merge it guards

**Severity** P3 · **Confidence** confirmed

**Where** [full_backup.dart:238-279](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/full_backup.dart#L238-L279),
[backup_gateway.dart:227-241](file:///J:/Projects/helix/helix_remote/app/lib/features/backup/application/backup_gateway.dart#L227-L241),
[backup_test.dart:526-536](file:///J:/Projects/helix/helix_remote/server/test/client/engine/backup_test.dart#L526-L536)

**What** `restoreFullBackup` merges the whole archive and *then* returns
`identityMatches`, which is false when the archive was sealed by this
account's identity before a key change (a takeover or a recovery). The app's
restore page treats false as a hard error (`accountMismatch`) — after the merge
already happened. So the user is told "This backup cannot be opened with your
account" while the old history has in fact been added, and every retry repeats
the merge and the error. The guard adds nothing a header check does not
already provide (`_checkHeader` requires the archive's account id to equal
this one), so its only effect is to make a successful restore look failed.

**Trigger** After a phone takeover or an account recovery, open Settings >
Backup > "Restore from a recovery secret" on the new device with the secret of
a full backup made before the key change.

**Evidence** `restore` merges first (the frame loop at
[238-253](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/full_backup.dart#L238-L253))
and computes `identityMatches` from the merged session
([258-279](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/full_backup.dart#L258-L279));
the gateway throws on that flag
([227-241](file:///J:/Projects/helix/helix_remote/app/lib/features/backup/application/backup_gateway.dart#L227-L241)).
The server test pins the merge side: after a takeover,
`restoreFullBackup` returns `added: 1`, `identityMatches: false`, and the
message is found by search ([526-536](file:///J:/Projects/helix/helix_remote/server/test/client/engine/backup_test.dart#L526-L536)).

**Impact** A confusing failure at the moment a user is recovering from losing
a phone: the history is there, the app says it is not, and the error invites
the user to do the one thing that cannot work (try again). It also means the
restore page's copy is untrue about what happened.

**Fix sketch** Decide the identity question before importing. The `secrets`
record is the first record of the first frame; the engine can parse the header
and the secrets record, expose them (a `probe` half, or `restoreFullBackup`
returning the secrets through the progress), and only merge after the caller
accepts. The cheaper app fix is to stop throwing: show "your history was
restored; this backup was made under an earlier identity key" and ignore the
secrets (they are for the account flow, which the signed-in device does not
need).

**Test that proves it** Takeover test as today, plus: a store that makes
`putHistory`/the frame loop observable — with the app's current rule the merge
must not run when the identity differs; after the fix, either the error comes
before any message is added or the restore result reports success with a
"made under an earlier key" flag.

**Overlap** AUD-15-5 says the take-over flow deliberately does not offer the
restore step, and its evidence calls a pre-takeover backup unopenable — true
for the AIK-keyed *history* backup, not for the full one (this test). Keep
15-5's conclusion; this finding is about the guard firing too late when the
page is reached some other way.

## Verified safe

- **The archive's bounds are real.** Frame lengths are checked against 8 MiB
  stored and 32 MiB inflated; a gzip bomb is stopped in a capped sink while it
  inflates; a record over 1 MiB is refused by the reader and never written by
  the writer; unknown codecs fail as `newerFormat`, unknown record types are
  skipped.
- **The full envelope is bound to its server metadata.** `_parse` checks the
  envelope's `backup_id` and `version` against the server's row and that the
  id is a UUID, so the server cannot replay an older envelope under a newer
  version; `BackupCrypto.open` then authenticates the same values.
- **The recovery secret cannot leak into the shipped envelope.** The envelope
  is scanned for `FullBackup.forbiddenFields` at any depth and for the
  secret's text before the request leaves; the archive itself is ciphertext at
  that point.
- **The import is merge-only and per-frame atomic.** An existing message is
  never overwritten: a delete-for-everyone, a *newer* edit, a reaction or
  receipt this device lacks, a later status and a later read position are the
  only things taken from the archive; each frame commits with its summaries
  recomputed, so an interrupted import resumes.
- **Read state cannot move backwards.** `mergeConversation` only advances
  `lastReadSortKey` and `markReadUpTo` only marks messages at or below the
  archive's key.
- **A full backup carries no session or key state beyond the identity
  secrets.** Sessions, prekeys, sender keys, device keys and tokens are not
  in the snapshot; the profile key rides only in `full`/`transfer`, and a
  history archive that claims one is not believed.
- **Export content is exactly the count it reports.** `backupableCount` and
  `included` apply the same rule in one place (view-once, undecryptable,
  pending/failed, expired), and `messages` counts the frames the writer
  actually sealed.
- **Attachment order survives.** The importer sorts an album by `pos` and
  `insertMessage` assigns positions by list index, so a multi-attachment
  message is restored in order.
- **The history backup's version discipline is sound.** A device that knows
  less never overwrites more: a conflict merges the newer backup and uploads
  on top, a rolled-back server version is refused on restore, and a
  newer-format or other-account backup is not overwritten.
- **A 413 halves the budget and retries.** The whole blob is sealed once per
  attempt, never streamed partially, and the retry re-exports under the
  smaller budget.

## Coverage notes

- `SnapshotImporter.importBytes` has no product caller (tests only); the
  product paths stream frames through `addFrame`.
- A record that fails halfway (say a message inserted and then a malformed
  reaction) commits the half that ran, because the per-record catch sits
  inside the frame's transaction. Only a corrupt or hand-made archive can do
  this (the writer validates what it writes), and the counter reports the
  record as invalid; noted, not written up.
- The head of an archive (self, settings, people, every conversation) is
  mandatory and unbounded — a device with tens of thousands of chats could
  exceed the 16 MiB budget with conversations alone and fail every backup as
  `tooLarge` rather than trimming. Only the local `BackupFailure.tooLarge`
  says so. Not plausible at the product's scale; noted.
- `FullBackupJob.create` has no run-dedupe (the history job has
  `_backingUp`), but the app guards the button with `state.busy`
  (`backup_providers.dart:576-577`), so two runs need a non-app host.
- The full backup's `secrets` record carries the identity key seed and public
  key; neither is length-checked on import. The account flow using them
  validates or fails later; not a trust boundary (the envelope is AEAD-bound).
- `deleteRemote` for both backup kinds resets the local state only after the
  server call succeeds, which is the right side to fail on.
