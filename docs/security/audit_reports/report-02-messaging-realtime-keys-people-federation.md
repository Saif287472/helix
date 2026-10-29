# Audit report 2 - Messaging, realtime, keys, people, federation (verbatim)

External static audit; saved as received. Triage and fixes are in
`docs/security/AUDIT_LOG.md`. The auditor may be wrong: every claim is checked
against the code before anything is changed.

---

### Orbit Server Security Audit

Scope: Messaging, realtime WebSocket, keys, people, federation, and their supporting event bus, ephemeral store, and relevant persistence code.

Method: Read-only source inspection of the supplied extracts. No runtime testing, traffic capture, Git history, or deployment configuration was available.

I found authorization and delivery-consistency failures, a federation key-pinning failure, and resource/privacy weaknesses. The findings below distinguish paths demonstrated by the code from behavior that still depends on runtime conditions.

### Critical

### F-1 Federation silently trusts a changed peer signing key

* Severity: Critical
* Confidence: Confirmed
* Where: `server/lib/src/modules/federation/peers.dart:169-211`; `server/lib/src/modules/federation/data/federation_store.dart:76-88`; `server/lib/src/modules/federation/module.dart:496-518`
* Breaks: A peer's long-term key is pinned on first use; changes must be detected and surfaced, not silently accepted.

Path

* Orbit has previously authenticated peer `example.org` using public key K1, which is stored in `federation.peers`.
* An attacker capable of replacing that domain's HTTPS identity document publishes K2 and signs an S2S request with K2.
* The receiving server first fails to verify the request against cached K1.
* At `module.dart:504`, it refreshes the peer identity. `peers.dart:193` saves K2, replacing K1 in PostgreSQL.
* At `peers.dart:206-211`, the mismatch only increments a metric and logs a warning; K2 is nevertheless returned.
* At `module.dart:505`, the attacker's signature is verified against K2. The request is accepted as originating from `example.org`.

A hostile replacement key can therefore impersonate the federated server and inject S2S messages attributed to accounts on that server, without possessing K1.

Evidence

`peers.dart:188-211`:

```dart
fetched = await _fetch(domain);
await store.savePeer(db, fetched);
...
if (cached != null &&
    !constantTimeEquals(cached.publicKey, fetched.publicKey)) {
  keyChanges?.inc();
  log.warn('peer_key_changed', {'peer': domain});
}
return fetched;
```

`federation_store.dart:78-81`:

```dart
'ON CONFLICT (domain) DO UPDATE SET public_key = excluded.public_key, '
'api_base = excluded.api_base, fetched_at = excluded.fetched_at'
```

`module.dart:502-505`:

```dart
var peer = await peers.resolve(server);
if (!await verifiedBy(peer)) {
  peer = await peers.resolve(server, refresh: true);
  if (!await verifiedBy(peer)) return null;
}
```

Fix: Make first-use pinning immutable during normal resolution. On a mismatch, retain K1, reject authentication with K2, and raise an operator-visible key-change condition. Permit rotation only through a separately authorized process. Make concurrent first-use writes atomic.

Test: Pin K1; replace the peer document with K2; submit an S2S request signed by K2. Assert authentication fails, the stored pin remains K1, and a key-change event is emitted. Also test concurrent first-use requests presenting different keys.

- Needs another slice: No for the server-side failure. The attacker's ability to control the external peer identity endpoint is an explicit attack prerequisite.

### High

### F-2 A federated sender can suppress a recipient device from the exact-list check

* Severity: High
* Confidence: Confirmed
* Where: `server/lib/src/modules/messaging/module.dart:495-520, 823-863`
* Breaks: Every recipient's exact current active-device list must be supplied; otherwise the send fails with `409 device_list_stale`.

Path

* A federated sender on `remote.example` targets a local account with two active devices, D1 and D2.
* The remote server sends an S2S batch identifying its `senderDevice` as D2's UUID, while listing a sealed payload only for D1.
* `_receive` verifies that the sender account belongs to the authenticated remote domain and that `senderDevice` is a syntactically valid UUID. It does not establish that this device belongs to the sender.
* `checkDevices` removes every device whose ID equals `senderDevice` from the required set, regardless of the recipient account.
* D2 is incorrectly excluded, the supplied list appears complete, and the send proceeds without `device_list_stale`.

