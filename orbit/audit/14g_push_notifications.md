# Sweep 14g — app `core/`: push and notifications

**Where:** `helix_remote/app/lib/core/push/` — `push_registration.dart` (156),
`push_token_source.dart` (101), `push_background.dart` (188) — and
`core/notifications/` — `message_alerts.dart` (207),
`local_notifications.dart` (202), `call_notifications.dart` (305),
`notification_accounts.dart` (34), `notification_permission.dart` (40) —
1,233 lines. Cross-reads: `features/calls/application/call_effects.dart`
(279, `CallNotificationHandler` and the missed-call path),
`platform/notification_call_ringer.dart` (65, the ringer provider),
`call_platform.dart:211-260` (`CallRinger` and the alert fallback),
`main.dart:130-240` (which providers are kept alive and the launch
preference), `core/engine/session_providers.dart:51-129` (both sign-out paths),
`runtime_providers.dart:267-301` (`switchTo`/`remove`), the engine's
`calls_service.dart:786-889` (when a missed notice is emitted, and its `muted`
flag), `core/sounds/orbit_ringtones.dart` (channel ids and `chosen`), and
`android/app/src/main/AndroidManifest.xml` (permissions).

The privacy design holds throughout: a push payload is a wake-up carrying no
text, every notification's body is built from the local database or from a
pending call's caller id, the caller's name and the message preview are gated on
the person's previews setting and marked `private` when off, and the payload
itself carries ids only. The wake path is disciplined too — its own isolate,
its own engine under the engine lease, one pass at a time, closed in a
`finally`, and errors printed by type only. The seven findings are all in what
the notifications *say and clean up*: a count that restarts, an alert that
fires once, an account's shade entry that survives its removal, a press that
goes nowhere, and two missed-call rules that disagree with the rest of the app.

## Findings

### AUD-14g-1 A later wake-up replaces the message notification with only that pass's count

