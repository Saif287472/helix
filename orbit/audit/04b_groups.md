# Sweep 4b — groups (roster, invites, sends)

The groups module is the roster authority: roles, settings, membership, bans,
invite links, join requests and the group send path. Names and messages are
end-to-end encrypted; the server enforces who may do what. Federation is split
into 4c.

Findings: **P1 1, P2 1, P3 4**. The P1 is the same stored-envelope fan-out as
AUD-4a-1, reached here by an ordinary group operation rather than by blocks.

## Files read

| File | Lines |
|---|---|
| `helix_remote/server/lib/src/modules/groups/MODULE.md` | 141 |
| `helix_remote/server/lib/src/modules/groups/api.dart` | 59 |
| `helix_remote/server/lib/src/modules/groups/module.dart` | 1,273 |
| `helix_remote/server/lib/src/modules/groups/application/frame.dart` | 51 |
| Cross-checks: protocol `modules/groups.dart` (limits, settings defaults, AddMembersRequest), messaging `_accept`/`chargeStored`, `platform/http/routes.dart` (body cap, per-route limit, idempotency) | ~160 |

`data/group_store.dart` and `federation.dart` are sweep 4c; nothing there was
judged for SQL shape or the S2S trust checks yet.

## What is sound

- Non-members get 404 on every group route, so ids do not leak
  ([module.dart:343-355](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L343)).
- Role checks are consistent: owner-only ownership transfer, admins cannot
  touch the owner, the sender's own role gates `add`, `edit_info` and `send`
  ([module.dart:357](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L357),
  [module.dart:744](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L744)).
- The send digest is checked in constant time against every member device and
  the stale answer lists the real lists
  ([module.dart:1112-1130](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L1112)).
- Distributions may only name member devices other than the sender's, so a
  client cannot route a distribution to an arbitrary device
  ([module.dart:1135-1147](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L1135)).
- Stored sends are charged per member device plus distributions, with a second
  per-group budget, before delivery
  ([module.dart:1186-1205](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L1186)).
- `groups.create` (20/day), `groups.preview` (60/h) and `groups.send`
  (200 burst, 5/s per device, before the body is read) exist
  ([module.dart:75-108](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L75)).

---

### AUD-4b-1 An unthrottled roster operation stores a `roster_change` in every member's mailbox; looping it flushes them

