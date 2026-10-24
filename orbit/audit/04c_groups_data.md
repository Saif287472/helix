# Sweep 4c — groups data and federation

`group_store.dart` is the SQL for the groups module. `federation.dart` carries
groups across servers: S2S actions, roster syncs, message fan-out and the
member server's cached snapshot. Together they hold the invariants that 4b's
handlers rely on.

Findings: **P2 1, P3 5**. No P0/P1.

## Files read

| File | Lines |
|---|---|
| `helix_remote/server/lib/src/modules/groups/data/group_store.dart` | 640 |
| `helix_remote/server/lib/src/modules/groups/federation.dart` | 607 |
| Cross-checks: `people.mayAddToGroup` (people/module.dart:771-779), protocol `GroupRole.canAdminister`, 4b handler line numbers already read | ~40 |

## What is sound

- S2S actions verify the actor's domain against the calling server
  ([federation.dart:178-183](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L178)).
- Reported devices are filtered twice: not a local device, and not already
  reported for another account
  ([federation.dart:238-248](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L238)).
- A sync is accepted only from the group's cached home, and only a home may
  fan a message out
  ([federation.dart:276-281](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L276),
  [federation.dart:388-391](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L388)).
- A message relayed to a member server names a sender in the cached snapshot
  and spreads only to that server's active member devices
  ([federation.dart:407-429](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L407)).
- The member server checks every new local account in a snapshot against
  either a join marker or an adding member's rights, privacy and blocks
  ([federation.dart:294-338](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L294)).

---

### AUD-4c-1 The roster cache version check is not atomic, so an older snapshot can overwrite a newer one

