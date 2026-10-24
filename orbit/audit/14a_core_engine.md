# Sweep 14a — app `lib/core/engine/`: the runtime, its providers, the settings seam

**Where:** `helix_remote/app/lib/core/engine/` — `helix_runtime.dart` (360),
`runtime_providers.dart` (447), `session_providers.dart` (239),
`failure_copy.dart` (145), `server_policy.dart` (89), `local_settings.dart` (51),
`backup_policy.dart` (47), `post_sign_in.dart` (30), `clock.dart`,
`global_server.dart`. Cross-reads: `core/platform/{engine_lease,account_slots,
app_storage,contacts_access,device_phone_book}.dart`,
`features/settings/application/{settings_providers,media_policy_sync}.dart`,
`main.dart:160-200`, the engine's `close`/`stop`/`signOut`
(`engine.dart:425-541`), `packages/helix_remote_protocol/lib/src/headers.dart`,
`packages/helix_remote_api/lib/src/v2/transport/transport.dart:86-95`,
`realtime_client.dart:290-297`, and the app tests that cover this area
(`test/account_slots_test.dart`, `test/hard_wipe_test.dart`,
`test/settings/settings_pages_test.dart`).

This is the seam between the app and the engine: one runtime per account, the
account list in the keystore, the sign-out/wipe paths, and the settings store.
The runtime itself is careful — the lease is acquired before the database is
opened and released if opening fails, the wipe is step-wise, transfers are off
in both directions, and the server-address rule is applied at three points.
The defects are in what happens *around* a runtime's lifetime: who re-resolves
it, and what the app concludes when the keystore cannot be read.

## Findings

### AUD-14a-1 A setting stream keeps the runtime it was first read on, so a signed-out start leaves it broken and an account switch leaves it on the previous account

