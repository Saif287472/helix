# Sweep 12c — engine: apply, inbound, content codec, kinds

Read line-by-line: `messaging/apply.dart` (852), `messaging/inbound.dart`
(528), `messaging/content_codec.dart` (113), `messaging/kinds.dart` (42),
plus the `inbox_dao` deferred-action queries (`deferAction`, `takeDeferred`,
`purgeExpiredDeferred`, inbox_dao.dart:94-126) and the maintenance call that
purges them. ~1,600 lines. No structural proposal: `ContentApplier` is one
cohesive unit (one envelope applied in one transaction) and splitting it
would only move its section comments into files.

Verdict: the inbound half is the strongest code read so far — dedupe before
work, decrypt-commit-apply in one transaction, identity pinning on new
sessions, quarantine for anything unreadable, one serial queue. Two defects
sit on top: a copy-paste double receipt, and edit/delete windows measured
against a timestamp the sender chooses.

---

### AUD-12c-1 Every arriving message queues two `delivered` receipts

**Severity** P2  **Confidence** confirmed

**Where** [`messaging/apply.dart:324`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/apply.dart#L324) and [`messaging/apply.dart:331`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/apply.dart#L331) — `_delivered(chat, content.id, sender.account, now)` is awaited twice on the incoming path, with only an unrelated early return between the two calls.

**What** For a message that arrives and is stored, `_insertMessage` queues a
delivered receipt, then queues the *same* receipt again unless the message
is a call log that already rang on this device. `_delivered` mints a fresh
content id each time ([`apply.dart:357`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/apply.dart#L357)) and `enqueueContent` uses that id as
its idempotency key, so the outbox keeps both and the idempotency machinery
does not collapse them.

**Trigger** Every incoming visible message — text, media, poll, event, a
missed call — in a direct or group chat.

**Evidence** The first call runs unconditionally after `if (fromSelf) return`;
the intervening `if (callLog != null && !(unseenCall && missed)) return;`
only skips the *second* call for call logs. Neither call is inside a branch
that varies with the receipt, and the two calls have identical arguments.
`_delivered` does no dedupe of its own: `ids: [messageId]` on a new
`ContentMessage` each time (apply.dart:369-381).

**Impact** Receipt traffic doubles for every message received: two outbox
ops, two pairwise sends (one ciphertext per author device each), two ratchet
steps, two `recordReceipt` writes on the author's device. On a phone this is
the dominant inbound-response cost and it scales with the number of author
devices. No visible behaviour changes, which is why it has survived.

**Fix sketch** Delete one of the two calls (the second is the intended one:
the first was presumably left behind when the call-log early return was
added).

**Test that proves it** Engine test: Alice sends a text to Bob, drain both
outboxes, assert Bob's outbox had exactly one `send_content` op whose body is
a `ReceiptBody`, and that Alice's message reaches `delivered` with a single
receipt row.

**Overlap** AUD-3-1 (unnecessary fan-out cost, server side) — same shape,
client side; AUD-12b-2's neighbour in the pipeline.

---

### AUD-12c-2 The edit and delete windows are measured against a sender-chosen timestamp that is only clamped in the future

**Severity** P3  **Confidence** confirmed

**Where**
- [`messaging/apply.dart:209`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/apply.dart#L209) — `_clamp` caps a future `sentAt` at `now + 1 min` and leaves anything older untouched.
- [`apply.dart:450`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/apply.dart#L450) — `at = _clamp(content.sentAt, now)` is the timestamp every window is checked against.
- [`apply.dart:508`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/apply.dart#L508) — edit window `at.difference(target.sentAt) > ContentLimits.editWindow`.
- [`apply.dart:542`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/apply.dart#L542) — delete window, same comparison.

**What** A negative difference passes both checks. A modified client can
send an `EditBody` or `DeleteBody` with `sentAt` set before the target
message (e.g. 1970) and edit or retract a message of any age,
indefinitely — the "15 minutes" the design states (CONTENT_V2.md §3) is not
enforced. `_edit` also writes `editedAt: at`, so the row's edit time goes
backwards (apply.dart:511, 524-528).

**Trigger** A client that does not use this app's `sentAt`; the server
forwards content without inspecting it, so nothing else stops it.

**Evidence** The clamp is one-sided by construction (`sentAt.isAfter(limit)`
only). Both windows use `>` against the difference, which a negative value
never satisfies. The `editedAt` monotonicity check compares against the same
attacker-controlled `at` (apply.dart:511-513), so a backdated edit cannot be
overwritten by a real later edit but does not itself get rejected.

**Impact** Message history can be silently rewritten or retracted after the
window the product promises, on the recipient's device, by a modified peer
client. It also lets a peer inject an edit that no later legitimate edit can
replace (the backdated `editedAt` outranks nothing, but the real edit is
accepted; the *displayed* original text is the changed one either way).
Not a confidentiality issue; an integrity-policy bypass.

**Fix sketch** Clamp both ends: reject (or clamp to `target.sentAt`) a
`sentAt` earlier than the target's own `sentAt`, in `_edit` and `_delete`
(and for the reaction ordering at apply.dart:483, where a backdated reaction
also loses every "newest wins" comparison and is ignored — benign). A
`_clampBetween(sentAt, notBefore, now)` helper keeps the call sites honest.

**Test that proves it** Engine test: Bob's message, then a forged
`DeleteBody` for it with `sentAt` one hour before the original, sent after
the delete window; assert the message is still present.

**Overlap** AUD-8-* content validation (the protocol accepts any `sentAt`);
this is the engine's side of the same trust boundary.

---

## Verified safe (checked, no finding)

- **One transaction per envelope.** Session save, consumed prekey, person
  pin, message/action, `processed_envelopes` and cursor commit together
  (inbound.dart:275-302); quarantining commits its placeholder and the mark
  in one transaction too (inbound.dart:395-442).
- **Dedupe before work.** `isProcessed(id, senderDevice)` runs before any
  decryption (inbound.dart:102-108); ephemeral envelopes (no `seq`) are
  never recorded (inbound.dart:512-518).
- **Ratchet movement is never lost.** A content that decodes badly after a
  successful decrypt commits the session first (inbound.dart:255-260), so
  the same failure cannot loop.
- **Identity pinning.** A device claiming this account under another key is
  quarantined, and a *new* session pins the sender's identity key on first
  sight (inbound.dart:225-249).
- **Group gate.** Pairwise group bodies may only be receipts; group content
  must come through the group send; system timers need an admin
  (apply.dart:181-203).
- **Receipt scoping.** A receipt only moves messages of the named
  conversation and author (apply.dart:612-645); a group receipt waits for
  every member in the group when the message was sent (apply.dart:686-718).
- **Re-send entitlement.** `_mayResend` limits who can pull a copy of an own
  message: the peer, own devices, or a current member who joined before it
  was sent and is neither banned nor blocked (apply.dart:835-851).
- **Deferred actions.** Stored for the missing target, applied when it
  arrives, and purged by the 5-minute maintenance pass
  (inbox_dao.dart:120-126; maintenance.dart:58), so an expired one lives at
  most one pass.
- **Codec round-trip.** `split`/`join` are inverse for the text and media
  cases they special-case; reserved row kinds can never be forged by a peer
  (content_codec.dart:102-108; kinds.dart:24).

## Coverage notes (12d+)

- A peer can backdate a *message* (not just an edit) arbitrarily far, so it
  sorts above all history (`SortKey.of`, apply.dart:272). Only the future is
  clamped by design; noted, not filed.
- `_quarantine` writes a placeholder into the sender's direct chat even when
  the undecryptable envelope was pairwise group content — today those are
  receipts (`urgent: false`), so no placeholder is created; if a future
  control type is marked urgent this becomes a misaddressed row.
- `_applyDeferred` does not re-run the group gate, so a reaction deferred
  while the sender was a member is applied even if they were removed in the
  meantime (7-day maximum, and it only changes a reaction/edit they were
  entitled to make when sent).
- `kinds.dart`'s `known` list is presentation only; `isRenderable` is not
  used for storage decisions.
