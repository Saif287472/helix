# Sweep 12f — engine: group crypto (inbound, sender, sender-key store, pipeline)

Read line-by-line: `groups/group_inbound.dart` (598), `groups/group_sender.dart`
(287), `groups/sender_key_store.dart` (147), `groups/group_pipeline.dart` (77),
`groups/group_ops.dart` (76), `groups/group_notices.dart` (64). Re-read for the
open questions of 12e: `groups/group_rekey.dart` (167, the crash windows),
`groups/group_roster.dart:180-249, 400-442` (`_apply`'s state handling,
`reopenState`). Cross-reads: `messaging/inbound.dart:140-310, 360-400` (the
direct twin of quarantine and the typing branch), `messaging/apply.dart:360-382`
(receipts are sent non-urgent), `features/chats_service.dart:590-699`
(`_sendAction`: reactions, edits and deletes go out non-urgent),
`features/presence_service.dart:80-153` (typing is sent outside the outbox),
the crypto `GroupEncryption.controlMessages` and `crypto_dao` sender-key
queries already read in 12d. ~1,750 lines. Two structural proposals.

Verdict: the send path is disciplined — encrypt, commit under a CAS, then POST,
and every retry class makes monotonic progress — and the rekey crash windows
both recover. What is missing is a *policy* for content that cannot be read:
the quarantine rule decides "worth repairing" from the envelope's `urgent`
flag, so a reaction, an edit and above all a **delete** are silently dropped
when the sender key is out of step; and the group master key has three writers
whose tie-break lives inside the inbound path, so the first key to arrive can
win over the correct one.

---

### AUD-12f-1 A delete or edit that fails to decrypt is dropped silently, forever

**Severity** P2  **Confidence** confirmed (rule and both send paths are unconditional; the trigger is the `no_sender_key` / `auth_failed` case 13a exists for)