**Severity:** P2  **Confidence:** confirmed
**Where:**
[local_settings.dart:19-41](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/local_settings.dart#L19-L41)
(`EngineLocalSettings` resolves the runtime per call),
[local_settings.dart:50-51](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/local_settings.dart#L50-L51)
(`settingProvider`),
[runtime_providers.dart:385-400](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/runtime_providers.dart#L385-L400)
(the runtime is rebuilt and the old one closed),
[main.dart:174](file:///J:/Projects/helix/helix_remote/app/lib/main.dart#L174)
(media policy is read at start-up),
[media_policy_sync.dart:41-52](file:///J:/Projects/helix/helix_remote/app/lib/features/settings/application/media_policy_sync.dart#L41-L52),
[settings_providers.dart:34-55](file:///J:/Projects/helix/helix_remote/app/lib/features/settings/application/settings_providers.dart#L34-L55).
**What:** `EngineLocalSettings.watch` awaits `runtimeProvider.future` once and
yields from that engine's `settings.watch(setting)`. `settingProvider` returns a
plain `StreamProvider` (not auto-dispose) that depends only on
`localSettingsProvider`, which never changes, so the subscription lives for the
whole process and is never re-made when the runtime is replaced. If the first
read happens *before* an account is chosen, `runtimeProvider` throws
`NoServerChosen` ([runtime_providers.dart:387-389](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/runtime_providers.dart#L387-L389)),
the stream goes to `AsyncError`, and Riverpod does not retry. If the runtime is
later replaced (an account switch, a sign-out, a lease hand-off),
`runtimeProvider`'s `onDispose(runtime.close)` closes the old database and
client ([runtime_providers.dart:393](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/runtime_providers.dart#L393),
[helix_runtime.dart:328-339](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/helix_runtime.dart#L328-L339))
while every live setting stream stays attached to it. `set` re-reads
`runtimeProvider.future` on each call, so a toggle writes to the new account's
database while the value shown is the old account's (or an error).
**Trigger:** a fresh install, or any start on the sign-in page: `main` reads
`mediaPolicySyncProvider`, which watches the four media settings, before a
runtime exists. Later, "Add account" and switch after having opened Settings
(or simply after the app started, for the media settings).
**Evidence:** `main.dart:174` is executed at first frame, before
`_restoreServer()` can have finished (`main.dart:165`); the four
`settingProvider`s it watches are created then. `settingProvider`'s body is
`ref.watch(localSettingsProvider).watch(setting)` — no dependency on the
runtime — and `localSettingsProvider` is a constant `Provider`
([local_settings.dart:43](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/local_settings.dart#L43)).
`settings_pages_test.dart` overrides the `LocalSettings` seam itself, so no
test exercises the real stream across a runtime change.
**Impact:** on a device that started signed out, the media auto-download policy
is never applied for that run, so "Wi-Fi only" is not enforced — the engine
keeps whatever limits the previous run wrote, or its defaults. After a switch,
the Settings pages show and toggle one account's choices against another
account's database, and any setting first read while signed out stays in an
error state until the app restarts.
**Fix sketch:** have `settingProvider` depend on the runtime: inside its
`StreamProvider`, `final runtime = await ref.watch(runtimeProvider.future);`
then `yield* runtime.engine.settings.watch(setting)` (or key the provider on the
runtime's account), so a runtime change rebuilds the stream. Make the settings
seam runtime-owned rather than provider-owned (S14-1).
**Test that proves it:** a provider test with a `runtimeFactoryProvider` that
hands out two in-memory runtimes: read a setting while no account is chosen and
again after one is; then swap the active account and assert the stream emits the
second runtime's value and a `set` on it is visible. Today no test opens two
runtimes in one container.
**Overlap:** AUD-12a-4/12a-5 (engine start/stop lifecycle) are the same
"rebuild leaves something behind" shape, engine-side; S14-1 and S14-3 here.

### AUD-14a-2 An empty or undecodable account list is taken as "no accounts", and every secondary account's database and key is then deleted

**Severity:** P2  **Confidence:** confirmed
**Where:**
[runtime_providers.dart:165-168](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/runtime_providers.dart#L165-L168)
(`restore` trusts the load),
[runtime_providers.dart:192-209](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/runtime_providers.dart#L192-L209)
(`_deleteUnlisted` wipes folders, databases and keys),
[account_slots.dart:248-262](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/account_slots.dart#L248-L262)
(absent entry → empty list),
[account_slots.dart:286-305](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/account_slots.dart#L286-L305)
(a decode failure → empty list),
[app_storage.dart:35-42](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/app_storage.dart#L35-L42)
(which folders are enumerated),
[app_storage.dart:163-199](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/app_storage.dart#L163-L199)
(what `includeDatabase` deletes).
**What:** `AccountSlotStore.load()` returns `const AccountSlots()` both when
nothing was ever saved and when the saved value cannot be read: a missing entry
(`account_slots.dart:251-252`), a JSON value that is not a map or whose
`accounts` is not a list (`:288-290`), or a `FormatException` (`:302-305`).
`AccountsNotifier.restore` cannot tell those from "this device has no
accounts", and `_deleteUnlisted` then treats every folder under `accounts/` as
abandoned: `AppPaths.wipeLocalFiles(id, includeDatabase: true)` deletes
`helix_remote.db` and its `-wal`/`-shm`/`-journal`, the account folder is
removed, and `SecureKeyStore.forget(id)` deletes the key. Nothing asks, and
nothing records that it happened.
**Trigger:** the keystore entry is lost or corrupt while a second account
exists — a restore onto new hardware whose secure storage did not come with it,
an OS-level keystore reset, or a truncated write (Windows keeps the value in a
file). The next start deletes that account's local data before any screen is
shown.
**Evidence:** `account_slots_test.dart:451-470` is the only test of
`_deleteUnlisted`; it seeds a genuinely stray folder ('stray') next to the
listed one and asserts the stray one and its key are gone. That is the intended
case, and it is indistinguishable, in this code, from a lost list. The first
account is exempt only because its files live in the base folder and
`accountFolders()` lists just `accounts/<id>` (`app_storage.dart:35-42`).
**Impact:** silent, unrecoverable loss of every secondary account's local
history, attachments and key at start. The server stores no message body, so a
recovery phrase or a backup is the only other copy; on a device whose keystore
was just lost, the first account instead fails to open (`KeyUnavailable`) and
is offered a destructive reset — the person is told there, and told nothing
here.
**Fix sketch:** make the load a three-way result (`read` / `absent` /
`unreadable`) and never delete when it is absent or unreadable but folders
exist; record the pending slot (a sign-in that never finished) so its folder is
known-dead, and keep deleting only those. A lost list then costs an orphaned
folder, not a history.
**Test that proves it:** seed two account folders with keys, start with the
keystore entry missing, and assert both folders and keys survive; repeat with
a corrupt entry (a truncated JSON string) and assert the same; keep the existing
stray-folder test as the intended deletion case.
**Overlap:** B5's title ("without deleting history") but a different mechanism;
AUD-12a-1 is a stranded account, not a deleted one.

### AUD-14a-3 `HelixRuntime.close` skips the rest of its teardown when one step fails, but releases the lease anyway

**Severity:** P3  **Confidence:** likely
**Where:**
[helix_runtime.dart:328-339](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/helix_runtime.dart#L328-L339)
(`close`),
[helix_runtime.dart:254-277](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/helix_runtime.dart#L254-L277)
(`hardWipe`, the step-wise pattern the same file already uses),
[engine.dart:432-439](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/engine.dart#L432-L439)
(what can throw inside `Engine.close`),
[engine_lease.dart:105-108](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/engine_lease.dart#L105-L108)
(a foreground lease in the same process is simply replaced).
**What:** `close()` runs `engine.close()`, `api.close()` and `db.close()` in one
`try`, and releases the lease in `finally`. If the engine's close throws — it
closes backup, presence, calls, the status controller and the context, after
stopping the workers — the API client and the database are never closed, but
the lease file is deleted, so the claim that kept two engines off one database
is gone. The next `HelixRuntime.open` in the same process then replaces the
lease without waiting (`engine_lease.dart:105-108`), and the old engine may
still have workers if `stop` was the step that threw.
**Trigger:** any exception from `Engine.close` during an account switch, a
sign-out, a lease hand-off or the push-isolate teardown; no test forces one, so
the path is unexercised.
**Evidence:** `hardWipe` in the same class demonstrates the intended contract —
"every step is tried even when an earlier one fails, because stopping at the
first error would leave the rest on the phone" (`:250-253`) — and `close` does
not follow it.
**Impact:** a leaked HTTP client and an open SQLCipher handle, and in the worst
ordering a stopped engine is not actually stopped while a new runtime writes
the same ratchet state, which is the specific hazard `EngineLease` exists to
prevent.
**Fix sketch:** the same step-wise teardown as `hardWipe`, keeping the first
error and rethrowing it after; release the lease only once the database is
closed (or after both closing steps were attempted).
**Test that proves it:** a runtime whose engine is a fake whose `close` throws:
`HelixRuntime.close` still closes the API and the database, and the lease is
kept until the database is closed.
**Overlap:** AUD-12a-5 (`signOut` can throw before the wipe) is the same
pattern one layer down.

### AUD-14a-4 The app fills `x-helix-client` with its phone model, where the documented value is `<platform>/<app version>`

**Severity:** P3  **Confidence:** confirmed
**Where:**
[runtime_providers.dart:37-51](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/runtime_providers.dart#L37-L51)
(the factory's fallback config),
[runtime_providers.dart:73-80](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/runtime_providers.dart#L73-L80)
(the factory is built without one),
[runtime_providers.dart:414-420](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/runtime_providers.dart#L414-L420)
(the real configuration),
[helix_runtime.dart:150-156](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/helix_runtime.dart#L150-L156)
(`clientName: config.deviceName`),
[headers.dart:16-18](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/headers.dart#L16-L18),
[transport.dart:86-95](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/transport.dart#L86-L95),
[realtime_client.dart:290-297](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/realtime/realtime_client.dart#L290-L297).
**What:** the header is documented as `<platform>/<app version>`, "used for
compatibility gating and support". The runtime passes `EngineConfig.deviceName`
as the client name, and `runtimeFactoryProvider` never injects
`engineConfigProvider`, so every app runtime is built with the fallback
`'Helix device'` (`:49`) — the device information the engine does have (sent
explicitly at sign-in and at link start) never reaches the header. The CLI sends
`cli/2.0.0` and the admin console `admin/2.0.0`; the app, the client that
matters, sends one constant, and on a host without the device-info plugin even
the model is absent.
**Trigger:** every request and every realtime handshake the app makes.
**Evidence:** the comment at `runtime_providers.dart:45-47` says "the real
device name comes from `engineConfigProvider`", but the factory provider at
`:73-80` passes only the phone book; `engineConfigProvider` is read by
`sign_in_controller.dart:579` and `devices_providers.dart:538` and by nothing
else.
**Impact:** no server-side compatibility or support gating can ever read a
platform or a version from an app request; if one is added, every app build
looks the same. The device model, which the header was never meant to carry, is
transmitted on every request instead.
**Fix sketch:** pass `config: () => ref.read(engineConfigProvider.future)` at
the factory, and give the runtime a separate client name built from the
platform and the app version, rather than reusing the device name.
**Test that proves it:** a runtime opened through `runtimeFactoryProvider`
sends `x-helix-client: android/<version>` (the transport test at
`transport_test.dart:76` already asserts the CLI's value in this style).
**Overlap:** B9 (the client transport), AUD-11a-1.

## Verified safe

- **Hard wipe.** `HelixRuntime.hardWipe` closes, destroys the files, records
  the destruction, then runs the app's half; every step is attempted and the
  first error is rethrown afterwards. `ensureWiped` covers an engine that had
  nothing to sign out, and `wasWiped` keeps `close()` from closing a database
  the wipe already closed.
- **The lease.** A headless engine never takes over a live lease; a foreground
  engine waits for a headless one and then takes over; a different process's
  foreground lease is refused; a lost heartbeat stops the engine and says so
  once; `release` deletes the file only if it still holds its own claim.
- **The server-address rule.** `ServerPolicy.check` refuses anything but
  `https`, allows `http` only for three development hosts in a debug build,
  refuses user-info, query, fragment and non-ASCII hosts, and is applied at
  restore, at `useServer` and again in `HelixRuntime.open`.
- **Transfers.** `backupOptionsFor` keeps both history-transfer switches off
  (so a linked device receives nothing unasked and Pause is meaningful),
  supplies `gzip` to the engine, and gates only uploads on metered connections
  — downloads and the manual full backup are deliberately never blocked.
- **Failure copy.** No message names a host, a key, a code or an exception
  type; wait times come from the server's own `retryAfter`/`lockedUntil`; the
  anomaly-log call is the one reporting seam.
- **Account ids.** Every path use goes through `AppPaths`, which validates the
  id against `^[a-z0-9]{1,32}$` before joining it; a pending slot is never
  written to the keystore; `switchTo`, `remove` and `lost` refuse unknown or
  unsigned-in ids; the lock is dropped when the last account leaves.
- **Restore of the remembered server.** A stored address the policy refuses
  opens sign-in instead of a client; a preference for another signed-in account
  (a notification) is honoured and saved.
- **The runtime's identity.** `activeAccountProvider` is keyed by account id
  and server, so a second account on the same server gets its own runtime; a
  lease lost to a push isolate reopens rather than being ignored.

## Coverage notes

- Nothing exercises two runtimes in one provider container: every widget suite
  overrides `runtimeFactoryProvider` with one runtime or a throwing factory,
  and `settings_pages_test` overrides `LocalSettings` itself, which hides the
  real seam behind AUD-14a-1.
- `account_slots_test.dart:451-470` covers the stray-folder deletion, not a
  lost or corrupt list; there is no test for `_decode` returning empty.
- `hard_wipe_test.dart` covers the wipe steps and a failing wipe; no test makes
  `Engine.close` throw, which is the trigger for AUD-14a-3.
- The app-side value of `x-helix-client` is never asserted; the transport test
  asserts the CLI's.

## Structural proposals

**S14-1 — A setting belongs to the live runtime.** Hand `LocalSettings` (or a
small `Reader`) down from `runtimeProvider` instead of having a constant
provider that resolves the runtime per call. Every stream then follows the
runtime, and the read/write asymmetry in AUD-14a-1 disappears by construction.

**S14-2 — "Which accounts does this device have" is a three-way answer.**
Return read / absent / unreadable from `AccountSlotStore.load`, and delete a
folder only when it is recorded as abandoned (a pending slot the app itself
created), never because a list failed to load.

**S14-3 — One teardown contract.** `HelixRuntime.close` and `hardWipe` should
share the step-wise "try everything, rethrow the first" shape, and whoever
replaces the runtime should await the close before opening the next one, so the
lease, the database handle and the engine's workers always agree.
