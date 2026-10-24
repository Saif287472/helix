# Sweep 12j — engine: presence and push

Read line-by-line: `features/presence_service.dart` (164),
`features/push_service.dart` (24), the app's push wiring
(`core/push/push_registration.dart` 157, `push_background.dart` 189,
`push_token_source.dart` 102), and the cross-reads that decide them: the
direct inbound typing branch and its blocked-check placement
(`messaging/inbound.dart:211-331`), the group typing branch
(`groups/group_inbound.dart:130-180`), the server's `_accept` block and
ephemeral paths (`messaging/module.dart:300-401`), the push-token routes and
their clearing on device removal (`identity/module.dart:198`,
`http/identity_routes.dart:335`), and `Engine.signOut` (`engine.dart:521-541`).
~700 lines; small because the two services are thin and the weight is in their
callers.

Verdict: both are sound. Typing is ephemeral both ways, throttled, expires on
its own, never starts a session and is refused by the server for a blocked
recipient; the push token is re-sent at every engine start and after every
rotation, is per-device, and is cleared when the device leaves. One unwired
promise (AUD-12j-1, Idea).

---

### AUD-12j-1 There is no way to stop server wake-ups short of signing out; `PushService.unregister` is dead code with a promise no screen keeps

**Severity** Idea  **Confidence** confirmed

**Where**
- [`features/push_service.dart:22-23`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/push_service.dart#L22) — "Stops wake-ups (the user turned notifications off)", implemented as `identity.clearPushToken`.
- [`app/core/push/push_registration.dart:45-66`](file:///J:/Projects/helix/helix_remote/app/lib/core/push/push_registration.dart#L45) — only `register` is ever called (`engineRunning`/`_send`); nothing in `app/lib` calls `unregister` (grep).
- [`server/.../identity/module.dart:198`](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/module.dart#L198) — the token is cleared only when the device is removed.

**What** The engine offers a way to stop push wake-ups and documents it as the
"notifications off" path, but no app code calls it and no settings screen
offers it: notifications are controlled only by the OS permission, per-chat
mutes and the preview toggle. A person who revokes the OS permission still
gets a data-only wake-up on every message (the app then shows nothing), and the
only way to stop them is sign-out or deleting the account.

**Trigger** Any user who wants no push traffic (battery, or not wanting the
timing of messages to reach Google) but wants to keep the account.

**Evidence** `unregister` has no caller; `pushRegistrationProvider` wires only
`engine.push.register`; the settings gateway's notification section
(`settings_gateway.dart:84-88`) has only mute/unmute and preview.

**Impact** Small and user-visible only as battery/noise; also the dead method
implies a control that does not exist. Not a security defect — the wake-up
carries no content by design.

**Fix sketch** Either delete `unregister` and its doc, or add a "Push
notifications" switch that calls it (and re-registers on enable), which also
gives the OS-permission-refused case a clean server-side counterpart.

**Test that proves it** Engine test: `push.unregister` clears the token
(`identity.clearPushToken` request observed); app test for the settings switch
if one is added.

**Overlap** AUD-1b-1 (push dedupe keys), none otherwise.

---

## Verified safe (checked, no finding)

- **Typing never becomes a session.** `sendTyping` uses
  `readyWithoutSetup(peer)` (presence_service.dart:107), so an indicator cannot
  start a session or fetch prekeys; a group indicator rides the sender key with
  `ephemeral: true` and no key distribution (presence_service.dart:143-149,
  `group_sender.dart:113`).
- **Throttling.** `started` at most once per `typingSendInterval` per chat
  (presence_service.dart:91-100); `stopped` is always sent and clears the
  throttle. A failed send is swallowed by design.
- **Receiving.** The direct path only accepts a `DirectConversation` addressed
  to this account from a non-self account (inbound.dart:317-331); the group
  path requires the group conversation id to match and a non-self sender
  (group_inbound.dart:150-165). Expiry closes the indicator even if no
  `stopped` arrives (presence_service.dart:64-67).
- **Blocks hold.** The server drops ephemeral payloads for recipients who
  blocked the sender in the same `_accept` path as stored messages
  (messaging/module.dart:348-374), so a blocked account's typing never reaches
  the blocker even though the engine's `_typing` has no local block check.
- **Ephemeral storage.** `_accept` returns before `recordSend` for ephemeral
  sends (messaging/module.dart:369-375), so typing writes no accepted row.
- **Push token lifecycle.** Registered on every engine start and on every
  token rotation (push_registration.dart:45-66), for the active account and
  for the other accounts on the device (`onToken` → `wakeSignedInAccounts`);
  cleared server-side when the device is removed, which `signOut` does
  (`engine.dart:531`). One token per device; a revoked device receives no
  envelopes.
- **Background isolate.** Builds its own engine per signed-in account, is
  fenced by `EngineLease` against the running app (`EngineAlreadyRunning`,
  push_background.dart:77-80), never reads content from the payload
  (push_background.dart:30-36, 38-50), closes its runtime in a `finally`
  (176-178), and one failing account does not stop the others (81-84).

## Coverage notes

- **A wake-up polls every signed-in account** (push_background.dart:56-86):
  the payload names no account by design, so each wake opens up to N encrypted
  databases and reads N mailboxes. Cost is bounded by the account slots on the
  device; noted, not filed.
- **`prepare()` asks for notification permission at the first engine start**
  (push_token_source.dart:68-72), i.e. right after sign-in. A UX choice, not a
  defect.
- **`PushRegistration` retries a failed registration only at the next engine
  start or rotation** (push_registration.dart:55-66); offline at start-up
  leaves no wake-ups until then. Acceptable for a best-effort channel.
- **Muted chats still wake the phone** (push carries no chat), and the
  background pass shows nothing for them via `MessageAlerts.alerts`
  (push_background.dart:126-141). Inherent to the metadata design.
- **`_lastSent` and `_typing` are only as large as the chats in use**; entries
  expire or are overwritten, and `close()` cancels the timers
  (presence_service.dart:155-163).
- **A removed group member cannot type into the group**: their send is refused
  by the server's membership check before any recipient sees it; the engine's
  group typing branch has no local membership check, but it has nothing to
  guard against beyond a stale sender key the server will not deliver.