The remote sender can make the server silently omit an active recipient device.

Evidence

`module.dart:499-516`:

```dart
final sender = AccountAddress.tryParse(batch.sender);
if (sender == null || sender.domain != domain) {
  throw const ApiError(ErrorCode.forbidden);
}
if (!Uuid.isValid(batch.senderDevice)) {
  throw const ApiError(ErrorCode.invalidField);
}
...
return _accept(
  senderAccount: sender.toString(),
  senderDevice: batch.senderDevice,
```

`module.dart:840-845`:

```dart
final required = {
  for (final d in devices)
    if (d.id != senderDevice) d.id,
};
final missing = required.difference(entry.value);
final extra = entry.value.difference(required);
```

Fix: Exclude `senderDevice` only when validating the sender's own account, and only after establishing that the device belongs to that account. For a federated sender targeting a local recipient, no recipient device should be excluded on the basis of a remote `senderDevice` claim.

Test: Create recipient devices D1 and D2. Submit a validly signed S2S batch from a different account with `senderDevice = D2` and only D1 listed. Assert `409 device_list_stale` and no stored envelopes.

- Needs another slice: No. The server-side bypass is demonstrable from these handlers.

### F-3 Recipient device lists and block state can change after validation

* Severity: High
* Confidence: Confirmed
* Where: `server/lib/src/modules/messaging/module.dart:375-417, 429-439, 823-863`; `server/lib/src/modules/messaging/module.dart:675-701`; `server/lib/src/modules/identity/data/identity_store.dart:218-234, 367-374`
* Breaks: Exact current active-device lists must be enforced; blocked senders must not reach recipients.

Path

* Sender A submits a message listing recipient B's active device D1.
* `_accept` checks blocks and the active-device roster outside the delivery transaction.
* Before storage begins, B adds D2. Alternatively, B blocks A.
* The original request continues using the previously validated state.
* The delivery transaction locks only the device IDs supplied by the sender. It does not recheck the complete active roster or B's current block decision.
* The server can accept the send without `409 device_list_stale`, omit D2, or deliver a message after the block has committed.

A revoked D1 is filtered from stored delivery, but that filtering does not restore the missing `409` behavior. In that case, a send can be recorded as accepted even though its listed device is no longer active.

Evidence

`messaging/module.dart:379-395`:

```dart
final blockers = await api.blockedBy(
  context.db,
  senderAccount,
  addressed.keys.where((a) => a != senderAccount),
);
...
await api.checkDevices(
  context.db,
  addressed,
  senderAccount: senderAccount,
  senderDevice: senderDevice,
);
```

`messaging/module.dart:429-437`:

```dart
final accepted = await context.db.tx((tx) async {
  final at = await _store.recordSend(
    tx,
    id,
    senderAccount: senderAccount,
    senderDevice: senderDevice,
  );
  if (at == null) return null;
  await api.deliver(tx, payloads, delivery);
```

The delivery-time lock covers supplied devices, not the full recipient roster:

```dart
final active = await _m.identity.lockActiveDevices(tx, payloads.keys);
```

Fix: Enforce recipient roster and block invariants inside the same transaction that records and stores the send. Use per-recipient account-level locking or another shared serialization mechanism also honored by device registration, revocation, blocking, and unblocking. Return `device_list_stale` when the locked current roster differs.

For remote relays, establish the same consistency guarantee at the destination before acceptance.

Test: Use transaction barriers to commit a new device, revoke an existing device, and commit a block between the initial read and delivery. Assert stale requests return 409, blocked messages create no envelopes, and rejected requests are not recorded as accepted.

- Needs another slice: No for the demonstrated ordering flaw. Runtime database isolation settings would help assess how frequently it occurs.

### F-4 Offline federation queues messages before validating the remote recipient roster

* Severity: High
* Confidence: Confirmed
* Where: `server/lib/src/modules/federation/module.dart:368-415`; `server/lib/src/modules/messaging/module.dart:198-219, 429-455`
* Breaks: Stale recipient device lists must be rejected with `409 device_list_stale`; a send must not be silently accepted with missing or removed devices.

Path

