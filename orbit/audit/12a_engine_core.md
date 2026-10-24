# 12a — `helix_remote_engine`: `Engine`, events, errors, context, maintenance

## Overview

`Engine` is a facade over ~20 services, a composition root (200 lines of
constructor wiring) and the owner of the lifecycle (start/stop/close, sign-out,
revocation, session end). The services themselves are cleanly separated; the
lifecycle is not: three booleans (`_workersRunning`, `_revoking`, and the
status enum) are flipped around `await`s with no serialisation, and the
"session ended" path leaves the engine in a state its own account service
refuses to recover from.

`events.dart` and `errors.dart` are sound: a sealed event family with no
content or identifiers a UI should not see, and a sealed exception family
whose messages are documented to carry no keys, tokens, codes or numbers. No
findings there. `context.dart`, `config.dart`, `util/` are small and
coherent (`emit` is guarded against a closed controller; `KeyedLock` is
correct for both single and multi-key use; `Backoff` is bounded).

The one finding that changes behaviour: after a session ends, **the person
cannot sign in again on that device**, although `EngineStatus.signedOut` and
its doc promise exactly that. The rest are ordering and re-entrancy hazards
in the lifecycle and in the maintenance timer.

## Files read

- `engine.dart` (663), `events.dart` (194), `errors.dart` (182),
  `context.dart` (64), `maintenance.dart` (119), `config.dart` (141),
  `util/{backoff,ids,keyed_lock,masking}.dart` (133).
- Cross-reads, to ground the findings: `account/account_service.dart`
  (register/sign-in/link/`_requireEmpty`/`deviceKeySignIn`/`leaveOnServer`),
  `account/key_maintenance.dart` (167), `messaging/inbound_runner.dart`
  (292), `helix_remote_db` `crypto_dao.dart:116`, `helix_remote_api`
  `transport/auth.dart` (219), app `session_providers.dart`,
  `runtime_providers.dart`, `sign_in_controller.dart`, `sign_in_copy.dart`,
  `helix_runtime.dart:120-250`, and the engine/security/account tests' names
  and assertions.

## Findings