**Severity:** P3  **Confidence:** confirmed
**Where:**
[push_background.dart:132-141](file:///J:/Projects/helix/helix_remote/app/lib/core/push/push_background.dart#L132-L141)
(`count: audible.length`),
[local_notifications.dart:120-158](file:///J:/Projects/helix/helix_remote/app/lib/core/notifications/local_notifications.dart#L120-L158)
(`showMessages`: one id per account, title from `count`).
**What:** every background wake opens the account, syncs once, and posts
`audible.length` — the messages *that pass* fetched — into the account's one
notification, whose id is fixed per account (`messagesIdFor`). Posting the same
id replaces the previous notification, so the earlier count is discarded rather
than added to. A device that receives two pushes with two messages each shows
"2 new messages" (or "1 new message" after a single-message pass) while four
are unread. The running app does better within one background run
(`RunningAppAlerts._count` accumulates, message_alerts.dart:118-131), so the
two paths disagree about what the number means.
**Trigger:** the app is not running (or is force-stopped) and messages arrive
over two or more wake-ups — the normal case for a phone in a pocket on a busy
chat, or one woken once per message by the server's push.
**Evidence:** the count is the pass's list length (push_background.dart:129,
137); the id is `messagesIdFor(account)` (local_notifications.dart:139), whose
purpose is "one notification for a run of new messages … a newer run replaces
an older one (120-125, 137-140)"; the title is built from that number
(140); the only cancellation is `clearMessages` (162-163), called when the
account is opened, never when the next pass posts. Nothing reads the active
notification's existing count (the plugin exposes `getActiveNotifications`,
used elsewhere in `forgetRingtone`, call_notifications.dart:126-145).
**Impact:** the shade under-reports what arrived; a person returning after an
hour can see "1 new message" over a chat with twenty. It is a display defect
only — every message is in the database — but it is the one number the
notification exists to state.
**Fix sketch:** make the count cumulative for the notification's life: read the
active notification for the account (or persist the last posted count per
account) and add this pass's, or, if reading the shade is refused, post a title
without a number ("New messages") rather than a wrong one. The same accumulator
should serve `RunningAppAlerts` across an account switch (S14g-3).
**Test that proves it:** a fake notification plugin records shows; two wake
passes with two and then one notice produce "3 new messages" (today the second
show says "1 new message"). A running-app test where a switch away and back
keeps the count.
**Overlap:** S14g-3 (the count lives with the notification, not the poster);
14g-2 (the same notification's alert policy).

### AUD-14g-2 Every message after the first is posted silently, because the update is `onlyAlertOnce`

**Severity:** P3  **Confidence:** likely
**Where:**
[local_notifications.dart:151](file:///J:/Projects/helix/helix_remote/app/lib/core/notifications/local_notifications.dart#L151)
(`onlyAlertOnce: true`), with
[local_notifications.dart:22-49](file:///J:/Projects/helix/helix_remote/app/lib/core/notifications/local_notifications.dart#L22-L49)
(the four sound/vibrate channels) and
[message_alerts.dart:99-116](file:///J:/Projects/helix/helix_remote/app/lib/core/notifications/message_alerts.dart#L99-L116)
(who posts, and how often).
**What:** the message notification is posted once per arriving message (or per
wake pass) under a fixed per-account id, with `onlyAlertOnce: true`. On Android
that flag means the sound and vibration play only the *first* time a
notification is shown; every later update to the same notification is silent.
Because the notification is only cancelled when the account is opened
(`clearMessages`, local_notifications.dart:162-163; `RunningAppAlerts`'
resume/opened, message_alerts.dart:150-168), a person away from the phone hears
one alert and then, for as long as the notification stays in the shade,
nothing — though the channels are built to sound and vibrate and Settings >
Notifications offers both as separate choices (`notifySound`, `notifyVibrate`).
**Trigger:** two messages arrive while the app is in the background; the second
updates the shade silently. Repeat for every later message until the phone is
unlocked and the app opened.
**Evidence:** `onlyAlertOnce: true` at 151; the comment above it ("Silent: the
shade says something arrived, and nothing more") describes the *content*
policy, while the sound and vibration are the channels' own settings (22-49)
read per post (message_alerts.dart:106-111); `show` is called for each message
by `RunningAppAlerts.onNotice` (118-142) and once per wake pass by
`push_background.dart:134-140`; `NotificationManager`'s documented behaviour for
this flag is "alert only the first time" — the update is where later messages
land.
**Impact:** a notification that stops sounding after the first message is, for
someone relying on it, a notification that does not work. It is the difference
between "the phone told me" and "the phone told me once, twenty minutes ago".
**Fix sketch:** drop `onlyAlertOnce` for the message notification (updates then
alert like any messaging app), or keep quiet updates only when the count has
not changed; if one alert per run is the intended product rule, say so in the
class comment and in Settings, because the current settings promise the
opposite. The ringing call notification's `onlyAlertOnce`
(call_notifications.dart:246-247) is a different, correct use: a re-post must
not restart the ring.
**Test that proves it:** the notification-details test (or a fake plugin
capturing `AndroidNotificationDetails`) asserts `onlyAlertOnce` is false for
messages; a real-device checklist line: two messages, two alerts.
**Overlap:** 14g-1 (same notification and counter); S14g-3.

### AUD-14g-3 Removing an account leaves its notifications in the shade

**Severity:** P3  **Confidence:** confirmed
**Where:**
[session_providers.dart:105-128](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/session_providers.dart#L105-L128)
(`RemoveAccountAction`), the sibling
[session_providers.dart:66-91](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/session_providers.dart#L66-L91)
(`SignOutAction`), and the only cancel path,
[local_notifications.dart:162-163](file:///J:/Projects/helix/helix_remote/app/lib/core/notifications/local_notifications.dart#L162-L163).
**What:** removing a signed-in account signs it out, wipes its database, key,
avatar, attachments and account folder — and leaves its notifications in
Android's shade. A message notification for that account stays with its
"N new messages" title and, when previews are on, the last message's text
(`showMessages` body, local_notifications.dart:141); a "Missed call" entry can
stay the same way (call_notifications.dart:139-164). Tapping the message
notification now does nothing at all: `notificationAccountSwitchProvider` calls
`switchTo(account)`, which returns for an account that is no longer listed
(runtime_providers.dart:269-271), and the notification is auto-cancelled by the
tap, so the press looks like a failure. The current-account sign-out path is
usually covered by accident — coming back to the app resumes it and clears the
active account's notification (message_alerts.dart:163-168) — but removing
*another* account has no such step.
**Trigger:** a device with two accounts; account B receives messages while the
app is in the background; the person removes B from Settings > Accounts without
opening B first.
**Evidence:** the removal path touches the runtime, the keystore and the files
(113-127) and never notifications; the only message-notification cancel is
`clearMessages`, called from `RunningAppAlerts._clearFor` on resume/opened of
the *active* account (message_alerts.dart:145-168); no `cancelAll` exists in
`app/lib` (grep). The preview is drawn from the local database at post time
(message_alerts.dart:79-97), so it does not disappear when the database is
wiped — it sits on the lock screen.
**Impact:** a person who removed an account to get its data off the phone keeps
a fragment of that account — a sender-less count and possibly the last line of
a message — on the lock screen, and the one gesture that would dismiss it
appears broken. Small in reach, but it is exactly the leftover a wipe is
supposed to remove.
**Fix sketch:** a per-account cleanup called from both sign-out paths and from
`accountsProvider.remove`, cancelling the message notification and any call or
missed-call notification the account owns (S14g-1 gives the ids one owner).
**Test that proves it:** a removal test with a fake notifier asserts
`clearMessages(id)` is called and, with a fake call notification recorded, that
the account's call entry is cancelled too.
**Overlap:** S14g-1 (one owner of an account's notification ids and their
cancellation); 14g-4 (the dead press the leftover produces).

### AUD-14g-4 A press on a message notification of the account already open goes nowhere

**Severity:** P3  **Confidence:** confirmed
**Where:**
[notification_accounts.dart:26-33](file:///J:/Projects/helix/helix_remote/app/lib/core/notifications/notification_accounts.dart#L26-L33)
(the whole listener), with
[local_notifications.dart:120-158](file:///J:/Projects/helix/helix_remote/app/lib/core/notifications/local_notifications.dart#L120-L158)
(the notification it answers).
**What:** the only handler for a press on a message notification switches the
account when the pressed account is not the one on screen, and returns when it
is. Nothing navigates. So a press opens the app (or brings it forward) and
leaves the person on whatever screen was showing — Settings, a conversation
with someone else, the call log — with the notification already dismissed by
the tap. The class comment promises "its chats" for a press, which holds only
for the other-account case, where the account switch itself sends the router
home (app_router.dart's switch handling).
**Trigger:** the app is in the background on a screen other than the chat list
(very common: a conversation), a message notification for that same account is
tapped.
**Evidence:** the listener body (27-32) has no navigation and no router call;
`notificationResponsesProvider` has this one consumer in `app/lib` (grep); the
per-account switch is the only effect; a cold launch does land on home because
`_restoreServer` prefers the launching account and the router starts there
(main.dart:187-200).
**Impact:** the gesture a notification exists for — "show me what arrived" —
does nothing visible. The person may retry, or conclude the app ignored the
tap.
**Fix sketch:** when the pressed account is the active one, route to the chats
tab (`router.go(AppRoutes.home)`, the same destination an account switch lands
on); opening the conversation whose message it was would need the notification
to carry a conversation id, which the ids-only payload policy allows and the
product may not want.
**Test that proves it:** a widget/provider test with an overridden response
stream and a router: a press while the active account is B and the location is
a settings route ends at `/home`; today it stays put.
**Overlap:** 14g-3 (a press on a removed account's leftover); T4 (the same
"notification says something happened, nothing happens" shape is not a dead
path — the parse works — so it stays a finding).

### AUD-14g-5 A missed call in a muted chat still posts a notification

**Severity:** P3  **Confidence:** confirmed
**Where:**
[call_effects.dart:249-255](file:///J:/Projects/helix/helix_remote/app/lib/features/calls/application/call_effects.dart#L249-L255)
(the missed listener) and
[call_effects.dart:259-278](file:///J:/Projects/helix/helix_remote/app/lib/features/calls/application/call_effects.dart#L259-L278)
(`_showMissed`), against the engine's notice,
[calls_service.dart:867-889](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/calls/calls_service.dart#L867-L889)
(`muted` computed at 874 and 884).
**What:** the engine's `MissedCallEvent` notice carries `muted`, computed from
the direct chat's `mutedUntil` exactly so a consumer can keep quiet — the
message path does (`MessageAlerts.alerts`, message_alerts.dart:49-56, returns
false for a muted notice). The app's only consumer of `MissedCallEvent` reads
the notice's sender and preview fields and never `muted`, so a muted chat's
missed call is posted like any other, with the caller's name when previews are
on (`showCaller`, 264-277). A mute that silences every message from a chat
therefore does not silence its missed calls.
**Trigger:** a person who has muted a chat is called by that person while the
app is not on screen, and the call rings out.
**Evidence:** `muted` is set (calls_service.dart:884) and appears nowhere in
`app/lib` (grep); `_showMissed` has no such check (259-278); the message path's
equivalent check exists (message_alerts.dart:50-56).
**Impact:** a muted chat still interrupts with a notification, which is the one
thing mute is for. Whether a *ringing* call should obey mute is a product
question (most messaging apps ring anyway, and nothing in this app lets a chat
silence a call); the *missed-call notice* is the quiet aftermath the engine
already decided to label.
**Fix sketch:** either honour the flag (`if (event.notice.muted) return;`, and
keep the chat's own missed-call row, which the engine writes regardless,
calls_service.dart:840-861), or delete the field and say in the engine's comment
that mute applies to messages only. Leaving a computed flag unread is the one
option that keeps the disagreement invisible.
**Test that proves it:** a fake `CallsPort` emits a muted missed call: no
notification is posted; the chat still shows the missed row.
**Overlap:** 14g-6 (the same function's other rule); S14g-2.

### AUD-14g-6 The missed-call notification treats `inactive` as away

**Severity:** P3  **Confidence:** likely
**Where:**
[call_effects.dart:250-251](file:///J:/Projects/helix/helix_remote/app/lib/features/calls/application/call_effects.dart#L250-L251)
(`lifecycle == AppLifecycleState.resumed`), against
[message_alerts.dart:171-177](file:///J:/Projects/helix/helix_remote/app/lib/core/notifications/message_alerts.dart#L171-L177)
(`appInForeground`: `inactive` counts as on screen).
**What:** the app has two notions of "the person is looking". Messages use
`appInForeground`, which treats `inactive` — on Android, `onPause`: the
notification shade pulled down, a system dialog over the app, a split-screen
focus change — as being on screen, so nothing is raised while the app is still
visible. The missed-call path suppresses only in `resumed`, so a call that
ends as missed while the shade is open over the ringing call screen posts
"Missed call" — for a call the person could see ringing and was, in fact,
looking at.
**Trigger:** a call rings while the app is on the call screen; the person pulls
the shade down to check something else; the call times out or the caller
cancels during that second.
**Evidence:** the two comparisons (call_effects.dart:250-251,
message_alerts.dart:171-177) and the doc comment on `appInForeground` (168-170)
stating the `inactive` rule; `_showMissed` is the only caller of `showMissed`
in the app (grep).
**Impact:** a redundant notification appears for a call that was on screen —
and, because the missed event is the engine's honest record of an unanswered
call, the row in the chat is right; only the notification duplicates what the
person saw.
**Fix sketch:** use `appInForeground()` in `_showMissed` (S14g-2), so every
"should this raise?" decision shares one predicate.
**Test that proves it:** a lifecycle fake set to `inactive` around a missed
event posts nothing; `paused` posts.
**Overlap:** 14g-5; S14g-2.

### AUD-14g-7 One failed Firebase start disables push for the rest of the process

**Severity:** P3  **Confidence:** likely
**Where:**
[push_token_source.dart:48-66](file:///J:/Projects/helix/helix_remote/app/lib/core/push/push_token_source.dart#L48-L66)
(`_prepared` and the single try), with
[push_registration.dart:46-53](file:///J:/Projects/helix/helix_remote/app/lib/core/push/push_registration.dart#L46-L53)
(`engineRunning` calls `prepare` on every engine start).
**What:** `prepare()` memoises its future (`_prepared ??= _prepare()`), and
`_prepare` answers `false` on any failure to reach Firebase — then that `false`
is what every later caller receives. `PushRegistration.engineRunning` calls
`prepare()` each time an engine reaches running precisely so a token is sent
"on a signed-in launch, sign-up, sign-in, linking, a new server"
(push_registration.dart:16-20), but after one failure it returns before
subscribing to rotations or wake-ups and before reading a token. The token
source's own contract says "push unavailable is a normal state"; a transient
failure (Play services not yet available at boot, a restricted launch) is
indistinguishable from a build without `google-services.json` and is cached the
same way. The device then has no registered token until the process is
restarted, and the app only catches up when opened — the behaviour push exists
to avoid.
**Trigger:** the first `prepare()` in a process fails; every engine start in
that process afterwards is silent about push.
**Evidence:** the memo at 54 (a `Future<bool>`, so failures are cached with
successes); the catch that returns false at 64-66; no reset anywhere in the
class or in `PushRegistration` (grep for `_prepared` finds only 48 and 54);
`engineRunning`'s early return (push_registration.dart:47).
**Impact:** a silent loss of wake-ups for the whole session, with no error and
no retry. The person sees messages only when they next open the app.
**Fix sketch:** cache only success — await `_prepare()`, keep the future when
it answers true, clear it when it answers false so the next engine start tries
again. Either way, keep the "no google-services.json" case cheap (it will
retry once per engine start, which is at most a few times a session).
**Test that proves it:** a fake `PushTokens` whose first `prepare` answers
false and second true; two `engineRunning` calls register the token on the
second (today neither does).
**Overlap:** 12j (the engine's push registration), S14g-1 (notification state
that survives what it was decided from).

## Verified safe

- **No content crosses push** (`local_notifications.dart:172-197`): the payload
  is `key=value` pairs of ids only; message bodies are built from the local
  database, and call text from the pending call's caller id. The background
  isolate never reads the FCM data (push_background.dart:5-20, 96-110).
- **Previews.** `showIncoming`/`showMissed` put the caller's name in the title
  only when `notificationsPreview` is on, and are `private` otherwise
  (call_notifications.dart:86-93, 137-163); the message body is the preview only
  when the setting is on (message_alerts.dart:118-136). Channel names carry the
  ringtone's name, never a person.
- **The wake pass** (push_background.dart:22-70, 72-188): plugin registrant
  first, its own Firebase app, one headless runtime per account under the
  engine lease (`EngineAlreadyRunning` means the running app owns the
  database), one account's failure does not stop others, the runtime is closed
  in `finally`, and failures are printed as a runtime type only.
- **Token flow** (push_registration.dart:45-66, push_token_source.dart:82-101):
  the current token and every rotation go to the running engine and to every
  other signed-in account; `ForegroundWakes` serialises passes with one queued
  re-run, so two engines never race one database; every Firebase call answers
  false/null/empty rather than throwing, and non-Android builds never touch
  Firebase.
- **Ringtone channels** (call_notifications.dart:64-81, 112-145;
  orbit_ringtones.dart:154-168, 254-282): the channel id carries the pack id
  and audio kind, the channel is created on first ring (and re-created if the
  person deleted it), the copy is re-gate-checked on every read with a fall
  back to the phone's ringtone on any error, and removing a pack deletes its
  channels by prefix.
- **The ringing notification** (call_notifications.dart:170-270): full-screen
  intent behind the declared `USE_FULL_SCREEN_INTENT` (AndroidManifest.xml:10),
  `ongoing`/`autoCancel: false`/insistent, `onlyAlertOnce` so a re-post from the
  app after a wake does not restart the sound, a 60 s timeout matching the
  engine's ring window, and Answer and Decline both opening the UI with
  `showsUserInterface: true` — the press is remembered
  (`PendingCallDecision`, call_effects.dart:178-190) until the offer arrives.
- **Missed calls are honest about what they are** (calls_service.dart:795-799):
  the engine emits the notice only for `unanswered` and `cancelledByPeer`, so a
  call the person declined is never announced as missed, and
  `CallNotificationHandler` rebinds its stream to whichever runtime is running
  (call_effects.dart:238-257).
- **Account presses** (notification_accounts.dart:26-33): a press for an
  account that is gone is a no-op (`switchTo` guards, runtime_providers.dart:
  269-271); the launch payload is applied by `restore(prefer:)` so the last
  account is not opened only to be closed (main.dart:187-200).
- **Initialisation** (local_notifications.dart:66-95): Android-only and
  idempotent; four message channels for the sound/vibrate combinations, which
  is the only way a channel's sound can be a setting.

## Coverage notes

- Read in full: the eight files in **Where** (1,233 lines), plus the
  cross-reads named above.
- Not filed, weighed:
  - Several accounts with pending calls in one wake pass each post a
    full-screen call notification (push_background.dart:155-180). Android
    shows one at a time and queues the rest; the oldest account wins the
    screen. It needs one phone, several signed-in accounts and simultaneous
    callers — noted, not filed.
  - `RunningAppAlerts._count` restarts when the person switches accounts and
    comes back (message_alerts.dart:124-128), so the next message replaces a
    larger count with "1 new message". It is the same undercount as 14g-1
    within one process, folded into S14g-3 rather than filed twice.
  - Notification ids derive from `String.hashCode` (local_notifications.dart:
    108-110, call_notifications.dart:96). Dart's string hash is content-based
    and 31 bits here, so a collision needs tens of thousands of live ids —
    not a bug today, but not a stated contract either; S14g-1 puts id
    derivation in one place, where a stable truncation can replace it.
  - A tap on a message notification opens the account, not the conversation
    that received the message. That is a product choice (the payload carries no
    conversation id by design); 14g-4 is only the case where it opens nothing.
  - A call in a muted chat still rings. Nothing in the settings offers
    call silencing, and most messengers behave this way; only the missed-call
    notice's unread `muted` flag is filed (14g-5).
  - `SystemNotificationPermission` swallows every error as "not allowed"
    (notification_permission.dart:19-34). It is a read used to draw a settings
    row; a failed read showing "off" is the safe direction, so no finding.
- Not read here: the native `MainActivity` intent handling and Firebase
  services in `AndroidManifest.xml` (declarations only checked for the two
  permissions this sweep depends on), and the Settings > Notifications page
  (sweep 15's settings feature).

## Structural proposals

**S14g-1 — an account's notifications have one owner.** Every notification id
is derived from a string in three places today (`messagesIdFor`, `idFor(callId)`,
`idFor('missed-$callId')`), and cancelling them is a fourth piece of knowledge
that sign-out does not have. One small seam — ids by kind for an account or a
call, plus `forgetAccount(account)` — makes removal complete (14g-3), gives the
message count an owner that can accumulate (14g-1), and turns the hash-based ids
into one documented rule.

**S14g-2 — one foreground predicate for every "should this raise?" decision.**
`appInForeground()` already exists and is documented for `inactive`; the missed
call path is the one place that asks a different question (14g-6). Using it
everywhere makes the answer about the person, not about which file asks.

**S14g-3 — a notification's state belongs to the notification.** Whether a run
has alerted (14g-2) and how many messages it stands for (14g-1) are facts about
the notification in the shade, not about the isolate that happened to post it.
One function that posts or updates `account`'s message notification — given the
pass's messages — should own the count, choose alert versus silent, and be the
only caller of `showMessages`, for both the background isolate and the running
app.