**Severity:** P2
**Confidence:** likely
**Where:** [federation.dart:274-293](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L274) (read, compare), [federation.dart:342-349](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L342) (save); [group_store.dart:500-547](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/data/group_store.dart#L500) (`remoteGroup`, `saveRemoteGroup`).

**What:** `_receiveSync` reads the cached `remote_groups` row, compares
`sync.rosterVersion <= cached.version`, then replaces the row and the whole
`remote_members` list. The read takes no row lock and the upsert has no
version predicate, so two syncs that overlap both see the old version and the
later commit wins regardless of its version. Two jobs for the same group are
easy to produce: every roster change enqueues its own sync job
([federation.dart:35-50](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L35)),
and `_runSync` reads the current row when it runs
([federation.dart:59-68](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L59)),
so a backlog of jobs sends v5 and v6 back to back.

**Trigger:** Two `groups.sync` deliveries for one group reach a member server
concurrently (job retry, two roster changes, two nodes). The connection
carrying v6 commits before v5's.

**Evidence:** The version read at 275 is a plain `SELECT`; the guard at 291 is
in Dart, outside any row lock; `saveRemoteGroup` is an unconditional
`ON CONFLICT DO UPDATE`
([group_store.dart:532-537](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/data/group_store.dart#L532)).
The transaction serialises nothing.

**Impact:** The cached snapshot and `remote_members` regress: a member removed
in v6 is added back locally, so `_receiveMessage` and `_deliverOwnSend` deliver
group messages to that account's devices again until the next sync. Conversely
a newly added member is dropped from local fan-out (their server may still
deliver their own copy). This is a confidentiality-adjacent regression, not
just stale UI.

**Fix sketch:** Make the version check part of the write: `SELECT ... FOR
UPDATE` on the `remote_groups` row (or an upsert guarded by
`WHERE $s.remote_groups.roster_version < excluded.roster_version RETURNING 1`,
replacing `remote_members` only when it returns a row). The event delivery
should also be gated on the version advancing (see AUD-4c-5). No wire change.

**Test that proves it:** Run two `receiveSync` calls (v5, v6) with a barrier
between the read and the write; assert the final cache is v6 and the removed
member is absent, in both commit orders.

**Overlap:** AUD-4c-5.

---

### AUD-4c-2 `remote_devices` rows are never cleaned when a group is deleted

**Severity:** P3
**Confidence:** confirmed
**Where:** [module.dart:551-568](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L551) (`_delete`), [group_store.dart:264-268](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/data/group_store.dart#L264) (`deleteGroup`), cleanup only in [module.dart:696-698](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L696) (`_remove`).

**What:** The home server stores other servers' reported devices in
`remote_devices`, keyed by account with no group reference. `_remove` calls
`forgetRemoteDevicesIfUnused` when a remote member is removed, but deleting a
group deletes only the `groups` row (members cascade); the remote accounts'
device rows stay. They are also never swept for accounts that left every group
by a path other than `_remove` (e.g. a group deleted while they were in it).

**Trigger:** Delete a group whose remote members are in no other group on this
server.

**Evidence:** `deleteGroup` is a single `DELETE FROM groups`
([group_store.dart:264-268](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/data/group_store.dart#L264));
`remote_devices` has no foreign key to a group
([group_store.dart:69-74](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/data/group_store.dart#L69)).
`forgetRemoteDevicesIfUnused` is invoked only from `_remove`
([module.dart:696-698](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L696)).

**Impact:** Device UUIDs of remote accounts linger indefinitely in the
metadata store after the reason to hold them is gone; the table grows with
every deleted group and every churned remote member. `remoteDeviceTaken` keeps
reserving those ids for the account, which is harmless for fresh UUIDs but
misleading after a device is retired.

**Fix sketch:** In `_delete`, collect the remote members before deleting and
call `forgetRemoteDevicesIfUnused` for each (or add a periodic sweep
`DELETE FROM remote_devices d WHERE NOT EXISTS (members ...)`). No wire change.

**Test that proves it:** Delete a group with one remote-only member; assert
`remote_devices` has no row for that account.

**Overlap:** AUD-4c-6, S2.

---

### AUD-4c-3 `joined_at` is the transaction timestamp and `members()` has no tiebreak, so "oldest" is arbitrary

**Severity:** P3
**Confidence:** confirmed
**Where:** schema [group_store.dart:25-31](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/data/group_store.dart#L25) (`DEFAULT now()`), query [group_store.dart:152-165](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/data/group_store.dart#L152); succession [module.dart:711-717](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L711).

**What:** `now()` is the transaction start time, so every member inserted in
one transaction (the creator plus everyone in `CreateGroupRequest`, or a batch
add) shares the exact same `joined_at`. `members()` orders by `joined_at`
alone, so their relative order is whatever PostgreSQL returns. Owner
succession picks `firstWhere(admin, orElse: first)` from that list; MODULE.md
promises "the oldest admin (or else the oldest member)".

**Trigger:** A group created with several members loses its owner immediately
(or the owner leaves later); two admins have identical `joined_at`.

**Evidence:** The column default and the single-column `ORDER BY`
([group_store.dart:154](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/data/group_store.dart#L154));
`_remove`'s heir selection at 711-717. The same unordered list is returned in
every `Group` payload, so member order can change between reads.

**Impact:** Ownership can pass to an unintended member, and the outcome is not
reproducible (it can differ between nodes/reads). The roster order in the
encrypted client view also jitters.

**Fix sketch:** Add a total order: `ORDER BY joined_at, account_id` for
stability, and for "oldest" use a monotonic `joined_seq bigserial` (or at
least order by `(joined_at, joined_at::text? no)`. A `bigserial` column is the
clean fix (one migration). Wire unchanged; clients get a stable list.

**Test that proves it:** Create a group with three members in one call,
remove the owner, and assert the same heir on repeated runs and re-reads.

**Overlap:** None.

---

### AUD-4c-4 An S2S action's `actorDevice` is trusted without checking it belongs to the actor

**Severity:** P3
**Confidence:** likely
**Where:** [federation.dart:187-192](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L187); used by [module.dart:1074-1079](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L1074) and [module.dart:1131-1147](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L1131); relayed messages [federation.dart:392-395](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L392).

**What:** `_receiveAction` builds `_Actor('${actor.id}@$domain',
action.actorDevice)` after checking only that the account's domain matches
the caller. It never checks that `actorDevice` is a device of that account, is
not a device of this server, or is not reported for another account — the
`devices` action does apply exactly those checks
([federation.dart:238-248](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L238)),
but `send` does not. A relayed `S2SGroupMessage.senderDevice` is likewise only
UUID-validated
([federation.dart:392-395](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L392)).

**Trigger:** A hostile (or compromised) member server calls `send` for one of
its users with `actorDevice` set to a device id of another member, including a
local device of the home server.

**Evidence:** The digest excludes exactly `senderDevice`
([module.dart:1104-1116](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L1104)),
and `EnvelopeSender(device: senderDevice)` is what every recipient sees
([module.dart:1153-1161](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L1153)).
The client computed the digest and the home cannot tell whether the named
device exists.

**Impact:** A member server can withhold a message from one chosen local
device (it is excluded from the fan-out) and attach another account's device
id as the sender's device in every member's envelope. Both are small,
targeted integrity violations inside the sender-key model; neither lets it
read anything.

**Fix sketch:** When `actorDevice != null`, run the same predicate as
`_foreignDevices`: reject a local device or a device reported for another
account; for `send`, require it to be already reported for the actor (or
accept and record it under the actor). Apply the same to
`S2SGroupMessage.senderDevice` on receipt, where the sender is known.

**Test that proves it:** An S2S send naming a local device as `actorDevice` is
refused (`invalid_field`/`forbidden`); the local device still receives the
message.

**Overlap:** AUD-4c-1 (federation trust), identity's device ownership.

---

### AUD-4c-5 Roster syncs are not coalesced and a replayed sync re-delivers its event

**Severity:** P3
**Confidence:** confirmed
**Where:** [federation.dart:35-50](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L35) (`_queueSyncs`, no dedupe key), [federation.dart:291-293](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L291) (older/repeated version keeps cache), [federation.dart:352-371](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L352) (event delivered regardless).

**What:** Every roster change enqueues a full-snapshot sync job for every
server with members; there is no coalescing key, so a group that changes ten
times in a second queues ten snapshot jobs per peer. On the receiving side, a
repeated or older version keeps the cached snapshot but still fans the
attached `roster_change` out to every local member device, creating new
mailbox rows each time. A sync whose answer is lost but whose delivery
succeeded is retried (`RelayUnavailable` propagates,
[federation.dart:70-76](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L70)),
so the same event is delivered again.

**Trigger:** A flapping membership (AUD-4b-1) or a slow/dead peer with a
backlog of jobs; a dropped answer after a processed sync.

**Evidence:** `enqueue` at 37-49 passes no `dedupeKey`; the member server
applies the snapshot only when the version advances but delivers the event
unconditionally at 359-370. `messaging.deliver` allocates a fresh id/rows per
call.

**Impact:** Job-queue growth proportional to roster churn (each job carries
the whole roster), and duplicate roster events in members' mailboxes with the
usual quota pressure. On a dead peer the backlog is bounded only by
`maxAttempts`, but the queue itself can grow without bound while the peer is
down.

**Fix sketch:** Coalesce per (group, domain): keep one pending job whose
runner reads the latest snapshot (a "latest wins" key, not a permanent dedupe
key — see AUD-1b-1). On the member server, record the last delivered
`roster_version` (e.g. `remote_groups.last_event_version`) and skip the event
when the version did not advance. Schema: one column; wire unchanged.

**Test that proves it:** Flap a group 100 times with one peer offline; assert
at most a couple of pending sync jobs. Deliver the same sync twice; assert one
roster_change row per device.

**Overlap:** AUD-4b-1, AUD-1b-1, AUD-4c-1.

---

### AUD-4c-6 Leaving remote groups depends on a one-shot job that gives up silently

**Severity:** P3
**Confidence:** likely
**Where:** [federation.dart:541-552](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L541) (`_leaveRemoteGroups`), [federation.dart:572-606](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L572) (`_runLeave`/`_runAction`), job limits [jobs](file:///J:/Projects/helix/helix_remote/server/lib/src/platform/jobs/jobs.dart).

**What:** Deleting a local account removes its remote-group memberships by
enqueuing a `groups.leave` job per group with `maxAttempts: 12` and no
dedupe. `_runAction` logs a 4xx answer and treats it as final; a transport
failure retries until the attempts run out. The member server drops its local
cache immediately (`removeRemoteMember`), so nothing remains to retry the
leave. After the last attempt the home server still lists the account in
`members` and its devices in `remote_devices`.

**Trigger:** The home server is unreachable for the retry window during an
account deletion, or refuses the leave (e.g. the job's actor no longer exists
there).

**Evidence:** 541-552 queues the job and 551 deletes local state in the same
transaction; 588-606 logs `status >= 400` and returns. Job death is the
AUD-1b-1 mechanism. On the home, the only cleanup is `_remove`, which the
leave would have invoked.

**Impact:** A deleted account remains in other servers' rosters indefinitely;
the home keeps its account id and reported device ids, and group fan-outs keep
being addressed to that server (which silently has no member). This
contradicts the MODULE's "account deletion ... queues groups.leave" guarantee
in the failure case.

**Fix sketch:** Keep a durable "leaving" marker (account, home, group) and a
periodic job that retries until the home answers success or a terminal
"not a member"; do not rely on the outbox's 12 attempts alone. Alternatively,
the home expires remote members whose server has not synced devices for N
days — but that risks removing active members, so the retry marker is safer.
Schema: one small table or a status column; no wire change.

**Test that proves it:** Make the relay fail past `maxAttempts`; assert the
leave is retried by the reconciliation run and eventually applied.

**Overlap:** AUD-1b-1, AUD-4c-2, S2.

---

## Structural proposal

### S2 — Federation state has four lifetimes and no reconciliation

**Current shape.** `remote_groups` (cache), `remote_members` (local accounts in
it), `remote_devices` (what each member's server reported) and `remote_joins`
(join consent) are each written by a different event and cleaned by a
different one: syncs replace the first two, a `devices` action replaces the
third, `_remove` forgets the third, account deletion clears the fourth. A
missing cleanup has no symptom until the data is stale (AUD-4c-2, AUD-4c-6),
and nothing detects a cache that stopped advancing.

**Hazard.** Every lifetime is an invariant maintained by call sites, not by
the data model: group deletion, account deletion, a dead peer and a lost answer
each need a different path to be correct, and none is observable. At the
current size the tables stay small; after federation is enabled they grow with
churn and a deleted account can persist as a member on another server.

**Proposed shape.** One `reconcile` periodic job (per node, leased) that (a)
drops `remote_devices` rows for accounts with no membership, (b) retries
pending leaves, (c) records and exposes the age of each `remote_groups` cache
and `remote_devices` report, and (d) prunes `remote_joins` older than their
lifetime. Writes stay where they are; the job only repairs drift. Add a
`SELECT ... FOR UPDATE` version-guarded write for the cache (AUD-4c-1) so the
job never fights a live sync.

**Migration path.** Add the job and the age columns/indices first (expand);
run it in report-only mode for a release; then enable deletions (migrate).
No client or wire change; the metrics tell the operator whether churn is
bounded.

**Risk.** A reconciliation job that deletes remote devices for an account
whose membership is temporarily missing (e.g. a snapshot was rejected) could
cause message loss for that member until the home re-reports; it should only
delete rows that are provably unused (`NOT EXISTS members`, as the existing
helper does) and never touch a group's current members.

**Rough size.** ~200 lines (job, queries, metrics), one migration for indices
and age columns.

## Coverage gaps

- Whether the federation module authenticates the calling domain (S2S
  signature/peer binding) is the federation module's job (sweep 6); 4c assumes
  the `domain` passed to `GroupsApi` is verified.
- The outbox's lease/dead-letter behaviour is AUD-1b-1 (sweep 1b); this file
  only describes the consequences.
- No server tests were run.
