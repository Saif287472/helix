# Sweep 6 — calls + federation

Scope: `server/lib/src/modules/calls/{module.dart,api.dart,MODULE.md}`,
`server/lib/src/modules/federation/{module.dart,config.dart,peers.dart,data/
federation_store.dart,MODULE.md}`, plus cross-checks: the call-signal parts of
messaging (`checkDevices`, block policy), the route catalog, platform HTTP
limits (`BodyBudget`, default body cap, global limiter), the ephemeral store,
and `server/test/modules/calls_test.dart`.

Files read: calls 633 + 33 + 61, federation 592 + 72 + 392 + 97 + 85, ~200
lines of cross-checks ≈ 2,165 lines. Over budget; the two modules are one unit
each and the sweep was split into a single file because both halves feed the
same relay surface.

## What is sound

- Federation transport is careful: TLS with the certificate checked against
  the domain, address pinning inside `connectionFactory` (no DNS-rebinding
  window), no proxy, no redirects, and a private/link-local refusal list that
  also judges IPv4 embedded in IPv6 forms (peers.dart:187-305).
- The S2S signature input binds server, timestamp, method, path+query and a
  body hash; skew is ±5 min and each signature is accepted once through the
  shared ephemeral store (federation/module.dart:437-484). The allow list is
  enforced for every resolve, inbound included (peers.dart:66-80).
- A peer's identity document must name the domain, carry a 32-byte key and
  keep `api_base` on the same scheme and authority, and a failed lookup is
  remembered for a minute so forged headers cannot hammer a domain
  (peers.dart:96-173).
- Inbound actors are bound to the calling domain for calls and groups
  (calls/module.dart:438-444; groups/federation.dart:187-192), and keys
  answers are limited per server and per (server, account)
  (federation/module.dart:209-229).
- Call offers require the complete callee device list (`device_list_stale`
  otherwise), blocked callers are refused with 403, other signals are dropped
  for those accounts, and a pending row can only be refreshed or cleared by
  the caller or the callee (calls/module.dart:321-359, 368-423, 477-508;
  tests calls_test.dart:261-299).
- TURN credentials follow the coturn REST scheme with a fresh random id per
  request and a one-hour expiry, and the URL list is validated at startup
  (calls/module.dart:31-52, 175-205).
- Federation's config and peer cache are small and readable; nothing caches a
  credential, and the signing seed is created once, race-safely
  (federation_store.dart:45-59).

## Findings

### AUD-6-1 Call metrics store an unbounded free-text field per row: ~9 GB per account over the retention window, with no owner