* A sender submits a stored message for an account on another server.
* The destination server is temporarily unreachable.
* `_relayMessages` catches `PeerUnavailable` and queues the complete batch.
* The origin returns a successful send response after its normal acceptance path. It has not established that the remote device list is current.
* The destination's roster changes while the relay is queued.
* On retry, the destination rejects the batch with `device_list_stale`.
* `_retryRelay` logs the refusal but does not throw or notify the sender. The job runner treats the handler as successful and deletes the job.

The sender sees an accepted message that the remote recipient never receives.

Evidence

`federation/module.dart:380-394`:

```dart
} on PeerUnavailable catch (e) {
  if (batch.ephemeral) return;
  ...
  await context.db.tx(
    (tx) => context.outbox.enqueue(
      tx,
      relayJob,
      {'domain': domain, 'batch': batch.toJson()},
      ...
    ),
  );
}
```

`federation/module.dart:399-413`:

```dart
try {
  await client.call(
    domain,
    'POST',
    Routes.s2sMessages.path,
    body: batch.toJson(),
  );
} on PeerRefused catch (e) {
  log.warn('relay_refused', {'peer': domain, 'code': e.error.code.wire});
}
```

Fix: Do not treat an unvalidated remote send as successfully accepted. Return an explicit retriable failure or a distinct pending state that remains visible to the sender, and propagate eventual device-list rejection to that sender. A queued job must not silently convert a destination refusal into success.

Test: Make a peer unavailable, submit a send, change its active-device list, then restore connectivity. Assert the sender never receives an unconditional success for a batch later rejected as stale.

- Needs another slice: No. The origin's queue and retry behavior are visible.

### F-5 WebSocket pongs and asynchronous acknowledgements lack bounded outstanding work

* Severity: High
* Confidence: Likely
* Where: `server/lib/src/modules/realtime/module.dart:226-237, 508-510, 531-568`; protocol `PingFrame`/`PongFrame` definitions in `dump_07_other_packages.txt`
* Breaks: Slow WebSocket clients must not cause unbounded server memory growth.
* Unsafe by itself: An authenticated client controls repeated server-side output and asynchronous work without a per-connection outstanding-work ceiling.

Path

* An authenticated device opens its WebSocket.
* It sends valid `ping` frames containing large nonces while not reading responses. The input frame limit and frame-rate limiter still permit a sustained stream.
* For every valid ping, `_onFrame` constructs a pong containing the same nonce.
* `_send` unconditionally adds the encoded response to the WebSocket sink. There is no application-level outstanding-byte limit or slow-consumer disconnect.
* Independently, the client can send acknowledgement frames faster than the database completes them. Each acknowledgement creates a tracked future with no maximum number of pending operations.

The code does not bound these queues. Whether sink buffering results in unbounded process memory depends on the WebSocket implementation and transport behavior; that portion is not proven without execution.

Evidence

`realtime/module.dart:508-510`:

```dart
void _send(ServerFrame frame) {
  if (!_closed) _ws.sink.add(frame.encode());
}
```

`realtime/module.dart:561-565`:

```dart
switch (frame) {
  case AckFrame(:final seq):
    _m.track(() => _ack(seq));
  case PingFrame(:final nonce):
    _send(PongFrame(nonce: nonce));
```

`realtime/module.dart:228-237`:

```dart
void track(Future<void> Function() work) {
  late final Future<void> tracked;
  tracked = Future<void>(work)
      ...
      .whenComplete(() => _tasks.remove(tracked));
  _tasks.add(tracked);
}
```

Fix: Bound outstanding outgoing bytes per socket and close connections that cannot drain. Independently, cap or serialize outstanding acknowledgement operations per device, preferably coalescing cumulative acknowledgements.

Test: Use a socket client that sends valid maximum-sized ping frames without reading. Assert bounded server memory and eventual closure. With an intentionally stalled database, send many acknowledgements and assert the number of pending operations remains bounded.

- Needs another slice: Yes - the exact WebSocket channel and transport buffering behavior, plus a runtime stress test, are necessary to confirm the memory impact.

### Medium

### F-6 Federation retry deduplication is not scoped to the sender