**Where**
- [`features/chats_service.dart:685-698`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/chats_service.dart#L685) — `_sendAction` queues every message action with `urgent: false` ("not worth waking the recipient's phone"); its callers are reactions ([`chats_service.dart:324`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/chats_service.dart#L324)), poll votes (349), RSVPs (369), **edit** ([`chats_service.dart:418-423`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/chats_service.dart#L418)) and **delete** ([`chats_service.dart:441-445`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/chats_service.dart#L441)).
- [`groups/group_inbound.dart:264-267`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_inbound.dart#L264) — `userMessage = envelope.urgent && envelope.seq != null`; `repair = resend && userMessage`; no placeholder and no `enqueueReset` when it is false.
- [`groups/group_inbound.dart:247-249`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_inbound.dart#L247) — `resend` is exactly the `NoSenderKeyException` / `DecryptionFailedException` pair, i.e. the recoverable cases.
- [`messaging/inbound.dart:376-394`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/inbound.dart#L376) — the direct twin of the same rule, with the comment "receipts, reactions, edits and other control content go out non-urgent, and there is nothing the sender could re-send for them".
- [`messaging/outbox.dart:363`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/outbox.dart#L363) — the group op passes `urgent` straight into `GroupMessageSender.send`, so a group action travels the same way.

**What** Delivery and readability are separate things. The outbox considers an
action sent when the server accepts the envelope (`POST .../messages`), and the
server stores it whether or not every member device can decrypt it. When a
member's sender-key state is out of step — the device reinstalled, a
distribution was lost, another engine moved the chain, the epoch changed —
`groupMessage` fails with `NoSenderKeyException` or `DecryptionFailedException`.
For a message body the pipeline writes a "couldn't decrypt" row and asks the
sender to distribute its key and resend (13a). For an action body it does
neither, because the only classifier is `urgent`, and actions are sent
non-urgent. There is no later pass that repairs it: the action is not
re-sent, not queued, and the sender's UI already shows it as sent.

**Trigger** A sender-key or ratchet state mismatch (the exact condition §13a
was built for) on a delete, edit, reaction or pin, in a group or a direct chat.

**Evidence** The two `_quarantine` implementations are identical in this
respect (`group_inbound.dart:264-267`, `inbound.dart:393-394`), and the direct
comment states the intent as "nothing the sender could re-send". That premise
is false for the stored action bodies: an `EditBody`, a `DeleteBody`, a
`ReactionBody`, a `PollVoteBody` and an `RsvpBody` all name a stable target id
— re-sending them is idempotent and is precisely what the outbox would do on a
retry. Only receipts (and typing) really have nothing to re-send. The classification therefore
protects push-notification silence (the actual purpose of `urgent`) at the
cost of correctness.

**Impact** "Delete for everyone" silently fails on the affected device: the
message stays visible (and in media, in search and in the FTS index) while the
author is told it was deleted. An edit silently reverts to the old text on that
device, a reaction vanishes, and a poll vote or RSVP never reaches the other
devices, so two people see two different poll results. None of it produces a
placeholder, an error or a receipt — the failure is invisible on both ends,
which is worse than a visible "couldn't decrypt" row, because the author has
no reason to re-issue the delete.

**Fix sketch** Stop using `urgent` as the repair classifier. Decide from the
body: `TypingBody` and `ReceiptBody` are never repaired; every other body
(including `ActionBody` kinds edit/delete/pin and `ReactionBody`) gets the
placeholder and the reset request. Keep `urgent` for what it means — whether
the server should wake a phone. A cheaper variant that covers the worst case
only: always repair `DeleteBody` and `EditBody`, and leave reactions to the
next reconcile.

**Test that proves it** `group_inbound_test`: a group member sends a
`DeleteBody` (urgent: false) from a device whose sender key the receiver does
not hold; assert the receiver writes an undecryptable placeholder for the
envelope and enqueues a reset to the sender, then that the resent action
deletes the target. Today the test sees neither row nor reset op.

**Overlap** The direct half is the same rule at `inbound.dart:393`; sweep 12c
did not list it (AUD-12c-1 is the doubled delivered receipts), and sweep 12b's
AUD-12b-1 is the give-up classifier for *exceptions*, not for urgency. The
message-level repair itself is 13a and is correct.

---

### AUD-12f-2 A stored `typing` envelope is never marked processed, so it is replayed on every reconnect

**Severity** P3  **Confidence** confirmed code path, client-unreachable today

**Where**
- [`groups/group_inbound.dart:155-165`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_inbound.dart#L155) — the typing branch commits the chain and returns `InboundResult(ignored)` without calling `mark`.
- [`messaging/inbound.dart:262-267`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/inbound.dart#L262) — the same early return for direct chats.
- [`messaging/inbound.dart:510-518`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/inbound.dart#L510) — `_mark` is the only writer of `processed_envelopes` and the cursor, and it returns early for `seq == null`; for a *stored* envelope (non-null `seq`) the early return of the typing branch means nothing records it.
- [`features/presence_service.dart:128-152`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/presence_service.dart#L128) — this client only sends typing as `ephemeral: true`, which is why the gap is not reachable from Helix itself.

**What** Ephemeral envelopes have no `seq` and are deliberately never recorded;
the typing branches therefore skip `mark`. But `ephemeral` is the *sender's*
flag: a stored group envelope carrying `TypingBody` reaches the same branch,
the chain is committed, the indicator is shown, and the envelope is left
unmarked. It is delivered again on the next reconnect while it is still the
newest sequence number. The second pass decrypts a chain iteration that has
already been consumed: within the skipped-key window the indicator flashes
again, and outside it the failure routes through `_quarantine`, which then
*does* mark — with `auth_failed`/`replayed_or_expired` — or, if the envelope
was urgent, writes an undecryptable placeholder for what was only a typing
indicator.

**Trigger** A third-party or modified client sends `TypingBody` with the
ephemeral flag off; or a future change stops sending typing outside the
outbox (the payload in `group_ops.dart` has no ephemeral field, so an outbox
path could not express it today).

**Evidence** The two return sites are identical and neither passes through
`_record`; `_quarantine` treats a non-ephemeral typing envelope as an ordinary
undecryptable message (its only exemption is `envelope.seq == null`).

**Impact** Low and self-limiting: the cursor advances as soon as any later
envelope is marked, so at worst one extra decrypt (and, if urgent, one bogus
placeholder) per reconnect until then. It is listed because the fix is one
line and because it is the kind of asymmetry a future refactor will copy.

**Fix sketch** Return `_record(envelope, mark, EnvelopeOutcome.ignored)` from
both typing branches. For ephemeral envelopes `mark` is already a no-op, so
the same call serves both cases.

**Test that proves it** A crafted stored envelope whose body is `TypingBody`:
assert `processed_envelopes` has a row for it and `inboxDao.cursor` advanced
past its `seq`.

**Overlap** AUD-12c-1 (receipts) touches the same file's transaction but not
this branch.

---

### AUD-12f-3 The first group key to arrive wins over the correct one when the state blob cannot arbitrate

**Severity** P3  **Confidence** likely (the rule is exact; exposure needs a member that races a wrong key or a state blob that is absent/rolled back)

**Where**
- [`groups/group_inbound.dart:380-410`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_inbound.dart#L380) — with no held key (`held == null`) the received key is stored without any test against the blob; the `opensNew`/`opensHeld` arbitration runs only in the `held != null` branch, and line 406 refuses the new key whenever `opensHeld || !opensNew`.
- [`group_inbound.dart:370-375`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_inbound.dart#L370) — the doc comment promises recovery: "the group's name stays unreadable until an admin's key arrives".
- [`groups/group_roster.dart:205-218`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_roster.dart#L205) — the blob a `rolledBack` group carries is the stored one, of an older epoch; it opens under neither key.
- [`groups/group_keyring.dart:153-173`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_keyring.dart#L153) — `openState` tries every held epoch, newest first; `tryOpen` (used as the arbiter here) opens only under the epoch it is given.

**What** The arbitration rule is "a key we hold is only replaced by one that
opens the stored state". It has two asymmetries. (1) When no key is held, the
first arrival is stored unconditionally, even if the stored blob opens under a
different key — a wrong key from a member is accepted. (2) Once that wrong key
is held, the *correct* key is refused whenever the blob still does not open
under it: a blob for an older epoch (`rolledBack`) or no blob at all reaches
line 406 with `opensNew == false` and returns `key_conflict`. The comment says
an admin's key eventually fixes the name; the code only fixes it when the blob
is already sealed under that admin's key, which is the case the wrong key was
supposed to be checked against in the first place.

The common case does heal: if the blob is sealed under the correct key, a
later correct key arrives with `held != null`, `opensNew == true`,
`opensHeld == false`, and is accepted (line 406 falls through). The residual
cases are a group whose state write has not happened yet (a fresh group, or
one whose first state write failed) and a `rolledBack` group.

**Trigger** A member (any member can send `group_key`; only roster membership
is checked) sends an epoch key that does not open the stored state to a device
that holds no key for that epoch — either deliberately, to pin the group name
unreadable on that device until the epoch changes, or by accident (two devices
both believing themselves responsible for a rotation, each minting a key:
`_rekeyDuty` picks one device per event, but a user-initiated `rotateKey` and
a queued `group_rekey` op can overlap with another device's rotation).

**Evidence** The two branches are visibly different in strictness: the
unheld case stores at line 410 with no check, the held case refuses without
`opensNew`. `reopenState` then quietly does nothing when the stored blob does
not open under the stored key ([`group_roster.dart:406-415`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_roster.dart#L406)), so the defeat is silent.

**Impact** The group's name, description and picture stay unreadable (title
falls back to whatever was stored before, `''` for a fresh group) on the
affected device until the epoch advances; the chat itself still works, since
message content uses sender keys. No key material is lost or leaked: the wrong
key cannot open anything a member could not already read.

**Fix sketch** Let the blob arbitrate whenever it can, and keep both candidates
when it cannot: accept-and-store the new key, but if the held key and the new
one disagree and the blob opens under neither, remember the new key as a
candidate (`GroupKeyring` already tolerates several epochs; a per-epoch list
of two is enough) and `openState` tries both. A stricter variant: never store
a key for an epoch whose blob exists and opens under a different key, and
require the sender to be an admin or the member's adder before replacing an
unopenable held key.

**Test that proves it** Two members send different epoch keys to a device that
holds none, with the state blob sealed under the second one and `stateVersion`
ahead (a `rolledBack`-style fetch): assert the device ends up able to open the
name. Today it keeps the first key and shows `key_conflict` for the second.

**Overlap** AUD-12e-2 (trust JSON without CAS) is the other half of "several
writers, no arbiter" in this folder; AUD-12e-1 is the lost-key variant of a
group with no readable state.

---

## Structural proposals

**S1 — one quarantine policy, keyed by content kind, shared by both pipelines.**
*Current shape:* `_quarantine` exists twice (`groups/group_inbound.dart:252`,
`messaging/inbound.dart:385`) and both decide placeholder-plus-repair from
`envelope.urgent`, a server hint whose real purpose is push wake-up.
*Hazard:* AUD-12f-1 — a policy that must stay correct as content kinds grow is
encoded in a transport flag, and the two copies can drift.
*Proposed shape:* a small `QuarantinePolicy` in `messaging/` with
`placeholderFor(body)` and `repairs(body)`, called by both pipelines; `urgent`
stops influencing engine behaviour except for push.
*Migration:* extract the two bodies into the helper, classify by body type,
ship a test per content kind. Expand (add the helper, keep the old call sites)
→ migrate (switch both pipelines) → contract (delete the `urgent` reads).
*Risk:* low; the only behaviour change is more placeholders for non-urgent
non-typing bodies, which is the point.
*Size:* ~80 lines moved, two call sites, one new test file.

**S2 — one arbiter for the group master key.**
*Current shape:* three writers touch the keyring's current-epoch key —
`GroupKeyDistributor.share` (read-only), `rekey` (mint + `put`), and
`GroupInbound._acceptGroupKey` (adopt + `put`) — and the tie-break between
arriving keys is an `if` inside the inbound path.
*Hazard:* AUD-12f-3 and AUD-12e-1: whether a key is the group's is decided by
who arrived first, and `rekey` then reuses whatever key it finds (line 98-131),
so a wrong-but-accepted key is also the one a rotation seals the state under.
*Proposed shape:* a `GroupKeyAuthority` (in `groups/`) owning `put` with the
arbitration rule, `keyFor`, and `openStateFor(blob)`, used by `share`, `rekey`
and the inbound path. Keep the keyring as storage only.
*Migration:* move `_acceptGroupKey`'s decision into the authority and have
`rekey` consult it before minting; the keyring's JSON stays as is. Expand (add
the authority next to the keyring) → migrate (three call sites) → contract
(keyring becomes internal to the authority).
*Risk:* medium — the inbound path currently runs inside the direct pipeline's
transaction; the authority must not open its own.
*Size:* ~150 lines, three call sites, four tests (accept, refuse, conflict,
reopen).

## Verified safe

- **One distribution body for all targets.** `_distribute` builds the
  `sender_key_distribution` content from `encryption.controlMessages[targets.first]`
  ([`group_sender.dart:217`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_sender.dart#L217));
  crypto's `controlMessages` is `{for (final device in key.devicesNeedingKey(roster)) device: distribution}`
  — one identical body per target, so any entry is the right one.
- **The sender-key CAS under the group lock.** `DbSenderKeyStore._ownVersions`
  is process memory, but every own-key read and write runs inside
  `GroupMessageSender`'s per-group `KeyedLock`; a second engine on the same
  database file is caught by `saveOwnSenderKey`'s compare-and-set, and the
  refusal (`StaleSenderKeyState`) degrades to a re-encrypt or (at
  `markDelivered`) to devices staying unmarked.
- **Received-key pruning cannot delete the key it just wrote.** `senderKeysOf`
  orders `createdAt DESC, updatedAt DESC` and the new row carries
  `receivedAt` as `createdAt`, so it sorts first and survives
  `skip(keptReceivedSenderKeys)`.
- **Both rekey crash windows recover.** Die after `share` but before
  `setState`: the next run finds the key in the keyring, `openState` still
  opens the old blob through the previous epoch, and the state is re-sealed
  under the same key. Die after `setState` but before `saveState`: the next
  refresh returns the new blob and `tryOpen` stops the run
  ([`group_rekey.dart:100-161`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_rekey.dart#L100)).
- **`reopenState` never clears a title it cannot open** — it returns before
  writing when `openState` is null (`group_roster.dart:409-415`), so a wrong
  key cannot blank a stored name.
- **Control from this account's own devices is accepted without a roster row**
  (`group_inbound.dart:353`) but still requires a known group row; it is the
  documented self-sync path.
- **Typing is sent outside the outbox** (`presence_service.dart:128-152`) and
  ephemeral sends distribute no keys
  ([`group_sender.dart:113`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_sender.dart#L113))
  — matching the documented "a member without the key simply does not see it".
- **No placeholder for ephemeral envelopes and none on the sender's own
  account** (`group_inbound.dart:261, 270`).

## Coverage notes

- Sender-key rotation triggers (member change, 7 days, 10,000 messages) live in
  `helix_remote_crypto`, audited in sweep 9; the engine only hands the crypto
  the roster and commits what comes back.
- `GroupNotices.add` dedupes by `(messageId, actor)`; whether the server ever
  re-emits the same roster change under a fresh envelope id (leave → re-join →
  leave) was not verified end to end. A duplicate notice would be cosmetic.
- `GroupLimits.keptReceivedSenderKeys` bounds late messages of the previous
  keys; the interaction with a device that stays offline beyond that bound
  resolves to AUD-12f-1's repair path for messages (working) and to silence
  for actions (finding 1).
- `SendGroupContentPayload` has no `ephemeral` field, so the outbox cannot
  send ephemeral group content at all; presence uses the sender directly
  today. If that changes, AUD-12f-2 stops being client-unreachable.
