# Sweep 12e — engine: groups service, roster sync

Read line-by-line: `groups/groups_service.dart` (696), `groups/group_roster.dart`
(601). Cross-reads to settle the findings: `groups/group_rekey.dart` (167),
`groups/group_keyring.dart` (196), `groups/group_trust.dart` (152), the roster
DAO (`replaceRoster` groups_dao.dart:115-132, `saveMemberDevices` 135-149), the
server's create/add/join-request handlers (groups/module.dart:438-505,
624-679, 1006-1061), the group-aware `device_list_stale` answer
(module.dart:1112-1129), the `StaleDevices` DTO (protocol errors.dart:133-171)
and `EngineConfig.trustLinkJoins` (config.dart:30, 126-130). ~2,100 lines.
Two structural proposals.

Verdict: the roster is the server's and the "an unexplained member gets no
keys" gate is carefully built. What is missing is *atomicity* between the
writers of per-group state: the key, meta and trust records are JSON blobs
mutated read-modify-write from four actors, and the mutating group calls
discard or skip key material when a response is ambiguous.

---

### AUD-12e-1 A create whose response is lost throws away the only copy of the group key

**Severity** P2  **Confidence** confirmed (the path is unconditional; only the trigger is a race with the network)

**Where**
- [`groups/groups_service.dart:253`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/groups_service.dart#L253) — a fresh master key is made and the state sealed under it; [`groups_service.dart:267`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/groups_service.dart#L267) stores it locally.
- [`groups_service.dart:270-282`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/groups_service.dart#L270) — `on Object { await _keyring.forget(groupId); rethrow; }` around `api.groups.create`: an `ApiException` (refused) and a `NetworkException` (maybe committed) are treated alike.
- [`groups_service.dart:283-287`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/groups_service.dart#L283) — the wire to the members (`_keys.share`) runs only after the lost response would have arrived.
- [`groups/group_rekey.dart:57-58`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_rekey.dart#L57) — `share` returns false without a held key; [`group_rekey.dart:120-126`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_rekey.dart#L120) — `rekey` refuses to mint a key when the state blob cannot be opened **and the title is empty**.
- [`groups_service.dart:646-647`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/groups_service.dart#L646) — `rename`/`setDescription`/`setAvatar` throw `noGroupKey` without a key.
- The id is client-chosen and the server only refuses a *remote* id that already exists: [`groups/module.dart:450-473`](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L450); a retry with the same id reaches the insert and fails there.

**What** `create` generates the group id and the master key on the device, seals
the initial state, stores the key, and only then calls the server. The call is
wrapped in a catch-all that **forgets the key** before rethrowing. For a timeout
or a reset the outcome is unknown: if the server committed, the group now exists
with the invited members, but the one device that held the key has deleted it,
and the members were never sent it. Nothing in the engine can repair that:
`shareKey` needs the key, `rename` needs the key, and `rekey` deliberately
refuses to replace an empty title with a new key. A user retry creates a second
group under a new id, so the first one stays in every member's list with an
empty name and cannot be renamed by anyone.

**Trigger** A network-level failure (timeout, connection reset) on
`POST /v1/groups` after the server committed the creation.

**Evidence** The catch is `on Object`, with no distinction between a refusal
and an ambiguous transport failure. The empty-title guard in `rekey` (120-126)
exists so a device that never received a key cannot wipe a real name; combined
with the forgotten key it becomes a permanent dead end. `share` returns false
rather than throwing when the keyring has nothing, so a "repair" call reports
nothing.

**Impact** The group's name, description and picture are permanently lost for
every member of that group; the chat still works (message content uses sender
keys), so the group looks broken rather than gone, and it can never be renamed
or given a new picture. The invited members are stuck in a nameless group, and
the creator owns a duplicate.

**Fix sketch** Distinguish `ApiException` (forget, rethrow) from a transport
failure (keep the key). On a transport failure, reconcile by id:
`api.groups.get(groupId)`; a 404 means nothing was created (forget and rethrow
the original error); a 200 means the create committed — run `_roster.apply`,
`_keys.share` and return the `CreatedGroup` the caller expected. Treat a retry
that meets `alreadyExists` the same way rather than failing. Separately, give
`rekey` one explicit empty-state path (no key at all, blob unreadable, title
empty): mint a key and seal an empty state, since there is no name left to
protect.

**Test that proves it** Engine test with a transport that lets the server-side
handler complete and then throws a timeout: assert `create` returns a group,
the creator reads the title, the members received the key op, and a retry does
not create a second group.

**Overlap** AUD-12e-2 (ambiguous failure of a mutating call) and AUD-12b-1
(a failed rekey op is never retried) — this is the path that makes the latter
permanent for a whole group.

---

### AUD-12e-2 Group trust (and the keyring) are read-modify-write JSON without a CAS: a confirm can release an unconfirmed member

**Severity** P2  **Confidence** likely (mechanism confirmed; needs a UI action to overlap a roster apply)

**Where**
- [`groups/group_trust.dart:123-132`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_trust.dart#L123) — `confirm` reads the whole pending map and writes it back, two statements apart.
- [`group_trust.dart:91-111`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_trust.dart#L91) — `explain` does the same for `pending` (and for `explained`); [`group_trust.dart:114-119`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_trust.dart#L114) `takeExplained` likewise.
- [`groups/group_roster.dart:248`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_roster.dart#L248) — the apply transaction; [`group_roster.dart:284-291`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_roster.dart#L284) holds back each new member inside it.
- [`groups_service.dart:187-199`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/groups_service.dart#L187) — `confirmMember` takes no group lock; [`groups_service.dart:360`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/groups_service.dart#L360) — `explainOwnAdds` in `addMembers` likewise.
- What the flag gates: [`group_roster.dart:510-513`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_roster.dart#L510) (`withheld` in the send roster) and [`group_rekey.dart:50-52`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_rekey.dart#L50) (withheld in `share`).
- Same shape elsewhere: [`group_keyring.dart:101-115`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_keyring.dart#L101) (`put` rewrites the whole epoch map); [`group_roster.dart:205-210`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_roster.dart#L205) computes the state rollback guard *outside* the transaction that then writes unconditionally (line 249).

**What** `confirm`, `explain` and `takeExplained` each read a JSON document,
mutate it in Dart and write it back. The roster apply's hold-back runs inside a
drift transaction, but `confirmMember` and `explainOwnAdds` issue plain
statements. A read that completes before the apply commits and a write that
lands after it drops whatever the apply inserted:

1. `confirmMember(A)` reads pending `{A}`.
2. The inbound apply inserts member B (server-added, unattributed) and writes
   pending `{A, B}` inside its transaction.
3. `confirmMember` writes `{}`.

B is now accepted. `rosterForSend` stops withholding B and the next send
distributes this device's sender key to it; the next `share`/`rekey` hands it
the group master key. And because the hold-back loop only marks members that
were not in the previous roster (`group_roster.dart:285-286`), no later refresh
re-holds B: the release is permanent.

**Trigger** A user confirms a pending member (or adds someone, which calls
`explain`) at the moment the inbound pipeline applies a roster change that
holds back a *different* new member.

**Evidence** Every mutation is `get` → mutate → `set` with an await in between
and no compare-and-set (settingsDao has none); the readers (`pending()` inside
`_apply`, `rosterForSend`, `share`) trust the whole document. The hold-back
condition is `existing != null && previous.isNotEmpty` and skips any account
already in `previous`, so a dropped entry is never reconsidered.

**Impact** The confirmation gate of CRYPTO_V2 §14 — the only defence against a
server silently adding a member — can be erased by an unrelated confirm, and
the member then receives this device's sender key and the group key. The same
lost-update pattern can drop an epoch key (state sealed under it becomes
unreadable on this device) or restore an older description/state blob.

**Fix sketch** Per-entry rows instead of one document: `group.pending.<id>.<account>`
and `group.key.<id>.<epoch>` (plus the explained marker), read through a small
store. Each mutation becomes a single-row upsert, so there is nothing to lose.
If the JSON shape must stay, wrap each mutation in a transaction *and* hold a
per-group lock from read to write — do not reuse `GroupRosterSync`'s lock from
inside `_apply` (it is non-reentrant); do it at the service boundary. Make the
group-state write conditional (`WHERE state_version < ?`) instead of the TOCTOU
`rolledBack` comparison.

**Test that proves it** Unit test on `GroupTrust` + `GroupRosterSync` with a
gated settings DAO: pause `_apply` after it writes pending `{A, B}`, run
`confirmMember(A)` to completion, release; assert B is still pending. Today it
is gone. A second test over `GroupKeyring.put` with two interleaved puts
asserts both epochs survive.

**Overlap** AUD-12d-1 (the same "two mechanisms, no owner of the order" shape
between locks and transactions); the structural proposal below.

---

### AUD-12e-3 The key share after add/approve is derived from the response, so a lost response leaves the new member without the group key

**Severity** P3  **Confidence** confirmed

**Where**
- [`groups_service.dart:355-365`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/groups_service.dart#L355) — the share audience is `result.added`, taken from the one response.
- [`groups_service.dart:544-555`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/groups_service.dart#L544) — the same in `approveJoinRequest`.
- [`groups_service.dart:598-603`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/groups_service.dart#L598) — `_afterRemoval` runs `forgetMember` and the rekey only after a network `refresh`.
- [`groups/module.dart:648-649`](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L648) — a repeated add reports the account as `alreadyMember`, not `added`.
- [`groups/group_inbound.dart:562-564`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_inbound.dart#L562) — the roster-event path returns early when the actor is not a joiner, on the assumption that the actor shares the key.

**What** If `addMembers` times out after the server added the accounts, the
share never runs. Every later attempt — the user's retry included — reports the
accounts as already members, so `result.added` stays empty and the share is
still skipped; the roster event's `_joinShare` defers to the actor, which is
this account. The new members remain in the group with no group key (empty
title, no description) until someone calls `shareKey` by hand. An `approve` that
succeeds on the server but whose follow-up `refresh` fails has the same effect.

**Trigger** A timeout/reset on `POST …/members` or `POST …/join-requests`
after the server committed, or a failed `refresh` right after.

**Evidence** The only call sites of `_keys.share` for an addition are the two
service methods (create, add/approve), and both are chained to a normal return
(see AUD-12e-1's `create` for the same pattern). The event path's early return
is explicit and correct for a *successful* call.

**Impact** The invited people see an unnamed group indefinitely; recoverable by
an admin pressing "share key", which most users will not know to do.

**Fix sketch** Derive the audience from the refreshed roster diff
(`RosterUpdate.added`) instead of the response, and run that share even when
`result.added` is empty; or enqueue a durable "share the current key with
whoever is new" duty after any successful mutation. In `_afterRemoval`, do the
local steps that need no server answer (`forgetMember`, and queueing the rekey —
`rekey` re-reads the group itself) before the network refresh, or in a `finally`.

**Test that proves it** Engine test: transport that applies an add and throws a
timeout; after a retry (or the next sync) assert the member received the group
key op. Today no share is ever queued.

**Overlap** AUD-12e-1, AUD-12b-1.

---

## Structural proposals

### S1 One writer for per-group state (settings JSON today)

- **Current shape:** four settings rows per group — `group.keys.<id>`,
  `group.meta.<id>`, `group.pending.<id>`, `group.explained.<id>` — each a JSON
  document, each mutated read-modify-write by the roster apply, the outbox
  rekey, the inbound group_key path and the UI service, with no lock and no
  compare-and-set.
- **Hazard:** lost updates (AUD-12e-2). In the worst direction a lost pending
  entry releases an unconfirmed member permanently; a lost epoch key makes the
  group state unreadable on that device; a lost meta write restores an old
  description; the group row's `state`/`stateVersion` can be regressed by a
  refresh that read the row before a concurrent `setState`.
- **Proposed shape:** one `GroupStateStore` that owns every write, with the
  pending/explained/keys records stored one row per entry
  (`group.pending.<id>.<account>`, `group.key.<id>.<epoch>`) so every mutation
  is an independent upsert. Keep the state blob where it is, but write it with
  a version condition instead of a pre-read comparison.
- **Migration:** expand (write both shapes; read the per-entry rows first, fall
  back to the JSON blob), migrate (one pass that rewrites each blob into rows
  when the group next loads), contract (delete the blob readers and the
  `keys()` map parser). No schema change — the settings table carries it.
- **Risk:** do not take `GroupRosterSync`'s per-group lock from inside `_apply`
  (same key, non-reentrant `KeyedLock`): the lock belongs at the service
  boundary, and per-entry rows remove the need for it inside the transaction.
- **Size:** M — 5 files, ~250 lines, plus the trust/keyring tests.

### S2 One post-mutation reconcile for the six server-mutating group calls

- **Current shape:** create, add, remove, approve, leave and delete each run
  "call the server, then a hand-written sequence" (apply/refresh, explain,
  share, forget, enqueue rekey), every step depending on the previous one
  returning normally, and with different recovery per call.
- **Hazard:** an ambiguous result or a single failed follow-up leaves key
  material unshared, or — in `create` — destroyed (AUD-12e-1, -3).
- **Proposed shape:** `_mutate(call, intent)`: run the call; on a transport
  error reconcile by group id (`GET`; 404 means it did not happen); then
  always refresh the roster, share the current key with `RosterUpdate.added`,
  spin down removals (forget sender keys, queue the rekey) and emit the local
  events. Each public method supplies only the call and the intent, keeping its
  signature and its `GroupException` mapping.
- **Migration:** expand (introduce the helper for `addMembers` and
  `approveJoinRequest`), migrate (`create`, `removeMember`/`ban`), contract
  (delete the bespoke sequences). The public API does not change.
- **Risk:** the helper must not swallow a refusal the UI needs to show (return
  a result, rethrow `ApiException` unchanged) and must limit "ambiguous" to
  transport failures, not to every exception.
- **Size:** M — 1 file, ~150 lines, plus tests.

---

## Verified safe (checked, not findings)

- `replaceRoster` refuses an epoch older than the stored one
  ([groups_dao.dart:121](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/daos/groups_dao.dart#L121)): a late answer cannot put a removed member back.
- `openState` tries every held epoch, newest at or below the group's epoch
  first, with the epoch in the AAD
  ([group_keyring.dart:153-173](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_keyring.dart#L153)):
  a rotation does not hide the title, and a blob can only open under its own
  epoch.
- `rekey` is idempotent (already sealed under the current key → stop) and
  queues the key *before* the state write
  ([group_rekey.dart:100-139](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_rekey.dart#L100)).
- `adoptStale`'s `missing` really is the full device list for groups, despite
  the DTO's "devices the request did not address" wording: the groups route
  fills every account's `missing` with its whole current list
  ([module.dart:1112-1126](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L1112)),
  so replacing the cache with it is correct and revoked devices drop out.
- `refreshAll` cannot forget groups past a first page: `myGroups` returns
  every group (local and remote) with no cursor
  ([module.dart:507-520](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L507)).
- Withholding is cryptographic and does not change delivery: the withheld
  member's devices stay in the digest but are dropped from the sender-key
  audience and from `share` (roster 56-65, 506-523; rekey 50-52), which is the
  design in CRYPTO_V2 §14.
- `attributeAdded` explains only an actor who may add (owner/admin, or anyone
  when the group allows it) and treats a self-join as `link_join` unless
  `trustLinkJoins` (default false, and the key reaches a trusted link joiner
  through `_joinShare`).
- `previewInvite` degrades to the member count on a bad AAD or format instead
  of throwing ([groups_service.dart:502-515](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/groups_service.dart#L502)).
- `create`'s `byId(...)!` cannot be null: for a new row the epoch is equal, so
  `replaceRoster` applies and `ensureGroup` ran in the same transaction
  (roster 249-276).
- The server re-checks every role these methods check locally (add:
  module.dart:635-638; set_state and send similarly), so a stale local role
  grants nothing.
- `GroupInviteLink.toString` redacts the link, and only the token (not the
  preview key) reaches the server.

## Coverage notes (not filed)

- A group read after `_lose` (`existing == null`) trusts every listed member
  without confirmation — the "first roster is trusted" rule. A server that
  404s a group to make a device forget it, then re-lists it with extra members,
  gets them trusted: a consequence of CRYPTO_V2 §14's open item (signed
  membership changes), not a new defect.
- `_lose` forgets keys, meta and trust in a transaction, but a `rekey` op that
  passed its `refresh` before the leave can `put` the key back into settings
  afterwards: leftover key material for a group this device left. Harmless
  without the server's blob; worth a cleanup when S1 lands.
- `GroupTrust._maxExplained` (200, FIFO) can drop an old explanation after 200
  additions in one group; harmless because an explanation is consumed by the
  next roster apply and re-explained by the adding device.
- `bans()` is local-only by design: the server exposes no ban list (documented
  at groups_service.dart:234-236). Bans made on another device are invisible
  here, which the UI must not present as a complete list.
- `_updateState` and `_apply` write `groups.state` / `settings meta` with no
  shared lock; folded into AUD-12e-2's fix (conditional write) instead of a
  separate finding, because the impact is a transient stale title.
- The service mirrors server permission checks for *UI shape only*; every
  call is re-checked server-side, including the owner-only ownership transfer
  in `setRole` and the owner-only `deleteGroup`.