### AUD-12a-1 A session that ends leaves the account in place, and every sign-in path refuses while it is there: the documented "session ended: sign in" recovery is a dead end
- **Severity:** P1
- **Confidence:** confirmed
- **Where:** [engine.dart:602-606](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/engine.dart#L602) sets `signedOut` without forgetting the identity; the refusal is [account_service.dart:596-602](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/account_service.dart#L596) called from `signInWithPassword` ([:263](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/account_service.dart#L263)), `register` ([:81](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/account_service.dart#L81)) and `beginLink` ([:426](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/account_service.dart#L426)); the promise is [events.dart:9-13](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/events.dart#L9)
- **What:** `_handleSessionEnded` stops the workers and reports `signedOut`
  but keeps `_ctx.identity` and the `account` row, so `_requireEmpty` — the
  guard every sign-in, registration and link path starts with — sees
  "an account already exists" and throws `EngineStateException('this
  database already holds an account; sign out first')`. The app maps
  `signedOut` to the sign-in page and runs sign-in on the same runtime
  (the active slot is unchanged), so the person sees "Could not sign in.
  Please try again." for every password, SMS or link attempt.
- **Trigger:** a session the server ends while the local data stays —
  refresh token refused (reuse, or expired past the device-key rescue) and
  the device-key sign-in also refused. The realistic case is a server
  restored from a backup that predates the device row: the refresh 401s,
  `deviceChallenge` answers "unknown device", the engine reports
  `signedOut`, and every device is locked out of its own history. The
  transient-error path of AUD-12a-2 reaches the same state from a 30-second
  server hiccup.
- **Evidence:** `_handleSessionEnded` only calls `_setStatus` and
  `_stopWorkers`; `_forgetIdentity` ([:608-611](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/engine.dart#L608))
  is called only by sign-out and revocation. `_requireEmpty` tests
  `_ctx.isSignedIn || await _ctx.db.accountDao.current() != null`. The app's
  `authStateProvider` maps `signedOut` to sign-in
  ([session_providers.dart:44-49](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/session_providers.dart#L44)),
  `signInWithPassword` calls the engine on the same runtime
  ([sign_in_controller.dart:508-516](file:///J:/Projects/helix/helix_remote/app/lib/features/sign_in/application/sign_in_controller.dart#L508)),
  and `passwordRejected` has no `EngineStateException` arm
  ([sign_in_copy.dart:105-114](file:///J:/Projects/helix/helix_remote/app/lib/features/sign_in/application/sign_in_copy.dart#L105)).
  The only callers of `signOutProvider` are Settings pages
  ([account_providers.dart:201](file:///J:/Projects/helix/helix_remote/app/lib/features/settings/application/account_providers.dart#L201),
  [accounts_providers.dart:81](file:///J:/Projects/helix/helix_remote/app/lib/features/settings/application/accounts_providers.dart#L81),
  [delete_account_providers.dart:296](file:///J:/Projects/helix/helix_remote/app/lib/features/settings/application/delete_account_providers.dart#L296)),
  and Settings is behind the signed-in shell. Restarting does not help: the
  slot is kept but marked `signedIn: false`
  ([runtime_providers.dart:306-313](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/runtime_providers.dart#L306)),
  `restore` still opens it ([:165-189](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/runtime_providers.dart#L165)),
  and `Engine.start` loads the identity and reports `running`
  ([engine.dart:325-339](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/engine.dart#L325)),
  so the app shows the home tabs with a session that cannot be renewed and
  falls back to sign-in when the socket says so.
- **Impact:** after a session end the only way forward is deleting the local
  data (destructive reset) — history included, unless the person has a
  backup. A server restore turns into a fleet-wide lockout of every device's
  local history, which is the opposite of what the status doc tells hosts to
  do.
- **Fix sketch:** make the state explicit and recoverable. Either (a) keep
  `signedOut` but let `_requireEmpty` admit a sign-in whose server account id
  equals the local `account.account_id`, with `_addDevice` replacing the
  identity, prekeys and session rows (chats and messages are not keyed by
  device, so they survive), or (b) add a distinct "session ended, data kept"
  state that the app renders as a sign-in page with "Sign out and remove".
  (a) is engine-only and matches the doc; (b) needs app copy. Either way
  `_handleSessionEnded` must mark the state, not just the status.
- **Test that proves it:** register a device; make the fake server forget it
  (refresh 401, `deviceChallenge` 401) so the engine reports `signedOut`;
  assert `accountDao.current() != null`, then `signInWithPassword` must
  succeed and existing messages must still be there. Today that call throws
  `EngineStateException`.
- **Overlap:** AUD-12a-2 (a transient error is one way in). Same status
  mapping as `EngineStatus.revoked` (session_providers.dart:137-143), which
  is the only path that rebuilds the runtime.

### AUD-12a-2 Device-key re-authentication treats every `ApiException` as "this device is gone", so a 429/5xx during re-auth forgets a still-valid session
- **Severity:** P2
- **Confidence:** confirmed
- **Where:** [account_service.dart:616-637](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/account_service.dart#L616) returns null for any `ApiException` that is not `device_revoked`; [auth.dart:149-163](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/auth.dart#L149) turns a null re-authentication into `forget()` plus `SignedOutException`
- **What:** when a refresh is refused, `DeviceSessionAuth` gives the device
  key one chance. The chance is `AccountService.deviceKeySignIn`, which
  catches `ApiException` and — except for `device_revoked`, which it routes
  to the revocation handler — returns `null` as if the device were unknown.
  A 429 `rate_limited`, a 502/503/504 `unavailable` after the transport's
  retries, a 409 or a 500 all mean "try later", not "this device is gone".
  `_refresh` then clears the stored session and publishes
  `SignedOutException(refreshRejected)`.
- **Trigger:** the access token expires (or the refresh is refused) exactly
  while the server or the network path answers the challenge route with 5xx
  or a rate limit. Rate limits are per-IP/account and 5xx is routine during a
  deploy or a busy host.
- **Evidence:** the catch is bare `on ApiException`
  ([:632-637](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/account_service.dart#L632));
  `_refresh`'s contract says a refresh that gets *no answer* keeps the
  session ([auth.dart:53-58](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/auth.dart#L53)),
  and `reauthenticate` is called inside the `on ApiException` catch, so any
  `NetworkException` it throws does propagate and is kept — only the
  *answered* transient case is lost.
- **Impact:** the session and its refresh token are deleted on the device;
  the person must sign in again (password or SMS), and a linked device with
  neither must be re-approved from another device. With AUD-12a-1 the sign-in
  is refused, so a transient error becomes a lockout plus data wipe.
- **Fix sketch:** branch on the code: return null (or call `onRevoked`) only
  for `device_revoked` / `unauthenticated` on `deviceChallenge` /
  `forbidden`; rethrow `unavailable`, `rate_limited`, `internal`,
  `conflict` and anything else, so `_refresh` propagates it and keeps the
  session. A `TransientEngineException` wrapper would not help here (the
  transport does not know it); rethrow the `ApiException` unchanged.
- **Test that proves it:** a fake identity route answers 503 (and 429) for
  `deviceChallenge` while the refresh route answers 401; assert
  `auth.current()` still returns the session and the request fails with the
  503/429 error rather than `SignedOutException`.
- **Overlap:** AUD-12a-1 (this is a trigger for that dead end). Sweep 11a's
  `isUnauthenticated => status == 401` note is the client-side mirror of the
  same "status versus code" confusion.

### AUD-12a-3 Maintenance passes can overlap, and two overlapping replenishments save different private keys under ids the server already holds
- **Severity:** P2
- **Confidence:** likely
- **Where:** [maintenance.dart:35-44](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/maintenance.dart#L35) fires `runOnce` from a periodic timer with no re-entrancy guard, and [maintenance.dart:54-81](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/maintenance.dart#L54) has none; [key_maintenance.dart:93-124](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/key_maintenance.dart#L93) reads the counter, generates, saves and uploads; [crypto_dao.dart:116-117](file:///J:/Projects/helix/helix_remote/packages/helix_remote_db/lib/src/daos/crypto_dao.dart#L116) saves with `insertAllOnConflictUpdate`
- **What:** a pass is network-bound (`keys.status`, device refresh, the
  backup's own work) and the default interval is 5 minutes
  ([config.dart:20](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/config.dart#L20)).
  When a pass outlives the interval, the next tick starts a second pass
  concurrently. Both then run `KeyMaintenance.run`; `replenish` reads
  `EngineState.oneTimePrekeyCounter`, generates a batch, saves it, then
  uploads it. Two runs read the same counter, generate *different* keys under
  the same ids, and the second `savePrekeys` (an upsert) overwrites the
  first locally after the first batch was already uploaded. The same
  read-then-write shape in `_syncSignedPrekey`
  ([:128-152](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/key_maintenance.dart#L128))
  can leave the server advertising a signed prekey this device no longer
  stores, if the two runs' saves and uploads interleave in opposite order.
  `Engine.runMaintenance` ([engine.dart:510-513](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/engine.dart#L510))
  lets a host (or a test) add a third caller by design.
- **Trigger:** a pass longer than the interval: an unreachable server (the
  transport's 30 s deadline times its attempts, twice in the same pass) plus
  a backup maintenance pass that uploads. On a slow link this is minutes.
- **Evidence:** `start()` arms the timer and calls `runOnce()` immediately;
  `runOnce()` has no `_running` flag (contrast `InboundRunner._fetching` at
  [inbound_runner.dart:232-237](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/inbound_runner.dart#L232));
  `replenish` commits local keys and the counter *before* the upload
  ([:109-119](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/key_maintenance.dart#L109)),
  which is right for crash safety but assumes it is the only writer.
- **Impact:** peers that fetch the overwritten one-time prekeys encrypt to
  material this device cannot answer; X3DH setup fails, the message is
  quarantined or triggers a session reset, and the failure repeats for every
  peer that took one of those ids. A signed-prekey mismatch has the same
  effect until the next pass re-uploads the stored key (up to
  `prekeyCheckInterval`, 6 h).
- **Fix sketch:** single-flight the whole pass (`Future<void>? _pass;
  Future<void> runOnce() => _pass ??= _go().whenComplete(() => _pass = null);`)
  — the timer's `unawaited` call then becomes a no-op while a pass runs,
  which is what its own backoff comments describe. Independently, make
  `replenish` allocate ids and check "is a fill still needed" inside one
  transaction (e.g. a conditional counter update), so it is safe even if a
  second caller appears.
- **Test that proves it:** a fake keys route with a controllable delay; call
  `runOnce()` twice concurrently and assert the counter advanced by exactly
  one batch's worth, only one upload happened, and every locally stored id
  matches the uploaded material for that id.
- **Overlap:** AUD-1b-2 (periodic lease shorter than the job timeout) is the
  server-side twin of this "timer shorter than the work" shape.

### AUD-12a-4 `_startWorkers`/`_stopWorkers` are not serialised: a stop that runs during a start can finish first and leave the socket, timers and subscriptions running
- **Severity:** P3
- **Confidence:** likely
- **Where:** [engine.dart:370-372](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/engine.dart#L370) sets `_workersRunning = true` before the first `await`, [engine.dart:409-411](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/engine.dart#L409) clears it before the teardown awaits, and [engine.dart:602-606](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/engine.dart#L602) calls `_stopWorkers` from a socket-state listener
- **What:** both methods are async and both flip the guard before doing
  their work, so they interleave. If `stop()` runs while `start()` (or
  `_activate`) is between `calls.recoverUnfinished()` and
  `_inbound.startRealtime()`, the stop tears down everything that exists,
  returns, and *then* the start opens the socket and subscribes `_callWakes`.
  The engine reports `stopped` while a socket, a heartbeat timer and an event
  subscription are live and writing to the database. The reverse order
  starts nothing while the status says running.
- **Trigger:** `_handleSessionEnded` arriving from the realtime state listener
  while `AccountService`'s sign-in callback is still in `_startWorkers`; or
  the app's lease-lost handler calling `engine.stop()`
  ([helix_runtime.dart:205-211](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/helix_runtime.dart#L205))
  during a start. Both are narrow races, not normal paths.
- **Evidence:** `_startWorkers` awaits `calls.recoverUnfinished()` and
  `_inbound.startRealtime()` between the guard and the subscription; nothing
  awaits the previous transition. `InboundRunner.stopRealtime` also waits up
  to a retry sleep for the in-flight envelope
  ([inbound_runner.dart:97-108](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/inbound_runner.dart#L97)),
  which widens the window.
- **Impact:** two engines on one database (the app's and a push isolate) are
  guarded by the lease and by `StaleSessionState` (review C-01), so this does
  not corrupt the ratchet; the cost is a leaked socket and timers under a
  stopped engine, and a status that does not describe what runs.
- **Fix sketch:** serialise transitions (S1): one `Future<void> _transition`
  chain, `_workersRunning` set after the work completes (or derived from a
  state enum), and `_stopWorkers` awaiting the start that precedes it.
- **Test that proves it:** a start whose `calls.recoverUnfinished` is
  delayed; call `stop()` mid-start; after both complete assert
  `api.realtime.state` is stopped and no `connected` state is ever observed.
- **Overlap:** AUD-12a-5 (partial transitions), review finding C-01 (two
  engines), the app's lease (sweep 14).

### AUD-12a-5 `signOut()` runs the local wipe after three fallible steps outside any `finally`, so a throw leaves the status `running` with workers stopped and tokens possibly cleared
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [engine.dart:528-541](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/engine.dart#L528)
- **What:** `_stopWorkers()` → `account.leaveOnServer()` →
  `auth.forget()` → `media.wipeFiles()` → `db.wipeAll()` →
  `_forgetIdentity()` → hard wipe, each awaited in sequence. Only the last
  step is in a `try/finally` (which sets the status). A throw from
  `_stopWorkers` (host media teardown), `media.wipeFiles` (filesystem) or
  `db.wipeAll` (a lock, a closed database) aborts the sequence: the workers
  are stopped, the session may already be forgotten, the rows remain, the
  identity is still loaded and the status is still `running`. That is a
  state the rest of the engine treats as "signed in and working".
- **Trigger:** a filesystem or database error during a sign-out, or a media
  release that throws on a broken call.
- **Evidence:** `leaveOnServer` is documented best-effort but catches only
  `HelixApiException`
  ([account_service.dart:643-655](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/account_service.dart#L643));
  `media.wipeFiles()` and `db.wipeAll()` have no catch. `_handleRevoked`
  ([engine.dart:575-599](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/engine.dart#L575))
  already has the right shape (guarded wipe, status in `finally`).
- **Impact:** "Sign out" can leave the data the person asked to remove, in a
  state the UI shows as signed in. With AUD-12a-1 a later session end then
  blocks the sign-in, so the leftover is not even reachable through the
  normal path.
- **Fix sketch:** one `try/finally`: the local wipe and `_forgetIdentity` in
  the body; `_setStatus(signedOut)` in the `finally`; the server call last
  and `on Object` (it is already documented as best effort). Keep the order
  local-first for the token: the revoke call needs the session, so either
  revoke first (as now) or capture the token before forgetting.
- **Test that proves it:** a `hardWipe`/blob store whose `wipeFiles` throws;
  `signOut()` propagates the error, and the engine must still end
  `signedOut` with the identity forgotten (today it ends `running` with the
  identity loaded).
- **Overlap:** the app's `SignOutAction`
  ([session_providers.dart:66-81](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/session_providers.dart#L66))
  calls `ensureWiped()` after the engine's sign-out, which covers the files
  but not a throw from `signOut` itself.

### AUD-12a-6 `start()` ignores the current status and changed flags; the backup timer is unreachable unless `background` is on
- **Severity:** P3
- **Confidence:** confirmed
- **Where:** [engine.dart:325-339](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/engine.dart#L325) (second call returns early; a revoked engine becomes `signedOut`) and [engine.dart:373-378](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/engine.dart#L373) (`if (_background || _realtime)` inside `if (_background)`)
- **What:** three small state-machine gaps in one public method. (a) A second
  `start()` while running returns at once after overwriting `_realtime` and
  `_background`, so a host that starts `background: false` and later wants
  the socket gets nothing (and the reverse leaves the socket on). (b)
  `start()` on a `revoked` engine reloads a (wiped) identity and reports
  `signedOut`, which the app renders as the ordinary sign-in page instead of
  the revocation notice it keys on; `wipedRuntimeResetProvider` then does not
  fire because the status never became `revoked` again. (c) The backup
  schedule is started inside the `_background` block while its own condition
  says "background or realtime", so the documented `start(realtime: true,
  background: false)` host runs no backup timer — the condition is dead.
- **Trigger:** a host that reuses one engine across modes, or calls `start()`
  after a revocation. No production caller does either today (the app passes
  one `!headless` value for both flags,
  [helix_runtime.dart:174](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/helix_runtime.dart#L174);
  the CLI one `live`), so this is latent API debt rather than a live bug.
- **Evidence:** the early return is before any identity load; the
  `if (_background || _realtime)` is textually inside `if (_background)`;
  `stop()` deliberately keeps `revoked`
  ([engine.dart:425-428](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/engine.dart#L425)),
  showing the status is meant to be terminal.
- **Impact:** a mode switch silently does nothing; a revocation notice can be
  replaced by sign-in; a documented flag combination loses backups. All
  latent, all easy to fix while the lifecycle is being serialised.
- **Fix sketch:** make `start` idempotent by *transition*, not by status:
  if already running, apply a mode change by starting/stopping the missing
  workers; make `revoked` terminal (`throw EngineStateException` or return);
  lift `backup.start()` out of the `_background` block or fix the condition
  and its comment. Fold into S1.
- **Test that proves it:** start with `background: false, realtime: true`,
  assert the socket runs and the backup schedule is armed (or that the
  documented contract says otherwise); start twice with different flags and
  assert the change took effect; call `start()` on a revoked engine and
  assert the status stays `revoked`.
- **Overlap:** AUD-12a-1 (status semantics), AUD-12a-4 (same lifecycle).

## Structural proposals

### S1 One serialized lifecycle object inside `Engine`
- **Current shape:** public methods (`start`, `stop`, `close`, `signOut`,
  `deleteAccount`) and four internal callbacks (`_activate`,
  `_handleRevoked`, `_handleSessionEnded`, lease-lost) mutate
  `_workersRunning`, `_revoking` and `_status` around `await`s, with no
  mutual exclusion.
- **Hazard:** AUD-12a-4, AUD-12a-5, AUD-12a-6; every new callback adds
  another interleaving to reason about.
- **Proposed shape:** a private `_Lifecycle` with one `Future<void> _tail`
  and an enum (`idle`, `starting`, `running`, `stopping`, `signedOut`,
  `revoked`); `start`, `stop`, `signOut` and the callbacks queue on `_tail`,
  the status is set from inside the transition, and `stop` is idempotent.
- **Migration:** internal to `Engine`; no public API change, no DB change.
  Move the bodies of `_startWorkers`/`_stopWorkers` unchanged.
- **Risk:** a `stop` queued behind an in-flight `start` waits for it, and an
  in-flight inbound retry sleeps up to 30 s
  (`inboundRetry.max`); measure `stop()` latency in the app's shutdown path
  or cap it.
- **Size:** ~150 lines in `engine.dart` plus ~80 lines of tests.

### S2 One session-state owner shared by the transport and the engine
- **Current shape:** three places decide what "signed out" means —
  `DeviceSessionAuth._refresh` (forget + throw), `Engine._handleSessionEnded`
  (status only), and `AccountService._requireEmpty` (refuse while an account
  exists) — plus the app's status mapping.
- **Hazard:** AUD-12a-1 and AUD-12a-2: the transport can end a session the
  engine cannot recover, and the engine's recovery path is the one method
  that refuses.
- **Proposed shape:** a small `SessionState` object owned by `EngineContext`
  (`active`, `ended`, `revoked`) with `end()`/`revoke()`/`beginSignIn()`;
  `_refresh`'s "refused" outcome calls back into it (through the existing
  `reauthenticate` seam or a new `onRejected` callback) instead of deciding
  alone; `_requireEmpty` consults it and admits a same-account sign-in.
- **Migration:** expand (add the object and the callback, keep the current
  behaviour), migrate (`_refresh` reports instead of throwing first),
  contract (remove the duplicate guards). Engine + api, no DB change.
- **Risk:** touches the auth/engine seam that every request crosses; keep the
  transport's exception contract unchanged.
- **Size:** ~200 lines across `auth.dart`, `engine.dart`,
  `account_service.dart`, plus app copy for the "session ended" page.

## Coverage notes

- `errors.dart`: sealed family, messages carry no content; the two stale-state
  exceptions are the review-C-01 mechanism and are not re-litigated here.
  `TransientEngineException.cause` holds an arbitrary object — fine, never
  rendered.
- `events.dart`: every event is shaped for UI/notification use; `IncomingNotice`
  for missed calls (`messageRowid: 0`) is consistent with `MissedCallEvent`'s
  doc. No finding.
- `context.dart`: `emit` guards a closed controller; `close()` only closes the
  events controller (the status controller is closed by `Engine.close`, also
  guarded). No finding.
- `KeyedLock`: `previous` tails always complete normally (errors are not
  forwarded), so a failed action does not poison the queue; `runAll` sorts
  keys. No finding.
- `RandomAdapter`: 53 bits from the CSPRNG with modulo reduction — fine for
  ids and jitter, and documented as not for keys. No finding.
- `InboundRunner.fetchOnce` runs each envelope through the same `_serial`
  queue as the socket and is single-flight (`_fetching`), so the app's
  resume-time `syncOnce` does not race the socket's processing
  ([inbound_runner.dart:232-259](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/inbound_runner.dart#L232)).
- `_processRetrying` retries a transient failure until `_running` goes false;
  `stopRealtime` therefore waits up to one retry sleep (30 s) — a slow stop,
  not a deadlock.
- Not covered here (other 12 units): outbox/sender (12b), apply/inbound
  (12c), crypto stores (12d), groups (12e-12f), account/features (12g), calls
  (12h), transfers (12i-12j), backup (12k-12m).