* Severity: Medium
* Confidence: Confirmed
* Where: `server/lib/src/modules/federation/module.dart:384-392`; `server/lib/src/platform/jobs/jobs.dart:69-85`
* Breaks: Idempotency keys must not suppress sends belonging to different senders.

Path

* Two distinct accounts submit federated stored messages using the same message UUID and destination domain.
* The destination is unreachable, so both batches enter the retry path.
* Both jobs receive the same deduplication key, `relay:<domain>:<message-id>`.
* PostgreSQL accepts the first pending job and silently ignores the second because of `ON CONFLICT ... DO NOTHING`.
* Both callers can receive successful acceptance, but only one batch survives for retry.

The collision is reproducible with chosen IDs. Exploiting a genuinely random, undisclosed victim message ID would additionally require learning or predicting that ID.

Evidence

```dart
dedupeKey: 'relay:$domain:${batch.id}',
```

`jobs.dart:77-78`:

```sql
ON CONFLICT (dedupe_key)
  WHERE dedupe_key IS NOT NULL AND status = 'pending' DO NOTHING
```

The normal messaging deduplication is correctly sender-scoped; this retry key is not.

Fix: Include the canonical sender account and sender device in the retry deduplication key.

Test: Queue two batches with identical message IDs and destination domains but different senders. Assert both jobs exist and both are eventually relayed.

- Needs another slice: No.

### F-7 Concurrent one-time-prekey uploads can exceed the per-device storage quota

* Severity: Medium
* Confidence: Confirmed
* Where: `server/lib/src/modules/keys/module.dart:193-207`; `server/lib/src/modules/keys/data/prekey_store.dart:37-48, 68-74`
* Breaks: Resource quotas must not be bypassable by concurrent requests.

Path

* A device already has 800 one-time prekeys.
* Two authenticated upload requests each submit 200 distinct new keys concurrently.
* Each transaction counts the same existing 800 keys.
* Each passes the `current + req.keys.length <= maxStored` check.
* Both transactions insert their distinct keys, leaving 1,200 keys even though `maxStored` is 1,000.

A transaction around the count and inserts does not, by itself, serialize competing count-and-insert operations.

Evidence

`keys/module.dart:197-205`:

```dart
final status = await context.db.tx((tx) async {
  final current = await _store.oneTimeCount(tx, deviceId);
  if (current + req.keys.length > maxStored) {
    throw const ApiError(ErrorCode.quotaExceeded);
  }
  await _store.addOneTime(tx, deviceId, req.keys);
```

`prekey_store.dart:68-70`:

```dart
'SELECT count(*) AS n FROM $s.one_time_prekeys WHERE device_id = @d:uuid'
```

Fix: Acquire a shared per-device serialization lock before counting and inserting, such as locking the device's parent row consistently across uploads.

Test: Start two simultaneous 200-key uploads against a device with 800 keys. Assert at most one succeeds and the final count never exceeds 1,000.

- Needs another slice: No.

### F-8 Federation retries persist the complete communication graph outside live mailboxes

* Severity: Medium
* Confidence: Confirmed
* Where: `server/lib/src/modules/federation/module.dart:380-392`; `server/lib/src/platform/jobs/jobs.dart:69-85, 93-105, 245-274`
* Breaks: The server should not retain who communicates with whom beyond the live mailbox, push tokens, and rate counters.

Path

* A federated message cannot be relayed immediately.
* `_relayMessages` serializes the entire `S2SMessageBatch` into a generic persistent job payload.
* The batch includes the sender identifier, sender device, recipient account/device identifiers, and encrypted payloads.
* The generic jobs table stores this JSON in PostgreSQL, independently of the recipients' live mailboxes.
* When a job exhausts its attempts because of repeated failures, the job runner marks it `dead` rather than deleting it.
* Dead jobs remain until an explicit administrative purge.

This preserves sender-recipient relationships and message payloads beyond the intended live-mailbox scope.

Evidence

`federation/module.dart:384-391`:

```dart
await context.outbox.enqueue(
  tx,
  relayJob,
  {'domain': domain, 'batch': batch.toJson()},
  delay: const Duration(seconds: 5),
  maxAttempts: 12,
  dedupeKey: 'relay:$domain:${batch.id}',
)
```

`jobs.dart:69-75`:

