# Sweep 12i — engine: `chats_service.dart`

Read line-by-line: `features/chats_service.dart` (714), plus the cross-reads
that decide the findings: `messaging/outbox.dart` (classify/`_failed`/
`_giveUp`/`_succeeded`, 174-477), `messages_dao.dart` (`markReadUpTo` 198-224,
`removeMessages` 165-181, `clearConversation` 736-742, paging 637-708),
`conversations_dao.dart:198-220`, the `messages` table's cascades
(`tables/messages.dart:12-60`), `opening.dart:150-163` (`foreign_keys = ON`),
the app's `message_actions.dart` (1-200), `conversation_screen.dart:529-532`,
`chat_gateway.dart`, `group_actions.dart:88-92`, `group_info_screen.dart:167-171`,
`orbit_ui`'s group info row (1005-1030), the server's group disappearing test
(`groups_test.dart:718-735`), `apply.dart`'s receipt and timer handlers
(196-201, 441-471, 598-700), and drift 2.34's nested-transaction support
(`connection_user.dart:460-501`). ~1,500 lines.

Verdict: the optimistic-write design is implemented correctly — every action's
local change and its outbox op commit in one transaction, ids and receipt
chunks are bounded, and cascades are real. The defect is on the other side of
the commit: once a *post-commit* action send fails for good, nothing links the
failure back to the message, nothing shows it, and "delete for everyone" cannot
be repeated. The deletion paths that run before a send also do not stop it.

---

### AUD-12i-1 A failed edit/delete/reaction is lost silently; "delete for everyone" is then unrepeatable

**Severity** P2  **Confidence** confirmed

