# Sweep 12l — engine: calls, part two (log mirror, media seam, WebRTC wrapper)

Read line-by-line: `calls/call_log_mirror.dart` (54), `calls/call_media.dart`
(106), `calls/fake_call_media.dart` (185), `calls/call_models.dart` (153), the
whole `helix_remote_calls` package (`web_rtc_call_engine.dart` 660,
`call_engine.dart` 132, `call_devices.dart` 124, `ice_config.dart` 152,
`call_quality.dart` 51, `call_setup_failure.dart` 55, `call_video_view.dart`
37), and the app's seam: `application/media/webrtc_call_media.dart` (217),
`call_media_hub.dart` (112), `call_media_providers.dart` (25) and
`notification_call_ringer.dart` (65), with cross-reads that settle them:
`apply.dart`'s call-log branch (`_insertMessage` 216-351), `calls_dao`'s
`start`/`answered`/`end`, the protocol's `CallLogBody` decode and
`CallSignalType` catalog, the API's `sendMetrics` and its only caller (the
route-parity test), the server's `_metrics` route, and
`REMOTE_CALLS_RELEASE_READINESS.md` (handoff and permission-contention rows).
~2,300 lines — over the guide because `helix_remote_calls` is one unit and the
findings live at its seams with the engine.

Verdict: the log mirror is correct and idempotent, and the media seam is
honoured by both implementations (buffered candidates, broadcast states,
one-shot close). Four defects, all P3: a failed media setup leaks the peer
connection (and can make a late ICE callback add to a closed stream), the ICE
config claims a server-side relay enforcement that cannot exist behind sealed
signals, the call-metrics path has no producer, and the ICE-restart path is
unreachable.

---

### AUD-12l-1 A failed media setup leaks the peer connection (and any initialized renderer), and its ICE callback can fire into a closed stream

**Severity** P3  **Confidence** confirmed