```sql
INSERT INTO platform.jobs
  (id, kind, payload, run_at, max_attempts, dedupe_key)
SELECT g, k, p::jsonb, ...
```

`jobs.dart:258-269`:

```dart
final dead = attempts >= job.integer('max_attempts');
...
'status': dead ? 'dead' : 'pending',
```

Fix: Remove full-message retention from the generic job system, or constrain the relay queue to the minimum permitted metadata and a strict retention window. Automatically delete terminal failed payloads. The design must also resolve F-4's sender-visible delivery outcome; simply deleting queued data is insufficient.

Test: Queue a federated send, inspect persisted job payloads for recipient graph and ciphertext, then exhaust retries. Assert the required privacy retention policy is enforced automatically.

- Needs another slice: No for the storage behavior. Production retention controls outside the source were not available.

### F-9 Unlimited blocks against nonexistent accounts create an unbounded database and response

* Severity: Medium
* Confidence: Confirmed
* Where: `server/lib/src/modules/people/module.dart:67-74, 621-660`
* Breaks: Resource exhaustion controls; unsafe by itself.

Path

* An authenticated device sends repeated block requests for distinct syntactically valid but nonexistent account UUIDs.
* `_blockTarget` checks the address format but does not require a local target account to exist.
* `_block` inserts each distinct target into `people.blocks`.
* The per-device rate limiter slows requests but does not establish a maximum stored block count.
* Over time, the account accumulates arbitrarily many block records.
* `GET /blocks` selects and materializes the entire accumulated set without a pagination limit.

A single authenticated account can therefore drive persistent storage growth and an increasingly expensive response.

Evidence

`people/module.dart:633-643`:

```dart
var address = AccountAddress.tryParse(q.param('account'));
...
return address.toString();
```

`people/module.dart:652-656`:

```dart
'INSERT INTO $s.blocks (account_id, blocked) VALUES (@a:uuid, @b:text) ON CONFLICT DO NOTHING',
{'a': me, 'b': target},
```

`people/module.dart:621-627`:

```dart
final rows = await context.db.query(
  'SELECT blocked FROM $s.blocks WHERE account_id = @a:uuid ORDER BY created_at',
  {'a': q.device.accountId},
);
return jsonResponse(
  BlockList(accounts: [for (final r in rows) r.string('blocked')]).toJson(),
);
```

Fix: Enforce an atomic maximum block count per account and paginate block-list retrieval. For local targets, reject nonexistent accounts where that does not conflict with the intended privacy model.

Test: Generate many unique block targets, including nonexistent UUIDs. Assert storage cannot exceed the configured ceiling and list responses remain bounded.

- Needs another slice: No.

### Low

### F-10 Remote block decisions are omitted from the originating sender's response

* Severity: Low
* Confidence: Confirmed
* Where: `server/lib/src/modules/federation/module.dart:238-242, 368-377`; `server/lib/src/modules/messaging/module.dart:225-259, 375-387, 420-455`
* Breaks: A sender must be told which recipient accounts blocked them on that sender's own send.

Path

* Sender A posts a federated message to remote recipient B.
* B's server correctly identifies B as blocking A, suppresses the corresponding delivery, and returns a `SendMessageResponse` containing `blockedBy`.
* The originating server's `_relayMessages` awaits the HTTP request but discards its JSON response.
* The originating messaging handler constructs its response using only its own local `blockers` set.
* A receives a successful send response without being informed that B blocked them.

This is a documented response-contract failure, not an established unauthorized delivery.

Evidence

`federation/module.dart:238-242`:

```dart
final accepted = await messaging.receive(q.server.serverId, batch);
return jsonResponse(accepted.toJson());
```

`federation/module.dart:372-377`:

```dart
await client.call(
  domain,
  'POST',
  Routes.s2sMessages.path,
  body: batch.toJson(),
);
```

`messaging/module.dart:452-455`:

```dart
final response = SendMessageResponse(
  acceptedAt: accepted,
  blockedBy: blockedBy,
);
```

Fix: Return and parse the remote `SendMessageResponse` through the relay interface. Merge qualified remote blocker accounts with locally detected blockers before replying.

Test: Have B block A across two federation servers. Submit A's send and assert B receives no envelope while A's response includes B in `blocked_by`.