**Severity:** P2
**Confidence:** confirmed
**Where:** [calls/module.dart:562](/J:/Projects/helix/helix_remote/server/lib/src/modules/calls/module.dart#L562)
(`_metrics` validates only `call_id`; `outcome` is inserted as-is),
[calls/module.dart:129](/J:/Projects/helix/helix_remote/server/lib/src/modules/calls/module.dart#L129)
(`call_metrics.outcome text`, no length check, and **no account column**),
[calls/module.dart:96](/J:/Projects/helix/helix_remote/server/lib/src/modules/calls/module.dart#L96)
(100 reports per account per day; keyed by `q.device.accountId` at 567),
[calls/module.dart:162](/J:/Projects/helix/helix_remote/server/lib/src/modules/calls/module.dart#L162)
(the route takes the default 1 MiB body cap — platform/http/routes.dart:99),
[calls/module.dart:147](/J:/Projects/helix/helix_remote/server/lib/src/modules/calls/module.dart#L147)
(cleanup every 5 minutes with `created_at < now() - 90 days` and no index on
`created_at`).
**What:** `CallMetricsRequest.outcome` is `String?` (protocol
modules/calls.dart:203-213) and the handler stores it in a `text` column with
no cap. With the 1 MiB body limit and 100 reports per account per day, one
account can write up to 100 MiB of rows per day and hold ~9 GB for the 90-day
retention — about 9,000 rows per account, exactly the count MODULE.md says is
"kept" (calls/MODULE.md:39-43), but with no bound on their size. The table has
no account column, so these rows cannot be deleted with the account and cannot
be attributed to one from the admin console.
**Trigger:** an authenticated account (or one buggy client that sends a whole
SDP/session state in `outcome`) loops `POST /v1/calls/metrics` 100 times a
day with a ~1 MiB `outcome`.
**Evidence:** insert at 568-582 has no truncation; the model exposes the field
as a plain string; the per-day policy (96-100) counts requests, not bytes; the
schema (129-140) has `created_at` unindexed, so the five-minute sweep
(151-154) scans the whole table — which now includes those gigabytes — every
five minutes, on the shared database that the storage budget measures. No
`storage.check()` is made on this route (contrast media/backup).
**Impact:** cheap, slow database growth that eventually flips the
server-wide storage budget (`quota_exceeded` for every media/backup upload)
and makes housekeeping progressively more expensive; the data is opaque
client text the server keeps 90 days and cannot delete per account, against
the "keyed by call id only" minimalism in MODULE.md.
**Fix sketch:** server only, no wire change. Cap `outcome` (enum wire values
or ≤64 bytes) in the handler, add an account column (or a `reporter` hash) so
rows can be purged on account deletion, add an index on `created_at`, and
either lower the daily count or charge the storage budget before insert.
**Test that proves it:** post a 100 KiB `outcome` and assert
`invalid_field`/`payload_too_large`; delete the account and assert its metrics
rows are gone.
**Overlap:** AUD-5-3 (byte-vs-row quota), AUD-1b-3 (missing hot-path index
tests), sweep 1c (storage budget).

### AUD-6-2 Federation reads peer responses with no size cap, and the identity fetch runs before authentication

**Severity:** P2
**Confidence:** confirmed
**Where:** [peers.dart:130](/J:/Projects/helix/helix_remote/server/lib/src/modules/federation/peers.dart#L130)
(`http.Response.fromStream(...).timeout(5 s)` then `response.body` — the whole
identity document is buffered),
[peers.dart:144](/J:/Projects/helix/helix_remote/server/lib/src/modules/federation/peers.dart#L144)
(`JsonReader.decode(response.body)`),
[module.dart:466](/J:/Projects/helix/helix_remote/server/lib/src/modules/federation/module.dart#L466)
(`_verify` → `peers.resolve(server)` happens before the signature is
verified),
[peers.dart:370](/J:/Projects/helix/helix_remote/server/lib/src/modules/federation/peers.dart#L370)
(same unbounded `Response.fromStream(...).body` for every API answer),
[config.dart:37](/J:/Projects/helix/helix_remote/server/lib/src/modules/federation/config.dart#L37)
(the only bound is a 5 s timeout).
**What:** Every outbound peer read accumulates the entire response into memory
with a time limit but no byte limit. Two paths reach it: (a) `client.call`,
which reads whatever a peer answers to messages/keys/calls/groups; (b) the
identity document fetch, which any unauthenticated caller can trigger by
sending S2S-looking headers (`x-helix-s2s-server: <valid public domain>`, any
64-byte signature, a current timestamp) to an S2S route while federation is
on — the signature is checked *after* the fetch. A domain the attacker owns
can stream for the full 5 s.
**Trigger:** with federation enabled, send one S2S-signed-shaped request per
allowed second naming a domain that serves a huge `/.well-known/helix-server`
body; or have any allowed peer answer a normal S2S call with a huge body.
**Evidence:** 130-135 and 370-380 both call `http.Response.fromStream` before
any inspection; `JsonReader.decode` runs afterwards; `_verify` calls
`peers.resolve(server)` at 466-474 and only then verifies the signature. The
global limiter is 10 req/s per IP (platform/http/pipeline.dart:23-27), so one
IP can hold ten such reads in flight; the node's `BodyBudget` protects
*inbound* bodies only, not outbound reads.
**Impact:** memory exhaustion of the node from an unauthenticated source when
federation is on (and from any federated peer always) — the process dies, all
sessions drop, and the server restarts without a circuit breaker. It is the
outbound twin of AUD-1c-1: no request budget.
**Fix sketch:** server only. Add a capped reader (`readJsonCapped(stream,
maxBytes)`) used by `_fetch` (≤64 KiB) and `client.call` (≤8 MiB, matching the
inbound batch cap); exceeding it becomes `PeerUnavailable`. Alternatively
check the signature's `server` shape and the down-cache before the first
fetch, but the byte cap is the actual fix.
**Test that proves it:** a fake peer whose identity endpoint streams 2 MB
must yield `PeerUnavailable`/a refused document without allocating 2 MB
(expose the cap constant and assert the read stops).
**Overlap:** AUD-1c-1 (no S3 timeout), AUD-1a-1 (body budget), S4 below.

### AUD-6-3 `PUT /calls/{id}/state` has no policy and fans out to every device of the account

**Severity:** P3
**Confidence:** confirmed
**Where:** [calls/module.dart:158](/J:/Projects/helix/helix_remote/server/lib/src/modules/calls/module.dart#L158)
(`setCallState` and `pendingCalls` are registered with no `rateLimit`),
[calls/module.dart:512](/J:/Projects/helix/helix_remote/server/lib/src/modules/calls/module.dart#L512)
(`_state` reads all of the account's devices, deletes pending rows, then sends
an ephemeral `end` to every other device),
[calls/module.dart:525](/J:/Projects/helix/helix_remote/server/lib/src/modules/calls/module.dart#L525)
(the fan-out is one `deliverEphemeral` over all other devices).
**What:** Every other call route has a per-principal policy (offers 30/10 min,
signals 240/min per device, metrics 100/day, TURN 10/h); `state` and
`pending` get only the 600-burst/10-per-s per-IP limiter. `state` costs an
`activeDevices` query, a `pending_calls` delete and an O(devices) ephemeral
fan-out; with no device cap (AUD-2-2) a client can call it ten times a second
with any call id, so its own device list (up to 1,100) becomes ~11k delivery
attempts per second of node work.
**Trigger:** an authenticated device loops `PUT /v1/calls/<random id>/state`;
more effective on an account with many devices.
**Evidence:** registration at 158-166; `_limit` is used in `_signal`,
`_turn` and `_metrics` but not in `_state` (512-535) or `_pending`
(537-560); `deliverEphemeral` is O(devices) round trips (AUD-3-1).
**Impact:** an authenticated account can turn the shared per-IP request
budget into a large multiple of database and bus work, degrading other users
on the node; no message content or cross-account effect.
**Fix sketch:** server only. Add a policy for `state` (e.g. 60/min per
account) and optionally one for `pending`, and skip the fan-out when the
account has a single device.
**Test that proves it:** exhaust `calls.state:<account>` and assert
`rate_limited`; assert a single-device account performs no ephemeral delivery.
**Overlap:** AUD-2-2, AUD-3-1, AUD-5-6 (same "route without a policy" shape).

### AUD-6-4 A non-offer call signal is delivered to any addressed device; only pending-row writes are party-scoped

**Severity:** P3
**Confidence:** likely
**Where:** [calls/module.dart:321](/J:/Projects/helix/helix_remote/server/lib/src/modules/calls/module.dart#L321)
(`_deliverLocal`: `checkDevices` and the block check, then a delivery to every
addressed payload),
[calls/module.dart:335](/J:/Projects/helix/helix_remote/server/lib/src/modules/calls/module.dart#L335)
(the completeness/authorization check runs only for `offer`),
[calls/module.dart:361](/J:/Projects/helix/helix_remote/server/lib/src/modules/calls/module.dart#L361)
(the ephemeral delivery is made for every kind),
[calls/module.dart:408](/J:/Projects/helix/helix_remote/server/lib/src/modules/calls/module.dart#L408)
(only `end` and `offer` touch pending rows; nothing checks that the sender is
the caller or the callee).
**What:** For `update`/`end` the server takes the client's recipient list at
face value: any signed-in account may address any device ids it names, and the
signal is delivered with the attacker as `from`. The party rule is enforced
only for the rows a third party cannot see (pending offers), which the test
suite calls "only the parties can clear or replace a pending offer" — but the
signal itself is still delivered, so a third party that knows a call id and a
victim device id can inject an `end` (or `update`) into a live call. Whether
the call actually drops depends on the engine ignoring signals whose `from`
is not the call peer (sweep 12).
**Trigger:** an account that learned a call id and device id (both parties in
a shared group/call, or a compromised peer) sends `kind: end` with the victim
device in `recipients`.
**Evidence:** `_deliverLocal` (321-368) delivers before it looks at kind;
`checkDevices` is offer-only (335-342); `_endPending` is party-scoped
(477-508), and the test at calls_test.dart:281-298 confirms a third party's
`end` is *accepted* and merely does not clear the pending row. The sealed
payload is no defence: a third party can seal a valid `CallSignalPayload.end`
to any device under its own session.
**Impact:** a call-hijack primitive if the client trusts the envelope's call
id alone; at minimum an unsolicited-signal injection into another person's
call UI. The server's documented model ("the server sees the call id, the
parties") does not hold for the delivery path.
**Fix sketch:** client is the real gate: the engine must drop signals whose
`from` is not the peer of that call (sweep 12). Server hardening if the engine
cannot: require, for `end`/`update` on a call with pending rows, that the
sender is the caller or a callee device; and give the server a way to know the
callee of an answered call (it does not store one). No wire change either way.
**Test that proves it:** carol sends `end` to bob's device for alice's call;
assert the engine never ends the call (engine test), or assert the server
refuses once the party rule is added.
**Overlap:** AUD-4c-4 (trusted `actorDevice`), sweep 12 (engine trust).

### AUD-6-5 TURN credentials are capped per device, so one account can mint many one-hour relay credentials

**Severity:** P3
**Confidence:** likely
**Where:** [calls/module.dart:78](/J:/Projects/helix/helix_remote/server/lib/src/modules/calls/module.dart#L78)
(`_turnLimit` is `RateLimitPolicy.per('calls.turn', 10, 1 h)`),
[calls/module.dart:187](/J:/Projects/helix/helix_remote/server/lib/src/modules/calls/module.dart#L187)
(charged against `q.device.deviceId`),
[calls/module.dart:188](/J:/Projects/helix/helix_remote/server/lib/src/modules/calls/module.dart#L188)
(each credential lives one hour).
**What:** The relay-credential budget is per device and the username embeds a
fresh random id, so coturn's per-user quotas do not bind across credentials.
With no per-account device cap (AUD-2-2), one account can hold 10 × devices
credentials per hour, each valid for an hour, i.e. an account is a
multiplier on the shared TURN relay rather than a single client of it.
**Trigger:** register many devices (or compromise them) and fetch TURN
credentials from each; use the relay for arbitrary traffic for the hour.
**Evidence:** the limit key is the device (187); every request yields a new
username and credential (189-196); the expiry is one hour (75); there is no
per-account policy anywhere in `_turn` (180-205).
**Impact:** abuse of the operator's relay (bandwidth, allocation slots) by one
account, and it defeats the intent of the 10-per-hour cap; no data-plane
impact on Helix itself.
**Fix sketch:** server only. Add a second, per-account policy (e.g. 20/h) on
top of the per-device one; no wire change.
**Test that proves it:** fetch 10 credentials from one device and the 11th is
`rate_limited`; with a per-account cap, a second device's 21st is too.
**Overlap:** AUD-2-2 (no device cap), AUD-6-3 (same missing-policy shape).

### AUD-6-6 Inbound S2S bodies are rate-limited per request, never per byte

**Severity:** P3
**Confidence:** confirmed
**Where:** [federation/module.dart:86](/J:/Projects/helix/helix_remote/server/lib/src/modules/federation/module.dart#L86)
(`_messagesLimit` = 3,000 requests/min per server),
[federation/module.dart:143](/J:/Projects/helix/helix_remote/server/lib/src/modules/federation/module.dart#L143)
(messages and group messages accept 8 MiB bodies),
[federation/module.dart:204](/J:/Projects/helix/helix_remote/server/lib/src/modules/federation/module.dart#L204)
(each request is decoded whole),
[federation/module.dart:157](/J:/Projects/helix/helix_remote/server/lib/src/modules/federation/module.dart#L157)
(the three group S2S routes reuse the request-count limits with 8 MiB / 1 MiB
bodies),
[groups/federation.dart:35](/J:/Projects/helix/helix_remote/server/lib/src/modules/groups/federation.dart#L35)
(the home fans one batch per peer per change, so a peer's inbound volume is
driven by the home, not bounded by it).
**What:** A federated peer's budget is requests, not bytes. The largest inbound
bodies are 8 MiB and are JSON-decoded per request, so an allowed peer can make
the node parse up to tens of GB per minute by sending the largest body at the
request rate; the 256 MiB `BodyBudget` bounds concurrent memory, not CPU.
Device-facing sends are charged per stored unit (`chargeStored`), S2S sends are
not.
**Trigger:** an allowed (possibly compromised) peer sends 8 MiB group fan-outs
or message batches at 50/s.
**Evidence:** the three limits (86-105) have no byte dimension; the 8 MiB caps
are at 147, 163 and 171; `_inboundMessages`/`_inboundGroupMessage` decode the
whole body before any accounting (204, 241-248). Nothing in the S2S path
charges bytes the way messaging's `_accept` charges local senders
(messaging/module.dart:325-345).
**Impact:** a single federated peer can occupy the node's CPU and starve
local users; the peer is authenticated, so this is a trust-boundary calibration
issue rather than an open door.
**Fix sketch:** server only. Charge an inbound byte budget per server (a
token bucket in the rate limiter keyed by `server:<domain>`, units = body
bytes) before decoding, or lower body caps for fan-out and require more
requests. No wire change.
**Test that proves it:** send N 8 MiB batches and assert the byte budget
produces `rate_limited` before the CPU-bound decode.
**Overlap:** S4, AUD-3-1 (local equivalent is charged).

## Structural proposal

### S4 Federation I/O has no bound at either end; one byte budget should sit on the S2S surface

**Current shape:** inbound S2S has per-server request counts (federation/
module.dart:81-105) and a node-wide concurrent-body budget; outbound federation
has a 5-second timeout and no response size cap (peers.dart:130-135,
370-380). S2S bodies are up to 8 MiB and are decoded whole. Nothing charges
bytes to a peer, and the identity fetch that authenticates a peer runs before
its signature is checked.
**Hazard:** capacity on a shared node is decided by request count, not work,
so an allowed peer can spend unbounded CPU (AUD-6-6) and an unauthenticated
caller can make the node buffer unbounded memory from a domain it controls
(AUD-6-2). Both bypass the careful accounting that exists on the device-facing
side (`BodyBudget`, `chargeStored`, the storage budget).
**Proposed shape:** one `FederationBudget` (a `RateLimiter` token bucket per
`server:<domain>` with byte units, plus an unauthenticated
`fedfetch:<domain>` bucket) used at three points: before decoding an inbound
S2S body, before buffering an outbound response (with hard caps of 64 KiB for
identity documents and 8 MiB for API answers), and on the identity-fetch path.
Per-domain concurrency capped at 1–2.
**Migration path:** expand only — add the buckets with generous defaults
(inbound 64 MiB/min per peer, outbound 8 MiB/response) and the capped reader;
no schema or wire change. Tune downward if metrics show headroom.
**Risk:** a busy peer's legitimate fan-out could be throttled; start generous
and surface the bucket in metrics before tightening. The capped reader turns
an oversized answer into `PeerUnavailable`, which existing relay retries
already handle.
**Rough size:** ~120 lines (a small reader helper, two bucket keys, tests with
a fake peer), no migrations.

## Coverage gaps / not measured

- Federation was not exercised live (no server started, no peer); every S2S
  path was read only. The `group_*` S2S handlers were covered in sweep 4c and
  only referenced here.
- Whether a third-party `end` actually drops a call (AUD-6-4) is decided in
  the engine; sweep 12 must confirm the `from` check.
- `calls.push` delivery, push token handling and platform push were covered in
  sweep 1c and sweep 2; not re-audited.
- The rate limiter's bucket semantics (capacity/refill) are platform code from
  sweep 1a; this sweep assumes a bucket keyed by principal works as named.