**Where**
- [`features/chats_service.dart:685-699`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/chats_service.dart#L685) — `_sendAction` enqueues the action with **no** `messageRowid`, although it has `target` in hand.
- [`features/chats_service.dart:427-447`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/chats_service.dart#L427) — `deleteForEveryone` sets `deletedAt` locally (440) and enqueues (441-446); the same method refuses a second call once `target.deletedAt != null` (435-439).
- [`features/chats_service.dart:399-424`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/chats_service.dart#L399) — `edit` writes the new text locally (416) before enqueueing (418-423); also `react` (301-332), `vote` (336-356), `rsvp` (359-377).
- [`messaging/outbox.dart:203-239`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/outbox.dart#L203) — `classifyOpError` gives up on every `CryptoV2Exception` (223-224), every `GroupException` (217-222) and every non-retryable `ApiException` (235).
- [`messaging/outbox.dart:447-452`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/outbox.dart#L447) — a retryable failure is also given up after `outboxMaxAge` as `expired`.
- [`messaging/outbox.dart:468-477`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/outbox.dart#L468) — `_giveUp` marks the op failed and emits `SendFailedEvent(messageRowid: null)`; no app code listens for `SendFailedEvent` (grep over `app/lib`).
- [`features/chats_service.dart:535-540`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/chats_service.dart#L535) — `retrySend` only reaches ops by `outboxDao.forMessage(rowid)`, and action ops carry no row.

**What** An action op that reaches a terminal failure is dropped. For a message
send the result is visible (the row goes `failed` and the chat offers retry,
[`outbox.dart:472-474`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/outbox.dart#L472)); for an action there is no row to mark, no event consumer and no retry entry point. The local state has already moved
on: the text is edited, the reaction is set, the message is `deletedAt`. For
edits, reactions, votes and RSVPs the user can repeat the gesture (the second
send is a fresh op); for **delete for everyone** the local row now fails the
`deletedAt != null` guard, so no later call can ever re-send it.

**Trigger** Any terminal failure at send time: a `CryptoV2Exception` or
`GroupException` from the group sender key (a rekey race, a sender key not yet
shared on a new device), the group's `sendMessages` flipping to admins-only
between enqueue and send (`not_allowed`), removal from the group, or 30 days
offline. The action is enqueued immediately and the failure surfaces later,
with the chat already showing the result.

**Evidence** The classifier is reason-blind for groups and crypto (outbox.dart:
217-224), so conditions that are transient in practice become `GiveUp`; a
message op stays recoverable because `_giveUp` writes `MessageStatus.failed`
onto its row, while an action op is enqueued without one
(chats_service.dart:690-698) and `retrySend` looks the op up by row
(chats_service.dart:537). The outbox has no UI surface of its own: the only
listener-side consumer of failures is the per-message status, and the app never
subscribes to `SendFailedEvent`.

**Impact** "Delete for everyone" silently fails: the sender (and, for an admin
delete, the admin) sees the message gone, every other device keeps it, and
there is no way to retry — the action is now impossible to express from the
UI. The same silent loss applies to an edit that never reached the peer, which
then shows different text per device with no failure indicator. This is the
sending half of AUD-12f-1 (the receiving half) and the action variant of
AUD-12b-1 (a lost rekey op).

**Fix sketch** Enqueue actions with the target row in a *separate*
`targetRowid` field (not `messageRowid`, whose presence advances a message's
status in `_succeeded`/`_giveUp`). On give-up, leave a failed-op record the
conversation can read (`outbox` already stores `conversation_id`), render it as
a system row ("Couldn't delete for everyone · Retry") and route retry through
`OutboxService.retry(opId)`. Classify `GroupException(versionConflict /
noGroupKey)` and `CryptoV2Exception` as `RetryLater` (the same change 12b
proposes), so only genuinely terminal codes reach the user.

**Test that proves it** Engine test: create a group message, remove this
device's ability to send (make `sendContent` throw `GroupException(noGroupKey)`
once), call `deleteForEveryone`, drain the outbox; assert the op is `pending`
with a next attempt, then let the send succeed and assert the peer applied the
delete. A second test: force `GiveUp('not_allowed')` and assert the chat
exposes a failed action the user can retry (today: nothing exists to assert).

**Overlap** AUD-12f-1 (the same action types dropped on receipt), AUD-12b-1
(rekey ops with no retry path), structural proposal S1 below.

---

### AUD-12i-2 "Delete for me" on a pending message does not cancel it — and is the only deletion offered

**Severity** P3  **Confidence** confirmed

**Where**
- [`features/chats_service.dart:450-451`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/chats_service.dart#L450) — `deleteForMe` only calls `messagesDao.removeMessages`.
- [`messages_dao.dart:165-181`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/daos/messages_dao.dart#L165) — `removeMessages` deletes rows and refreshes the summary; it never touches `outbox`.
- [`messaging/outbox.dart:426-432`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/outbox.dart#L426) — `_succeeded` tolerates a vanished message row, so the op sends anyway.
- [`features/chats_service.dart:557-560`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/chats_service.dart#L557) — `clearChat` has the same shape (`clearConversation`, `messages_dao.dart:736-742`).
- [`app/.../message_actions.dart:55-90`](file:///J:/Projects/helix/helix_remote/app/lib/features/conversation/application/message_actions.dart#L55) — "delete for everyone" is offered only when the message is `sent` (or delivered/read), so on a **pending** message the menu offers only "delete for me".

**What** A message written while offline (or held behind a slow rekey) is
queued in the outbox at send time. Removing it with "delete for me" deletes the
row but leaves the op, which sends as soon as the network returns. The user's
only removal action on an unsent message is therefore also the action that
delivers it invisibly — and because the row is gone, no later
`deleteForEveryone` call can recall it.

**Trigger** Compose while offline (or while the group's send is blocked), open
the message menu, "Delete for me"; reconnect. Same with "Clear chat" on a chat
that has pending messages.

**Evidence** The op is created in the same transaction as the row
(chats_service.dart:290-295) and `removeMessages` deletes only rows
(messages_dao.dart:174-176); the worker's success path explicitly tolerates a
missing row (`byRowid(rowid) != null`, outbox.dart:429), so nothing stops the
send. The app's menu gate (message_actions.dart:86-90) means a pending message
has no other removal path: "delete for everyone" is hidden until it is sent.

**Impact** Content the user removed from their device is delivered after all,
with no trace on the sender to retry or recall. No data loss for the recipient;
a privacy/expectation failure for the sender.

**Fix sketch** In `removeMessages`/`clearConversation`, cancel the pending
outbox ops for those rows in the same transaction
(`DELETE FROM outbox WHERE message_rowid IN (…) AND state IN ('pending',
'failed')`) and drop their queued transfers; or offer an explicit "cancel send"
that reuses "delete for me" for pending rows. Cancelling a claimed in-flight op
should be best-effort (its send may already be on the wire).

**Test that proves it** Engine test: with the transport offline, send a text,
`deleteForMe` its row, bring the transport up, drain; assert the peer received
nothing and the outbox holds no op for the row.

**Overlap** AUD-12i-1 (the action-side failure path of the same op), media
transfer interactions deferred to 12l.

---

## Structural proposals (2 of max 3)

**S1 — Action ops should carry their target separately and surface failures in
the chat.**
*Current shape.* `_sendAction` enqueues with `conversationId` only
(chats_service.dart:685-699); failure handling keys off `messageRowid`, which
actions do not set, so their failures vanish (AUD-12i-1).
*Hazard.* Every new action type inherits a silent-loss path; the same shape
already bit rekeys (12b) and inbound actions (12f).
*Proposed shape.* Add a `targetRowid` to the op payload, keep `messageRowid`
meaning "this op delivers this message", and let the conversation read failed
ops by `conversation_id` and show a retry row. `_giveUp`/`_succeeded` only
advance message status for ops that have `messageRowid`.
*Migration.* Additive: new payload field, new read query, no schema change to
`messages`; the app renders the new rows behind the existing conversation
watch. Expand (write the field), migrate (render + retry), contract (none
needed).
*Risk.* A retried delete must be idempotent on peers — it already is
(`_delete` applies once, apply.dart:457-463).
*Size.* ~60 lines engine + ~80 app + tests.

**S2 — One authority for "what can be done to this message".**
*Current shape.* The app reconstructs the engine's rules
(message_actions.dart:73-90: edit window, delete window, `sent` state, group
admin) and the engine re-checks them (chats_service.dart:399-447). They already
differ: the app requires a sent state for edit and delete-for-everyone, the
engine does not.
*Hazard.* Two rule sets drift; the menu can hide something that would work, or
offer something that throws a `StateError` with prose as its message.
*Proposed shape.* `ChatsService.actionAvailability(rowid) → Set<MessageAction>`,
computed from the row plus the group role; the app renders the returned set and
the write methods keep their checks as the backstop.
*Migration.* Additive method; the app swaps its local computation for the
engine's; delete the duplicated predicates.
*Risk.* The availability query must stay cheap (one row + one group lookup),
cached per menu opening.
*Size.* ~120 lines (engine method, app wiring, tests).

## Verified safe (checked, no finding)

- **Optimistic write and enqueue in one transaction.** Every action method runs
  as one `_db.transaction`: `react` (301), `vote` (336), `rsvp` (359), `edit`
  (399), `deleteForEveryone` (427), `setDisappearing` (517), `markRead` (456),
  `openViewOnce` (489), `_sendVisible` (230). A failed enqueue rolls the local
  change back, so only *post-commit* failures can diverge (AUD-12i-1).
- **Nested transactions are supported.** Drift 2.0+ nests (savepoint-free
  nesting supported by the sqlite3 delegate,
  `connection_user.dart:460-501`), so `markRead`→`markReadUpTo` and
  `setDisappearing`→`_sendVisible` are correct.
- **Cascades.** `messages.conversation_id` cascades from `conversations`, and
  reactions/receipts/attachments cascade from `messages`
  (`tables/messages.dart:19-20, 66-70, 82-86, 100-104`); `PRAGMA
  foreign_keys = ON` at open (`opening.dart:163`), so `deleteChat` leaves no
  orphans.
- **Read receipts are bounded and correctly addressed.** `markReadUpTo` only
  returns `received` rows (messages_dao.dart:205-214), so a direct receipt never
  names this account's own messages; chunks are ≤500 ids
  (`ContentLimits.maxIdsPerReceipt = 500`, bodies.dart:14); a group's own-device
  receipts skip outgoing rows again on apply (`apply.dart:663-668`); per-author
  group receipts are skipped above 64 members by design
  (chats_service.dart:667, `group_ids.dart:30`).
- **View-once receipts.** A group view-once receipt goes pairwise to the author
  only (chats_service.dart:495-505); `_groupGate` admits receipts pairwise
  (apply.dart:195).
- **Admin delete is checked at both ends.** The engine asks the local roster
  (chats_service.dart:431-434) and the receiver re-checks the sender's role
  (apply.dart:457-463).
- **`openDirect` does not clobber a person.** `upsertPerson` uses
  `insertOnConflictUpdate`, which (drift 2.34) only updates the columns present
  on the companion — `account_id` and `updated_at` — so a stored name, block or
  photo survives (12g's drift check).
- **Outbox tolerates a cleared chat.** Success and failure both skip a
  vanished message row (outbox.dart:429, 472), so `clearChat`/`deleteChat`
  mid-flight cannot crash the worker (it still sends — AUD-12i-2).

## Coverage notes

- **Group timer vs roles.** `setDisappearing` has no role check
  (chats_service.dart:517), while every receiving device ignores a timer change
  from a non-admin (`apply.dart:196-201`). The app gates the row on
  `canAdminister` (`group_screens.dart:1010-1029`), and the server-side test
  asserts peers ignore a member's change (`groups_test.dart:731-734`). The only
  exposure is a stale admin (demoted while the sheet is open) or a programmatic
  caller: their own chat shows the timer, everyone else's stays off. Not filed
  as a finding; worth an engine-side role check next time this file changes.
- **`edit` accepts an empty string** (only the length cap is checked,
  chats_service.dart:409-415); the UI prevents it. Idea-level.
- **Mentions.** `_checkMentions` validates membership and offsets but not
  overlapping or duplicate ranges, and direct chats are not checked at all
  (chats_service.dart:175-194).
- **Replies.** A reply's `MessageRef` is not checked against the conversation or
  existence (chats_service.dart:252-260); the receiver resolves it per chat and
  shows nothing for a miss.
- **Quarantined messages are receipted.** A placeholder inserted by
  `_quarantine` has status `received`, so `markReadUpTo` includes it and the
  author gets a read tick for a message this device cannot display — consistent
  with the 12f quarantine family, not filed separately.
- **Pending media and delete-for-me.** Uploads for a queued media message whose
  row was deleted are the transfer queue's problem; deferred to 12l.
- **`setDisappearing` sends a system row even when the value is unchanged**
  (chats_service.dart:517-532); harmless noise.
- **Receipt fan-out cost.** One op per 500 read ids per audience, so a very
  large backlog (history import) enqueues tens to hundreds of non-urgent ops in
  one transaction; bounded, and the outbox processes them serially.