- Needs another slice: No.

### Checked and fine

These are narrowly scoped positive results from code inspection, not guarantees that the components have no other vulnerabilities.

* Mailbox REST ownership: `messaging/module.dart:523-547` derives mailbox fetch and acknowledgment device IDs from `q.device.deviceId`, rather than caller-supplied account/device IDs. Corresponding mailbox SQL scopes operations by device.
* Normal stored-send idempotency: `messaging/data/mailbox_store.dart:294-323` keys sends by sender account, sender device, and message ID. The separate federation retry collision is F-6.
* Revoked-device protection in stored delivery: `identity/data/identity_store.dart:367-374` locks supplied active-device rows; `messaging/module.dart:681-687` filters out inactive devices. This protection is useful but does not resolve the complete-roster race in F-3.
* One-time-prekey consumption: `keys/data/prekey_store.dart:51-66` uses an atomic delete with `FOR UPDATE SKIP LOCKED`, preventing two concurrent bundle fetches from consuming the same stored one-time prekey.
* Key binding and signature checks: The examined certificate-validation path checks account/device binding; the signed-prekey publication path verifies its signature against the device signing key. No server-side bypass was demonstrated in these paths.
* Contact discovery: `people/module.dart:391-430` validates hash format and batch bounds and atomically charges a per-account daily discovery budget. No raw-number storage was identified in that handler.
* Block write ownership: `people/module.dart:646-674` derives the blocker from the authenticated account, so the examined routes do not let A directly modify B's block list.
* WebSocket authentication and routing: Upgrade authentication uses a device principal; connected sockets periodically revalidate sessions; route ownership uses compare-and-set; cross-node bus consumers look up connections by device ID. No direct cross-device subscription or mailbox-read path was established.
* WebSocket input limits: The examined implementation enforces client frame-size and frame-rate limits. F-5 concerns outstanding output and asynchronous work, not absent input limits.
* Federation signatures and network targets: The S2S verifier checks timestamp, signed request content, and replay identity. The production HTTP connection factory vets resolved IP addresses before opening sockets, preserves TLS hostname verification, and disables redirects. I did not establish an SSRF or DNS-rebinding exploit in that path.
* Ephemeral consumption and bus fan-out: The examined ephemeral `take` is atomic, and realtime bus handlers target their local connection map using device IDs. No direct wrong-device consumption was demonstrated.

### Not covered

* Execution of attacks or integration tests against a running PostgreSQL, HTTP, or WebSocket deployment.
* Exhaustive analysis of every test, schema migration, administrative route, operational job, and auxiliary server package in the larger extracts.
* Complete authorization and cryptographic sender-authenticity analysis for group messaging and calls, including the separate group-home forwarding logic.
* Exhaustive analysis of logging and telemetry sinks for every secret or metadata field, beyond the traced persistence and logging paths.
* Verification of actual memory-growth behavior under slow WebSocket clients or database stalls.
* Independent cryptographic review of payload formats, ratchets, or message decryption, which is outside this audit's requested server trust boundary.

### Needs another slice

* Flutter/Dart engine message-authentication and group-message validation: To determine whether clients reject sender-attribution forgeries in forwarded group envelopes and to establish the exact end-user impact of malicious group-home behavior.
* Deployed HTTP/WebSocket runtime and dependency versions: To confirm sink-buffer growth, network backpressure behavior, and outstanding-task memory consumption for F-5.
* Production PostgreSQL isolation and operational settings: To quantify the race windows in F-3 and F-7. The source already demonstrates that the relevant validations are not explicitly serialized.
* Deployment and infrastructure configuration: To check reverse-proxy WebSocket behavior, token/header handling at the edge, secret storage, logging collection, and database retention policies.
* Federation key-rotation operational workflow, if any: To determine whether another component provides a separate approval or quarantine process. No such enforcement appears in the traced peer-resolution path.

Priority for remediation: F-1 first, because a changed federation identity key becomes trusted. Then F-2 and F-3, which undermine the exact-device delivery invariant, followed by F-4's accepted-but-undelivered federation messages. F-5 requires a runtime stress test, while the remaining findings can be pinned with focused concurrency and integration tests.

All findings are based on static source inspection; none has been represented as an executed exploit.