**Where**
- [`web_rtc_call_engine.dart:122-167`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_calls/lib/src/web_rtc_call_engine.dart#L122) — `_createState` creates the peer connection at 130, then awaits the microphone/camera (132), two renderer `initialize()`s (140-141) and `addTrack` (145); only at 161 is the state put in `_calls`.
- [`web_rtc_call_engine.dart:327-338`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_calls/lib/src/web_rtc_call_engine.dart#L327) — `endCall` removes the state; with no entry it returns having released nothing.
- [`web_rtc_call_engine.dart:390-396`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_calls/lib/src/web_rtc_call_engine.dart#L390) — `dispose` only ends the states in `_calls`, then closes the event controller.
- [`web_rtc_call_engine.dart:85-93`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_calls/lib/src/web_rtc_call_engine.dart#L85) — `onIceConnectionState` adds to `_eventController` without an `isClosed` or `_endedCalls` guard (the sibling `onIceCandidate` has the latter).

**What** If anything between the peer connection's creation and its insertion
into `_calls` throws — a denied or contended microphone/camera
(`getUserMedia`), a renderer that will not initialize, a failing `addTrack` —
the exception propagates to the engine's `_accept`/`_startCall`, the session is
closed, and `endCall(callId)` finds no state, so the peer connection (and any
renderer already initialized) is never closed or disposed. The clean
"ended during setup" path exists only *after* the state is assembled
(154-160).

**Trigger** Permission denied at the OS level after the app's probe succeeded,
or camera/microphone contention — an explicit item of the release checklist
(`REMOTE_CALLS_RELEASE_READINESS.md:52`) and the ordinary case of another app
holding the camera. Every retry leaks another peer connection.

**Evidence** There is no `try`/`catch` in `_createState`; the only cleanup is
`_releaseState(state)` at 158, on the path where `state` was built. `pc` is a
local (`130`) that no other code can reach once the frame unwinds, and
`_calls[callId]` (161) is the sole handle `endCall`/`dispose` work from. The
leaked pc's callbacks still point at `_diag` and `_eventController`; `_diag`
checks `isClosed`, but `onIceConnectionState` (85-93) does not, so a state
change after `dispose()` throws `StateError` from inside a plugin callback.

**Impact** Native media resources held until GC on a path that retries
(permission prompts, busy camera); a possible `StateError` reported through the
zone when the stale connection changes state. No media, key or content leak.

**Fix sketch** Make setup transactional: wrap 130-147 in `try`/`catch`, and on
any throw close/dispose the pc, dispose both renderers, dispose the stream,
then rethrow (the same calls `_releaseState` makes). Add `_eventController
.isClosed` to the `onIceConnectionState`/`onIceCandidate` handlers as a belt.

**Test that proves it** The package has no seam for `navigator.mediaDevices`
today; add one (a `MediaDeviceProvider` defaulting to the plugin) so a test
can make `getUserMedia` throw and assert `pc.close`/`pc.dispose` were called
and the event stream can be closed without error. Without the seam, the test
belongs at the engine level only if the wrapper is split.

**Overlap** AUD-12k-2 (an engine stop can also end a call mid-setup; different
leak site), none otherwise.

---

### AUD-12l-2 The ICE config says the server enforces relay-only and can drop leaking candidates; call signals are sealed, so the server cannot see a candidate

**Severity** P3  **Confidence** confirmed

**Where**
- [`ice_config.dart:10-14`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_calls/lib/src/ice_config.dart#L10) — "That is why the negotiated policy is also enforced on the server, which sees every candidate and can drop the ones that would leak."
- [`engine_call_signaling.dart:44-66`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/calls/engine_call_signaling.dart#L44) — every signal, ICE included, is sealed per recipient device before it is posted.
- [`server/.../calls/module.dart:330-368`](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/calls/module.dart#L330) — the server checks device lists and blocks, then delivers the sealed payloads; it never parses them.
- [`PRIVACY_CLAIM_MATRIX.md:31`](file:///J:/Projects/helix/helix_remote/docs/product/PRIVACY_CLAIM_MATRIX.md#L31) — the product claim is the correct one: SDP and ICE candidates are sealed pairwise, the server sees only the kind.

**What** A source comment in the file that defines the privacy modes states a
protection the architecture does not have: the server holds ciphertext and
cannot inspect or drop a candidate. Relay-only is enforced only by each
client's own `iceTransportPolicy` (144-150) and by the factory refusing a
config with no TURN (`webrtc_call_media.dart:50-57`).

**Trigger** A reviewer or a future implementer reading `IpPrivacyMode` to
decide whether a weaker mode is safe: the comment says the server is the
backstop, so a client-side check can look optional.

**Evidence** Server sweep 6 found no candidate parsing (`_deliverLocal` checks
`checkDevices` and blocks only); the sealed payload is opaque; the protocol's
`CallSignalType` has no candidate kind the server could filter on. The
Privacy Claim Matrix and `DATA_FLOW.md` already describe the true model
(client-side relay-only, sealed candidates), so this comment is the outlier.

**Impact** No leak today: both sides hardcode `relayOnly`
(`webrtc_call_media.dart:52`), and a relay-only peer gathers no host
candidates, so it cannot be talked into a direct path. The damage is a false
security claim where the security decision lives.

**Fix sketch** Rewrite the paragraph: relay-only is enforced per client by
`iceTransportPolicy`, symmetric only when both sides honour it, and the server
cannot inspect candidates because they are sealed; any future server-side
enforcement would need a wire change. Alternatively, if enforcement really is
intended, file it as a design item rather than describing it as present.

**Test that proves it** None needed for the comment; a test asserting the
factory always builds `relayOnly` configs would pin the actual guarantee.

**Overlap** AUD-6-4 (signal addressing) is unrelated; sweep 6's server side
already established the server's blindness.

---

### AUD-12l-3 The call-metrics pipeline has a route, a client method and a serializer, but nothing ever sends a sample

**Severity** P3  **Confidence** confirmed

**Where**
- [`calls_client.dart:36`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/clients/calls_client.dart#L36) — `sendMetrics`, whose only caller in the repo is the route-parity test ([`route_parity_test.dart:188`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/test/v2/route_parity_test.dart#L188)).
- [`call_quality.dart:35-50`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_calls/lib/src/call_quality.dart#L35) — `toMap`, with no caller.
- [`web_rtc_call_engine.dart:461-474`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_calls/lib/src/web_rtc_call_engine.dart#L461) — the sampler emits `RemoteCallQualityEvent`; the adapter keeps only `isWeak` (`webrtc_call_media.dart:143-144`).
- [`server/.../calls/module.dart:562-585`](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/calls/module.dart#L562) — the route that would store the row, and its `call_metrics` table and 90-day sweep.

**What** The quality sampler runs every 5 s during a call, but its numbers
reach only the UI's "poor connection" flag. `CallQualityMetrics` is never
serialized for the server, so `POST /v1/calls/metrics` has no producer and the
`call_metrics` table (with its `reconnects` and `relayed` columns) stays empty.

**Trigger** Every call. The release-readiness runbook tells the operator to
record packet loss, RTT, jitter, candidate type and setup latency per run
(`REMOTE_CALLS_RELEASE_READINESS.md:34-37`), which is a manual substitute for a
feed that was built and never connected.

**Evidence** `grep -rn sendMetrics` over `packages/ app/ server/lib server/bin`
returns only the definition and the parity test; `toMap` has no caller; the
adapter's quality case has the `weak` field as its only consumer, so no
`RemoteCallQualityEvent` reaches any code that could post it.

**Impact** No quality data on the server: connector/NAT problems cannot be
seen in aggregate, and AUD-6-1's cost analysis is currently moot. Not a
correctness or privacy issue (the metrics carry no participants).

**Fix sketch** Either wire it (the engine's `CallsService` already owns the
API client and the call's `callId`; post the last sample at `_finish`, with
`relayed` from `isRelay` and `reconnects` from an ICE-restart counter — see
AUD-12l-4) or delete the client method, `toMap` and the server route so the
surface stops implying collection. Wiring is the smaller change.

**Test that proves it** Engine test: finish a call with a fake media that
reports one quality sample and assert `api.calls.sendMetrics` was called once
with the duration and outcome; today nothing is called.

**Overlap** AUD-6-1 (the route's storage cost and unindexed cleanup) — that
finding only matters if this one is fixed; note it there.

---

### AUD-12l-4 The ICE-restart path is unreachable: nothing calls `restartIce`, the adapter drops the offer it would emit, and the wire has no renegotiation signal

**Severity** P3  **Confidence** confirmed

**Where**
- [`call_engine.dart:67-73`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_calls/lib/src/call_engine.dart#L67) and [`call_engine.dart:116`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_calls/lib/src/call_engine.dart#L116) — the event and the interface method.
- [`web_rtc_call_engine.dart:257-281`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_calls/lib/src/web_rtc_call_engine.dart#L257) — the only implementation, emitting `RemoteRenegotiationOfferEvent`.
- [`webrtc_call_media.dart:147-150`](file:///J:/Projects/helix/helix_remote/app/lib/features/calls/application/media/webrtc_call_media.dart#L147) — the adapter's switch discards that event.
- [`protocol/.../calls.dart`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/modules/calls.dart) — `CallSignalType` is offer/answer/ice/ringing/end; there is no renegotiation kind to carry an ICE-restart offer.

**What** The wrapper can start an ICE restart and produce a new offer, but no
layer above it can deliver that offer: `restartIce` has no caller anywhere in
the repo, the adapter explicitly ignores the event, and the engine's signalling
has no type for it. A call whose path dies (a Wi-Fi to mobile handover, a NAT
rebinding) therefore has no recovery: ICE goes `disconnected` (ignored by
`CallsService._onMediaState`) and then `failed`, which ends the call.

**Trigger** Leaving a Wi-Fi network during a call, or any mid-call address
change — an explicit real-device row in the readiness checklist
(`REMOTE_CALLS_RELEASE_READINESS.md:48`).

**Evidence** Repo-wide grep for `restartIce(` finds only the interface and the
implementation; `RemoteRenegotiationOfferEvent` is constructed in one place and
consumed nowhere; `CallSignalType` has no such member, so even a wired event
would have nothing to route as.

**Impact** Calls drop instead of recovering on a network change. The dead
surface also implies recovery exists, which is what a reviewer of the handoff
row will assume. No data-loss or security impact.

**Fix sketch** Decide explicitly: implement (new `CallSignalType.renegotiate`,
engine relay of the SDP to the bound device, adapter feeding it back through
`acceptAnswer`-style renegotiation — a wire change and a protocol version
note) or delete `restartIce`, the event and the adapter case so the interface
matches what ships. Given the relay-only policy, deleting is the honest
short-term move.

**Test that proves it** None until wired; after wiring, an engine test that a
`disconnected` call on both sides recovers via a renegotiation signal would
pin it. A deletion needs no test.

**Overlap** AUD-12l-3's `reconnects` column is the metric that would measure
this; the readiness checklist is the only document that asks for the case.

---

## Verified safe (checked, no finding)

- **The call-log mirror is idempotent and keeps local truth.** `record`
  returns early when the call id already has a row (`call_log_mirror.dart:23`),
  so a device that saw the call ring keeps its own log, a second copy of the
  message changes nothing, and the missed-call notice is raised only for a row
  this device did not have (`apply.dart:311-330`). The `fromSelf` mapping is
  right in all four outcomes: a caller's other device learns an outgoing call
  with its duration, a callee's offline device learns `answered_elsewhere`,
  `declined` or `missed`.
- **The mirror runs inside the apply transaction** (`apply.dart:313`, called
  from the transaction that stores the message and commits the ratchet), so a
  row and its message cannot disagree. `durationS` is clamped at decode
  (`bodies.dart:615`, `optIntIn(0, maxCallSeconds)`), so the subtraction cannot
  overflow or produce an out-of-range `DateTime`.
- **The media contract is implemented faithfully on both sides.** Candidates are
  a single-subscription stream buffered before the engine listens
  (`web_rtc_call_engine` gathers into the session's controller; the fake's
  controller buffers); states are broadcast with no replay; every method after
  `close` may throw, and both implementations do.
- **Close is one-shot and complete.** `_finish` cancels both engine
  subscriptions before calling `close()` (`calls_service.dart:764-806`); the
  adapter cancels its remote-engine subscription, closes its controllers and
  ends the engine; the WebRTC engine cancels the quality timer, closes and
  disposes the pc, stops every local track, clears both renderers, disposes the
  streams and the renderers (`web_rtc_call_engine.dart:340-355`). The fake
  reports `closed` once and ignores later state changes.
- **Ended during setup is handled on the successful-assembly path**: the mark
  is checked after the state is built, the state is released and
  `CallEndedDuringSetup` is thrown (`web_rtc_call_engine.dart:154-160`).
- **Remote candidates are bounded and deduped**: length cap and prefix check
  (`595-599`), a per-session seen-set, and a queue only until the remote
  description is set, flushed once (`398-431`); the engine caps its own queue at
  64 before it ever calls the media layer.
- **Relay-only fails closed.** `toWebRtcConfiguration` sets
  `iceTransportPolicy: 'relay'` unless the policy *explicitly* permits direct
  (`ice_config.dart:141-150`), and the factory refuses a config without a TURN
  server instead of falling back to a direct call
  (`webrtc_call_media.dart:50-57`).
- **The fake is a faithful double**: it gathers a fixed number of candidates,
  connects only after the remote description and the configured number of
  remote candidates, can stay connecting or fail on demand, and close is
  idempotent. Nothing in it pretends to succeed where production fails.
- **No content crosses the metrics or diagnostic surfaces**: quality samples
  carry transport numbers only, `_diag` messages carry lengths, candidate
  types and state names, and `IceServer.toString` redacts the credential.

## Coverage notes

- **The 660-line WebRTC engine has no tests** (the package's only test is
  `ice_config_test.dart`), and it cannot get one without a seam for
  `navigator.mediaDevices` — which finding 1 also needs. The readiness runbook
  covers it with real-device runs today.
- **`CallSnapshot.copyWith` cannot clear a nullable field** (null means "keep",
  `call_models.dart:109-128`); a `phase: ended` snapshot with `end: null` is
  constructible but no producer builds one. Folded into 12k's S1.
- **A mirrored non-answered call has `startedAt == endedAt`** (the caller's
  `sentAt`), so the detail page shows a zero-length attempt rather than the
  time the caller started dialling; the wire carries no start time.
- **`apply.dart` queues two delivered receipts** for an arriving missed-call
  message (`_delivered` at 324 and again at 331) — that is AUD-12c-1's defect,
  and the missed-call branch is its most visible case.
- **`_endedCalls` does not grow with the process**: every session owns its own
  `RemoteWebRtcCallEngine`, and the adapter disposes it on close.
- **`WebRtcAudioOutputs.select(earpiece)` does not unset the speakerphone flag**
  that `select(speaker)` set (`call_devices.dart:42-53`); the plugin's
  `selectAudioOutput` is expected to route, but only a device run can confirm
  it — noted for the real-device matrix.
- **`CallMediaHub.watch()` can miss one publish** between its first `yield`
  and the subscription to `_changes` (`call_media_hub.dart:88-91`); at worst a
  frame is skipped until the next media event.
- **`CallMediaInfo.copyWith` cannot clear `local`/`remote`**; `publish(null)`
  is the close path (`call_media_hub.dart:42-55, 93-96`).
- **The transfer queue's call loops** are 12m/12n with the transfers, not here.
