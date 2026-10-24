# Sweep 14b — app `lib/core/`: the lock, the network, and the resume

**Where:** `helix_remote/app/lib/core/` — `platform/tls_pinning.dart` (214),
`security/app_lock.dart` (355), `security/app_settings.dart` (155),
`security/device_auth.dart` (45), `lifecycle/app_lifecycle_host.dart` (79),
`platform/saved_accounts.dart` (98), `platform/network_probe.dart` (66),
`platform/secret_clipboard.dart` (61), `platform/share_adapter.dart` (56),
`platform/picker_cleanup.dart` (25), `platform/chat_platform.dart` (64) —
about 1,220 lines. Cross-reads: `main.dart:42-91` (the zone and its two error
handlers), `core/engine/helix_runtime.dart:136-244` (where pinning is applied
and the backup upload gate reads the network),
`features/settings/application/media_policy_sync.dart`,
`features/settings/application/settings_providers.dart:209-245` (the
enable-time check), `features/calls/application/call_effects.dart:30-110`,
`calls/call_host.dart`, and the tests that cover the area
(`test/app_lock_test.dart`, `test/tls_pinning_test.dart`,
`test/settings/a3b_rules_test.dart:260-330`).

This is the app's own security and process glue, below every screen: the
certificate pin, the app lock, the network reading that decides metered
transfer, and what happens when the app is resumed. The certificate pin is
careful (bounds-checked DER, fail-closed, never on in a debug build, applied to
both the REST client and the socket factory at
[helix_runtime.dart:149-159](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/helix_runtime.dart#L149-L159)).
The defects are all in *answers the app gives without looking again*: a network
kind decided from the wrong interface, a relock suppressed by a call and never
reconsidered, an unlock that cannot say why it can never pass, and a resume
that asks for a runtime on a page that has none.

## Findings

### AUD-14b-1 A VPN on mobile data is classified as Wi-Fi, so "Wi-Fi only" downloads and the backup gate run over mobile data

**Severity:** P3  **Confidence:** confirmed
**Where:**
[network_probe.dart:31-39](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/network_probe.dart#L31-L39)
(`classify`),
[media_policy_sync.dart:30-35](file:///J:/Projects/helix/helix_remote/app/lib/features/settings/application/media_policy_sync.dart#L30-L35)
(`autoDownloadLimit`),
[helix_runtime.dart:237-242](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/helix_runtime.dart#L237-L242)
(the backup upload gate).
**What:** `DeviceNetworkProbe.classify` returns `unmetered` when *any*
reported transport is `wifi`, `ethernet`, `vpn` or `other`. `vpn` is not a
transport: it is a tunnel over one. On a phone that is on mobile data with a
VPN up, `Connectivity` reports `vpn` (and often nothing else), so the app
answers "unmetered" for a connection that is in fact metered.
**Trigger:** any user who keeps a VPN on — the likeliest user of a
privacy-focused messenger — and has chosen "Wi-Fi only" for automatic
downloads, or has backup-over-mobile off.
**Evidence:** `final unmetered = results.any((r) => r == wifi || r == ethernet
|| r == vpn || r == other); if (unmetered) return NetworkKind.unmetered;`
([network_probe.dart:31-38](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/network_probe.dart#L31-L38)).
Both consumers treat `unmetered` as "Wi-Fi" without qualification: the media
policy writes the full per-kind ceiling ([media_policy_sync.dart:33-34](file:///J:/Projects/helix/helix_remote/app/lib/features/settings/application/media_policy_sync.dart#L33-L34))
and the backup remote uploads whenever `network.current() != mobile`
([helix_runtime.dart:241](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/helix_runtime.dart#L241)).
The classification test covers only `[mobile]`, `[mobile, wifi]`, `[none]` and
`[]` ([a3b_rules_test.dart:260-276](file:///J:/Projects/helix/helix_remote/app/test/settings/a3b_rules_test.dart#L260-L276));
`vpn` and `other` appear nowhere in the tests.
**Impact:** a phone on a metered plan downloads media up to 50 MiB per video
unasked, and uploads backups, with the person believing both were limited to
Wi-Fi. On a metered or roaming plan that is a bill, not a bug report.
**Fix sketch:** `unmetered` only for `wifi`/`ethernet`. For a bare `vpn` (where
the plugin does not report the underlying transport), take the conservative
answer for a privacy app — treat it as `mobile` — or read the platform's metered
flag instead of the transport list. Keep `other` metered too: it is the
plugin's remainder bucket. Add `[mobile, vpn]`, `[vpn]` and `[other]` to the
classification test with the chosen expectation written out.
**Test that proves it:** `classify([mobile, vpn]) == NetworkKind.mobile` and
`classify([vpn]) == NetworkKind.mobile`; a media-policy test that a
`wifi`-policy writes `MediaSettings.never` on `[vpn]`.
**Overlap:** the consumer half is AUD-14a-1 (the same media policy, left
unapplied after a signed-out start). Both are fixed by "the policy is the
transport's answer, re-read when the transport changes".

### AUD-14b-2 A call that outlasts the relock time cancels the relock for that return; after hang-up the app stays open

**Severity:** P3  **Confidence:** confirmed
**Where:**
[app_lock.dart:128-135](file:///J:/Projects/helix/helix_remote/app/lib/core/security/app_lock.dart#L128-L135)
(`onResumed`),
[app_lock.dart:113-117](file:///J:/Projects/helix/helix_remote/app/lib/core/security/app_lock.dart#L113-L117)
(`lockIfEnabled` skips while a call is live),
[app_lock.dart:266-269](file:///J:/Projects/helix/helix_remote/app/lib/core/security/app_lock.dart#L266-L269)
(the gate stays open while the bypass is set),
[call_effects.dart:108](file:///J:/Projects/helix/helix_remote/app/lib/features/calls/application/call_effects.dart#L108)
(the bypass is cleared on end, and nothing relocks).
**What:** `onResumed` decides once whether the absence exceeded
`relockAfterSeconds` and then forgets the start time (`_backgroundedAt =
null`). If a call is live at that moment, `lockIfEnabled` returns without
locking — the right call while the call UI is up. But the bypass is a plain
boolean that the call effects clear when the call ends
([call_effects.dart:108](file:///J:/Projects/helix/helix_remote/app/lib/features/calls/application/call_effects.dart#L108));
nothing re-runs the relock decision, and `lockIfEnabled` has no other caller
outside `onBackgrounded`/`onResumed`.
**Trigger:** relock set to 1 minute (the default), a call on speaker with the
screen off for several minutes, the person comes back to the call screen (resume
during the call), then hangs up. The app underneath is unlocked although the
person was away far longer than the setting.
**Evidence:** `if (since == null) return; final away = ...; if (away <
_relockAfter) return; lockIfEnabled();` — `since` is cleared on every resume
([app_lock.dart:129-134](file:///J:/Projects/helix/helix_remote/app/lib/core/security/app_lock.dart#L129-L134)).
`lockIfEnabled` is `if (!enabled) return; if (_callActive?.call() ?? false)
return; locked.value = true;` ([app_lock.dart:113-117](file:///J:/Projects/helix/helix_remote/app/lib/core/security/app_lock.dart#L113-L117)).
`_finish` clears the bypass and never asks the lock
([call_effects.dart:101-109](file:///J:/Projects/helix/helix_remote/app/lib/features/calls/application/call_effects.dart#L101-L109)).
`test/app_lock_test.dart` has no call in any of its four relock tests (the
suite's fake call state stays false).
**Impact:** the relock setting — the one thing that protects a phone left on a
table — can be defeated for the rest of the session by any call longer than the
chosen time. An attacker who picks up the phone after the owner's call ends
gets an open app, not the lock screen.
**Fix sketch:** make the bypass a state to be re-evaluated, not a veto with no
memory: remember `_awayLongEnough` when a resume crossed the threshold, and
have the call effects (or a listener on `callInProgress`) re-apply
`lockIfEnabled()` when the bypass drops while the app is foregrounded. The
cheap version is one call to `AppLock.lockIfEnabled()` at the end of
`CallEffects._finish`.
**Test that proves it:** an `AppLock` unit test: enable with 60 s, background,
resume 120 s later with `callInProgress` true (no lock), clear the bypass and
assert `locked` is true.
**Overlap:** none filed; `call_effects.dart` is otherwise 14g/14i material.

### AUD-14b-3 After the phone's screen lock is removed, the app lock can never be passed and the screen does not say why

**Severity:** P3  **Confidence:** confirmed
**Where:**
[app_lock.dart:139-158](file:///J:/Projects/helix/helix_remote/app/lib/core/security/app_lock.dart#L139-L158)
(`unlock`),
[app_lock.dart:160-169](file:///J:/Projects/helix/helix_remote/app/lib/core/security/app_lock.dart#L160-L169)
(`_systemPrompt` fails closed),
[app_lock.dart:329-349](file:///J:/Projects/helix/helix_remote/app/lib/core/security/app_lock.dart#L329-L349)
(the only action is "Unlock" again),
[settings_providers.dart:216-234](file:///J:/Projects/helix/helix_remote/app/lib/features/settings/application/settings_providers.dart#L216-L234)
(the capability is checked only when the lock is turned on).
**What:** turning the lock on requires `deviceAuthenticator.isAvailable()` and
one successful confirmation ([settings_providers.dart:221-230](file:///J:/Projects/helix/helix_remote/app/lib/features/settings/application/settings_providers.dart#L221-L230)).
Nothing re-checks later. If the person then removes the phone's PIN/pattern
(Android) or Hello/PIN (Windows), `LocalAuthentication().authenticate` fails,
`_systemPrompt` returns false, and `unlock` keeps `locked` true; the lock screen
shows "Not unlocked. Try again." with a single Unlock action. The seam for the
answer already exists — `AppLock.deviceSupportsLock`
([app_lock.dart:43](file:///J:/Projects/helix/helix_remote/app/lib/core/security/app_lock.dart#L43))
— and nothing outside its own file calls it.
**Trigger:** lock on, then the person changes their phone's screen lock and
removes it (or a device-management policy removes it), then opens Helix.
**Evidence:** `unlock` catches every platform refusal into `false` and clears
`_forced` only on success ([app_lock.dart:146-157](file:///J:/Projects/helix/helix_remote/app/lib/core/security/app_lock.dart#L146-L157));
`LockActions` carries only `onUnlock`
([app_lock.dart:347](file:///J:/Projects/helix/helix_remote/app/lib/core/security/app_lock.dart#L347)).
Because the credential prompt accepts a *newly set* screen lock, the person can
get back in by adding one — but nothing on the screen says so, and the app
gives the same "try again" on every launch until they work it out.
**Impact:** a support dead end that reads like data loss: the app holds the
database key, the only in-app way out is clearing app data (which destroys
local history), and the screen names neither cause nor cure. It is reachable
without anyone misusing the app, because the lock follows a credential the
phone owns.
**Fix sketch:** on an unlock failure, ask `deviceSupportsLock()`; if false,
show a message with the cure — "Orbit is locked with your phone's screen lock,
and this phone no longer has one. Set a PIN, pattern or fingerprint in the
phone's settings and unlock again." Do **not** fail open and do not offer an
in-app wipe as the first answer. Keep the existing "try again" for a real
biometric mismatch.
**Test that proves it:** a widget test with `authenticator` returning false and
`deviceSupportsLock` returning false: the lock stays, and the screen names the
phone's screen lock as the missing piece; the same with `deviceSupportsLock`
true shows "try again".
**Overlap:** overlaps the settings page half in sweep 15a's area (the
enable-time check) only by file; no filed finding.

### AUD-14b-4 Every resume on the sign-in screen throws `NoServerChosen` into the crash log

**Severity:** P3  **Confidence:** confirmed
**Where:**
[app_lifecycle_host.dart:42-46](file:///J:/Projects/helix/helix_remote/app/lib/core/lifecycle/app_lifecycle_host.dart#L42-L46)
(the call site),
[app_lifecycle_host.dart:66-69](file:///J:/Projects/helix/helix_remote/app/lib/core/lifecycle/app_lifecycle_host.dart#L66-L69)
(`await ref.read(runtimeProvider.future)`),
[runtime_providers.dart:385-389](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/runtime_providers.dart#L385-L389)
(the throw),
[main.dart:51-90](file:///J:/Projects/helix/helix_remote/app/lib/main.dart#L51-L90)
(the zone handler that records it as a crash).
**What:** `unawaitedResume()` returns a future that nothing awaits, and its
first statement can throw. With no account chosen — the sign-in page, which is
where the app spends time on a fresh install or after sign-out — `runtimeProvider`
throws `NoServerChosen`, which the zone handler records with
`AnomalyLog.crash`.
**Trigger:** open the app signed out, switch away, switch back. Every resume
writes one crash entry.
**Evidence:** `unawaitedResume();` with no `unawaited(...)`, `try` or
`.catchError` ([app_lifecycle_host.dart:46](file:///J:/Projects/helix/helix_remote/app/lib/core/lifecycle/app_lifecycle_host.dart#L46));
the body awaits the provider before its own `try` starts
([app_lifecycle_host.dart:67-71](file:///J:/Projects/helix/helix_remote/app/lib/core/lifecycle/app_lifecycle_host.dart#L67-L71)).
Only `backup_gateway.dart:330` catches `NoServerChosen` anywhere in `lib/`
([backup_gateway.dart:330](file:///J:/Projects/helix/helix_remote/app/lib/features/backup/application/backup_gateway.dart#L330)).
`runtimeProvider` documents the throw as "the normal 'nobody is signed in'
state, not a failure" ([runtime_providers.dart:402-406](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/runtime_providers.dart#L402-L406)).
**Impact:** the crash log — the one place the app is supposed to record things
that actually went wrong — fills with a normal state, drowning real entries and
poisoning any crash-rate signal the log is used for. Nothing user-visible breaks.
**Fix sketch:** guard the whole body: resolve the runtime with
`on NoServerChosen { return; }`, or check `activeAccountProvider` first. Keep
the existing best-effort `try` for the sync call.
**Test that proves it:** a widget test that pumps the host with no account,
resumes the app, and asserts `AnomalyLog` recorded nothing (against a counting
sink).
**Overlap:** AUD-14a-1 is the same provider throwing into a provider body; this
is a direct `read`, so the two fixes are independent.

## Verified safe (read, no finding)

- **Certificate pinning** (`tls_pinning.dart`, all 214 lines): the DER walk
  checks every length and end (`_Tlv.read`, :193-213), the SPKI slice is bounded
  by the certificate (`_subjectPublicKeyInfo`, :178-182), `accepts` refuses
  anything it cannot parse and anything whose host is not pinned
  (:104-111), `run` replaces the trust store with an empty one so every
  certificate reaches the callback (:147-156), and both the REST client and the
  realtime socket factory are built inside it
  ([helix_runtime.dart:149-159](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/helix_runtime.dart#L149-L159)).
  Debug builds never pin (`fromDefinedPins`, :72-82). No gap found.
- **Secret handoff** (`secret_clipboard.dart`): the clipboard is cleared after a
  minute only if it still holds the same text; the timer is not tied to a
  widget. Fine.
- **Share adapter** (`share_adapter.dart`): a dismissed or unavailable share
  returns false; exceptions are caught. Fine.
- **Picker temporary files** (`picker_cleanup.dart`): a platform without the
  plugin and any failure are swallowed on purpose; the copies are cleared after
  a send and at sign-out. Fine — and documented as such.
- **Device auth** (`device_auth.dart`, 45 lines): `isAvailable` and `confirm`
  both fail closed. Fine.
- **Saved accounts** (`saved_accounts.dart`): reads/writes with `try` around the
  platform and no secrets (server label, account id). Fine.
- **`AppLock.completeColdStart`** (:78-88): the "unreadable" path forces the
  lock, and `coldStartDone` is set exactly once. The cold-start-during-a-call
  branch (`&& !callInProgress.value`) is unreachable in practice: a fresh
  process has no call, and an engine that outlives the process is the headless
  one, which never shows the gate. Not filed.
- **`AppLock.onBackgrounded` during the prompt** (`_authenticating`, :120-126):
  the prompt's own pause is not counted. Fine.
- **`chat_platform.dart`** (:47-50): returns a fresh `DeviceAudioPlayer()` per
  call; disposal is the caller's business (noted for 14e, not filed here).

## Coverage notes

- Read in full: the eleven files in **Where** (1,218 lines by `wc -l`).
- Not read in this sweep, deferred: `platform/{attachment_picker,
  media_sanitizer, media_temp, video_frames, file_actions, device_camera,
  app_blob_store, flutter_media_processor, storage_usage, qr_encoder,
  app_info, phone_numbers, contacts_access, device_phone_book}.dart`,
  `platform/{audio_player, device_audio_player, video_player,
  device_video_player, voice_recorder, device_voice_recorder}.dart`,
  `links/`, `router/`, `push/`, `notifications/`, `sounds/`, `diagnostics/`,
  `chat/`, `people/`, `format/`, `calls/`, `theme/`, `util/` — planned as
  14c–14j.
- Grep-verified rather than read: `lockIfEnabled` has only the two callers
  inside `app_lock.dart`; `TlsPinPolicy`/`socketFactory`/`appliesTo` have no
  call sites outside `helix_runtime.dart` and the pinning test;
  `NoServerChosen` is caught only in `backup_gateway.dart`.
- Test coverage checked: `app_lock_test.dart` (7 tests + 4 relock tests, no
  call state, no missing-credential case), `tls_pinning_test.dart` (the pin,
  the socket factory, debug and release defaults), `a3b_rules_test.dart:260-330`
  (network kinds and the backup gate, no VPN).

## Structural proposals

**S14b-1 — the lock's answer is derived on every transition, not decided once.**
Today "should the app be covered now" is three independent decisions
(`onBackgrounded`, `onResumed`, the call bypass) that each look at a different
piece of state and forget the rest. One function,
`covered(enabled, awaySince, callActive, coldStart)`, called at every
transition (background, resume, call start/end, setting change), would make
14b-2 and 14b-3 impossible by construction and would give the missing-credential
case a place to answer. One seam, ~15 lines.

**S14b-2 — the network answer comes from the platform's metered flag.**
`NetworkKind` is inferred from a list of transports, which cannot see what a
VPN runs over. The seam should ask the platform "is this connection metered?"
(the Android API that `connectivity_plus` wraps exists for exactly this) and
keep `none`/`metered`/`unmetered` as the result, with the VPN and `other`
buckets resolved by the platform rather than by a guess in Dart. This is the
same seam AUD-14a-1 made fragile by resolving the runtime once; both fixes turn
a startup snapshot into a live reading.