**Severity:** P1
**Confidence:** confirmed
**Where:** [`_announce`, module.dart:380-430](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L380); fan-out [module.dart:402-419](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L402); unthrottled mutations [addGroupMembers, module.dart:182](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L182), [removeGroupMember, module.dart:183-188](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L183), [setGroupState, module.dart:175-180](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L175), [joinGroup, module.dart:196](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L196); quota and trim [mailbox_store.dart:20](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/data/mailbox_store.dart#L20), [mailbox_store.dart:107-131](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/data/mailbox_store.dart#L107).

**What:** Every roster or settings change calls `_announce`, which stores one
`roster_change` envelope **per device of every member** (1,024 accounts at most,
multiplied by devices) via `messaging.deliver`
([module.dart:398-419](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L398)).
`deliver` writes a mailbox row per device and trims that device's oldest
envelopes once it holds 10,000
([messaging/module.dart:578-594](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L578)).
None of the mutating routes have a `rateLimit` — only `groups.send`,
`groups.create` and `groups.preview` do — so the global 10 req/s per IP is the
only bound. A mutation that changes nothing sends nothing, but alternating
add/remove (or join/leave through a no-approval link) changes the roster every
time, so one account produces two full fan-outs per cycle.

**Trigger:** Create a group (20/day), add up to 1,023 accounts that have not
blocked you and allow group adds (the default,
[people/module.dart:131](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L131)),
then alternate adding and removing one puppet account at 5 cycles/s. Each
cycle writes two `roster_change` envelopes to every member device. At 1,000
target devices the 10,000-row quota is reached in five cycles — a few seconds
— and the trim runs on every cycle thereafter. A member with a no-approval
invite link can do the same alone via join/leave.

**Evidence:** `_announce` is called by `_create`
([module.dart:495](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L495)),
`_addMembers` ([module.dart:663-671](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L663)),
`_remove` ([module.dart:719-726](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L719)),
`_join` ([module.dart:991-999](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L991)),
`_setState` and `_setSettings`; the delivery is unconditional for every member
device. `trim` deletes `ORDER BY seq LIMIT n`, i.e. the oldest undelivered
envelopes. The route table passes no `rateLimit` for any of them
([module.dart:169-205](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L169)),
and the registry only applies a limiter when one is set
([routes.dart:230-240](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/routes.dart#L230)).

**Impact:** Any account can silently destroy other accounts' oldest
undelivered envelopes (messages, group updates, parked call offers) just by
making them group members; the victim need not have any relationship with the
attacker and can be added by default privacy. This is a wider reach than
AUD-4a-1: the fan-out is per member device, and the trigger is an ordinary
group mutation. Secondary: the victims' clients receive a burst of roster
events.

**Fix sketch:** Send `roster_change` through the same budgeted path as S1 in
`04a_people.md`: either make it advisory (online-only) with a state refetch
when a client reconnects, or bound it — one announcement per group per short
window (coalesce add/remove of the same account), plus a per-actor rate limit
on `add_members`, `remove_member`, `join` and `set_state`. Do not remove the
stored form blindly: a removed member must still learn they were removed while
offline, which `GET /v1/groups` no longer shows. Wire: no shape change for the
coalesced form.

**Test that proves it:** Create a group with one victim device, fill its
mailbox to quota−1 with a normal message, then add/remove a puppet ten times
and assert the normal message survives (today it is trimmed).

**Overlap:** AUD-4a-1 (same mechanism, different trigger), AUD-3-1 (fan-out
cost), AUD-3-2 (trim accounting), AUD-1b-1 (dedupe-key death for group syncs).

---

### AUD-4b-2 Ephemeral group sends bypass both budgets and fan out to every member device

**Severity:** P2
**Confidence:** confirmed
**Where:** [module.dart:1175-1181](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L1175) (ephemeral return before charging), charge only at [module.dart:1186-1197](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L1186); fan-out [module.dart:1149-1154](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L1149); `deliverEphemeral` [messaging/module.dart:635-665](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L635).

**What:** The ephemeral branch returns immediately after
`messaging.deliverEphemeral(fanOut, …)`, before `chargeStored` and before the
per-group `fan_out` limiter. Only the per-device `groups.send` limit (200
burst, 5/s) applies, and one request fans out to every member device. Each
device costs an ephemeral `put` and a bus publish
([messaging/module.dart:641-663](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L641)),
so one member of a 1,024-member group can drive ~5,000 device round trips per
second from a single client.

**Trigger:** Any member sends typing indicators (or crafted ephemeral group
messages) at the 5/s device limit.

**Evidence:** MODULE.md documents "Ephemeral sends are not charged"
([groups/MODULE.md:64](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/MODULE.md#L64));
the code path confirms the early return. The group budget is only hit for
stored sends.

**Impact:** The group is a free amplifier for the cost shape in AUD-3-1 (two
DB round trips and a publish per recipient device). A large group's typing
indicators can saturate a node's ephemeral store and bus without any sender
budget being consumed; a malicious member can do it deliberately.

**Fix sketch:** Charge ephemeral group sends a small per-device unit (a
separate `groups.eph` policy, or a fraction of `groups.fan_out`) and/or batch
the ephemeral put/publish (S1 in `03_messaging_realtime.md`). No wire change;
a new documented `rate_limited` on a path that today never returns one.

**Test that proves it:** Send ephemeral group messages at the device limit for
a minute and assert the group budget is consumed / the request is refused;
today it is never touched.

**Overlap:** AUD-3-1, Q1 in `99_OPEN_QUESTIONS.md`.

---

### AUD-4b-3 A refused or failed group send still burns the sender's stored budget

**Severity:** P3
**Confidence:** confirmed
**Where:** [module.dart:1186-1205](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L1186); `chargeStored` [messaging/module.dart:615-632](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L615); delivery tx [module.dart:1207-1227](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L1207).

**What:** The sender's `chargeStored` runs first, then the per-group limiter
may refuse (`rate_limited`), then delivery runs in a separate transaction that
can still fail. `chargeStored` is a sliding-window token bucket
(`storedPerAccount`, 50,000 units / 250 per second), not a ledger, so a refused
or rolled-back send consumes tokens that are never returned. A send to 2,000
devices costs 2,000 units: eight seconds of the sender's budget lost per
refusal.

**Trigger:** Send into a large group after the group budget is exhausted, or a
send whose delivery transaction fails (e.g. a pool timeout).

**Evidence:** Charge at 1193-1197, group check at 1198-1205, tx only at 1207;
`chargeStored` has no refund path
([messaging/module.dart:623-631](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L623)).

**Impact:** A sender can be throttled for a minute after one failed large send,
with no message delivered; retries make it worse. Also the group budget is
checked after the sender budget, so the group-level refusal always wastes the
sender's tokens.

**Fix sketch:** Check the group limiter before `chargeStored`, and charge
inside the delivery transaction (or refund on failure). The limiter hits are
cheap; reordering is not a wire change.

**Test that proves it:** Exhaust `groups.fan_out`, attempt a large send, then
assert the sender's `messaging.stored_account` availability is unchanged.

**Overlap:** AUD-3-6 (charge before filtering/relay in messaging).

---

### AUD-4b-4 Group sends have no message-id dedupe, unlike direct sends

**Severity:** P3
**Confidence:** confirmed
**Where:** [module.dart:1155-1161](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L1155) (id passed straight to `deliver`), [module.dart:1207-1227](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L1207); contrast direct sends [messaging/module.dart:313-321](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L313) and [messaging/module.dart:377-399](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L377).

**What:** A direct send is deduped by `(sender account, sender device, id)` in
`messaging.sends` regardless of any header. A group send carries `req.id` into
the envelopes but never records it, so the only replay protection is the
optional `Idempotency-Key` header
([routes.dart:306-321](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/routes.dart#L306)).
A retry without that header (a different client, a header lost by a proxy, a
retry after the idempotency record expired) stores the ciphertext and every
distribution a second time and charges again.

**Trigger:** Client retries `POST /v1/groups/{id}/messages` with the same
message id but no `Idempotency-Key`.

**Evidence:** `req.id` is used at 1157 but there is no `recordSend`/`acceptedAt`
call anywhere in groups (`_store` has no send table; the send path goes
straight to `messaging.deliver`). MODULE.md's "Retries: use Idempotency-Key"
([groups/MODULE.md:70](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/MODULE.md#L70))
is therefore the only mechanism.

**Impact:** Duplicate ciphertext and sender-key distributions in every member
mailbox, double budget consumption, and duplicate message rows on each device;
the client's own message-id dedupe may hide it, but the server-side copies are
real and count against quotas.

**Fix sketch:** Route group sends through the same `recordSend` acceptance
path keyed by `(actor.account, senderDevice, req.id)` before delivering (the
remote fan-out job already dedupes by `gfan:<domain>:<id>`). Schema: reuse
`messaging.sends` via a small facade method rather than adding a table.

**Test that proves it:** Send the same `req.id` twice without an
Idempotency-Key; assert one set of mailbox rows and one charge. Today there
are two.

**Overlap:** AUD-1a-3 (idempotency), AUD-1b-1 (gfan dedupe key).

---

### AUD-4b-5 `add_members` is bounded only by the request body, and each id costs several queries under the group row lock

**Severity:** P3
**Confidence:** confirmed
**Where:** [module.dart:624-679](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L624); body cap and default [routes.dart:99](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/routes.dart#L99), [routes.dart:106](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/http/routes.dart#L106); no list cap in the DTO [protocol groups.dart:266-274](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/modules/groups.dart#L266).

**What:** `AddMembersRequest.accounts` has no length limit; the route has no
`maxBodyBytes`, so the default 1 MiB applies (~25k quoted UUIDs). The handler
locks the group row `FOR UPDATE`
([module.dart:634](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L634))
and then, per id, calls `identity.account`, `_store.role`, `_store.isBanned`
and possibly `people.mayAddToGroup` before it ever counts members. A request
full of unknown UUIDs does ~75k queries while holding the lock.

**Trigger:** A member who may add (owner/admin by default,
[protocol groups.dart:32](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/modules/groups.dart#L32))
posts a 1 MiB list of random ids.

**Evidence:** The loop has no early length check; the member cap is checked
only after the per-id lookups
([module.dart:641-661](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L641)).
The only route limit is the global per-IP one.

**Impact:** One request can hold a group's roster lock for seconds to tens of
seconds, blocking sends that need the roster, and consume a DB core; repeated
at the 10/s global limit it is a single-node DoS scoped to that group.

**Fix sketch:** Reject `accounts.length > Group.maxMembers` (or a smaller
batch cap, e.g. 100) in the DTO/`fromJson`; resolve members before taking the
row lock, or check the cap first. No wire change (the server simply refuses an
unreasonable list).

**Test that proves it:** Post 5,000 ids and assert a fast `invalid_field`; time
a full group's add while a concurrent send runs.

**Overlap:** AUD-4b-1 (same handler).

---

### AUD-4b-6 A group send authorizes and snapshots the roster outside the delivery transaction

**Severity:** P3
**Confidence:** confirmed
**Where:** [module.dart:1084-1111](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L1084) (role, settings and roster read), delivery tx [module.dart:1207](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L1207).

**What:** The sender's membership and role, the group settings and the full
roster are read in autocommit statements; charging and the limiter follow; the
delivery transaction starts later and re-reads nothing. A member removed in
the window still delivers one message to every device in the snapshot taken
before removal, and a member added in the window receives nothing.

**Trigger:** A removal (or a ban) races a send from the same member.

**Evidence:** `_requireMember` and `_store.members` at 1085-1093 run on
`context.db`, and the only transaction is the delivery block at 1207-1227.
`messaging.deliver` filters inactive *devices*, not membership. The same
pattern exists in `_setState`/`_setSettings` but those take the row
`FOR UPDATE`.

**Impact:** A removed or banned member's last send is accepted and fanned out
after removal; the roster change and the message cross. Low frequency, but the
invariant "removal stops the next send" is not enforced at the moment that
matters.

**Fix sketch:** Lock the group row (`FOR UPDATE` like the other mutations) or
re-check the sender's role inside the delivery transaction; the roster read
should come from that same transaction. The limiter/charge can stay outside if
the group check is repeated inside.

**Test that proves it:** Remove a member and concurrently send from their
device; assert the send is refused (or the message never reaches devices after
the removal commits).

**Overlap:** AUD-3-6, AUD-4b-3.

---

## Coverage gaps

- `data/group_store.dart` (ordering of `members()` for the owner-succession
  rule, invite-link expiry, `remote_devices`, join-request limits) and
  `federation.dart` (S2S actor/device trust, sync/fan-out jobs): sweep 4c.
- No server tests were run.
- The client's retry behaviour (whether it always sends `Idempotency-Key` for
  group sends) was not checked in `helix_remote_api`/engine; AUD-4b-4 assumes
  the header can be absent, which the server permits.
