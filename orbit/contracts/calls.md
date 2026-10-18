# Contract: calls

Prototype screens: `call` (states: `call-incoming`, `call-incoming-video`, `call-incoming-notice`, `call-outgoing`, `call-ringing`, `call-connecting`, `call-active`, `call-active-weak`, `call-reconnecting`, `call-video`, `call-video-dialing`, `call-ended`, `call-busy`, `call-failed`), `call-detail` (states: `call-detail`)
Today's app: `features/calls/presentation/call_screen.dart`, `incoming_call_view.dart`, `in_call_view.dart`, `call_parts.dart`, `call_detail_screen.dart`; `features/calls/application/call_controller.dart`, `call_screen_state.dart`, `call_copy.dart`, `call_audio.dart`, `call_log.dart`, `calls_port.dart`, `start_call.dart`, `call_effects.dart`, `media/`, `platform/`; `core/calls/`, `core/notifications/call_notifications.dart`

Paths are under `helix_remote/app/lib/` unless they start with `packages/`
(under `helix_remote/`). The Calls tab, dial pad and call log list are in
`home.md`.

## Call (`call`)

Dart: `CallScreen`, `CallModel`, `CallActions`.

- **Name clash.** The app already has `CallScreen`
  (`features/calls/presentation/call_screen.dart`), `CallActions`
  (`call_controller.dart`), `CallStage`, `CallQuality`
  (`call_screen_state.dart`) and `CallAudioRoute`
  (`platform/call_platform.dart`). `orbit_ui` defines its own enums with the
  same values, and the connector imports `orbit_ui` with a prefix.
- **Open and close.** The screen never opens itself. `CallHost`
  (`core/calls/call_host.dart`) pushes `/call` when `callScreenStateProvider`
  has a call, and `callScreenOpenProvider` stops a second push. The connector
  pops the screen when the model becomes null. `currentCallProvider` keeps an
  ended call for `callEndedLingerProvider` (2200 ms), or 400 ms for a lost
  glare. This is the prototype's "closes after 2 s".
- **One source.** Everything below comes from `callScreenStateProvider`
  (`CallScreenState`), except `elapsedLabel`.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `callId` | `String` | have | `CallScreenState.callId` | Resets the screen's own state (tile position, controls hidden) for each call. |
| `title` | `String` | have | `CallScreenState.title` (`people.nameOf(peer).tileNames.display`) | The people-naming order. |
| `subtitle` | `String?` | have | `CallScreenState.subtitle` (`HelixPersonNames.secondary`) | See the copy row on the line under the name. |
| `avatar` | `HelixAvatarModel` | have | `CallScreenState.avatar` | Initials and colour only. `PeopleDirectory.avatarOf(peer)` (`core/people/people_names.dart`) also has the phone-book photo, if the design wants it. |
| `video` | `bool` | have | `CallScreenState.video` | The call was offered with video. |
| `stage` | `CallStage` (`dialing`, `incoming`, `connecting`, `active`, `ended`) | have | `CallScreenState.stage` | The prototype's `outgoing` and `ringing` are both `dialing` (the difference is in `statusText`). Its `reconnecting` is `active` with `quality: reconnecting`. |
| `statusText` | `String` | have | `CallScreenState.statusText` (`CallCopy.status`) | "Calling…", "Ringing…", "Connecting…", "Reconnecting…", "Incoming voice call" / "Incoming video call", and the end reason (`CallCopy.ended`). "Connected" shows until the first timer tick. |
| `elapsedLabel` | `String?` | derive | `callElapsedProvider` + `formatCallDuration` (`call_copy.dart`); the rule is in `CallStatusLine` (`call_parts.dart`) | "00:12". Set only while `stage` is `active` and `quality` is not `reconnecting`, and then shown in place of `statusText`. Changes every second. |
| `talkTimeLabel` | `String?` | have | `CallScreenState.talkTime` → `formatCallDuration` | Only for an ended call that was answered. |
| `endDetail` | `String?` | have | `CallScreenState.endDetail` (`CallCopy.endedDetail`) | Busy: "They are in another call right now." Failed: "The call could not connect. Check your connection and try again." Hidden while a `notice` shows (`_CallHeader`). |
| `endIsProblem` | `bool` | derive | `CallScreenState.end` is `busy` or `failed` | The prototype tints these reasons. |
| `quality` | `CallQuality` (`good`, `weak`, `reconnecting`) | have | `CallScreenState.quality` (`CallMediaInfo.weak` from `CallQualityMetrics.isWeak`; reconnecting = active with media `disconnected`) | `weak` shows the "Poor connection" chip while the call is live. `reconnecting` shows a spinner and "Reconnecting…". |
| `muted` | `bool` | have | `CallScreenState.muted` | Also drives the prototype's new line "Your microphone is off". |
| `cameraOn` | `bool` | have | `CallScreenState.cameraOn` | A video call rings with the camera on. |
| `audioRoute` | `CallAudioRoute` (`earpiece`, `speaker`, `bluetooth`, `wiredHeadset`) | have | `CallScreenState.audio.route` (`callAudioProvider`) | Labels: Phone, Speaker, Bluetooth, Headset (`CallAudioRoute.label`). |
| `audioRoutes` | `List<CallAudioRoute>` | have | `CallScreenState.audio.available` | Only the outputs that exist now, in display order. Empty on Windows. Filled once the microphone is open (`mediaOpen`). |
| `notice` | `String?` | have | `CallScreenState.notice` (`callNoticeProvider`, keyed by call id) | A permission refusal or a failure sentence. This is the prototype's `call-incoming-notice` bar. |
| `busy` | `bool` | have | `CallScreenState.busy` (`callBusyProvider`) | An answer, decline or hang-up is in flight. Answer and Decline are disabled meanwhile. |
| `videoLayout` | `bool` | derive | `CallScreenState.showsVideo && isLive` (`InCallView.build`) | True from dialing to the end of a video call. The ended screen uses the voice layout. |
| `hasLocalVideo` | `bool` | derive | `cameraOn && CallScreenState.local != null` (`_VideoLayoutState`) | Decides whether the `localVideo` slot is drawn. |
| `hasRemoteVideo` | `bool` | derive | `stage == active && CallScreenState.remote != null` | Decides whether the `remoteVideo` slot is drawn. |
| `canMute` | `bool` | derive | `buildCallControls` (`in_call_view.dart`): live and `hasControls` (dialing, connecting, active) | The rule moves from presentation to the connector. |
| `canToggleCamera` | `bool` | derive | `buildCallControls`: `video`, live, stage `connecting` or `active` | The prototype allows `active` only. The app also allows `connecting`. |
| `canFlip` | `bool` | derive | `buildCallControls`: `video`, live, `cameraOn` | |
| `canChooseRoute` | `bool` | derive | `buildCallControls`: live and `audio.canChoose` (more than one output) | False on Windows. |
| `canEnd` | `bool` | derive | `buildCallControls`: `isLive` | Every control is disabled on the ended screen. |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `answer` | `Future<void> Function()` | have | `CallActions.accept` (`call_controller.dart`) → `CallsPort.accept` | INTERACTIONS "Answer (incoming)". Asks for the microphone, and the camera for video, first. A refusal shows `notice` and the call keeps ringing. A `CallFailedException` shows `notice`. |
| `decline` | `Future<void> Function()` | have | `CallActions.decline` → `CallsPort.decline` | INTERACTIONS "Decline (incoming)". The ended screen reads "Call declined". |
| `hangUp` | `Future<void> Function()` | have | `CallActions.hangUp` → `CallsPort.hangUp` | INTERACTIONS "End". Before an answer it cancels ("Call cancelled"). After an answer it hangs up ("Call ended"). |
| `setMuted` | `Future<void> Function(bool muted)` | have | `CallActions.setMuted` → `CallsPort.setMuted` | INTERACTIONS "Mute". |
| `setCamera` | `Future<void> Function(bool on)` | have | `CallActions.setCameraEnabled` → `CallsPort.setCameraEnabled` | INTERACTIONS "Camera". |
| `flipCamera` | `Future<void> Function()` | have | `CallActions.switchCamera` → `CallMediaHub.switchCamera` → `RemoteCallEngine.switchCamera` (`packages/helix_remote_calls`) | INTERACTIONS "Flip". The facing comes back as `RemoteCameraFacingEvent` and mirrors the self view. |
| `selectAudioRoute` | `Future<void> Function(CallAudioRoute route)` | have | `CallActions.selectRoute` → `CallAudioController.select` → `WebRtcAudioOutputs.select` | INTERACTIONS "Audio output". See "Kept inside the screen" for the toggle and the sheet. |
| `dismissNotice` | `void Function()` | have | `CallActions.dismissNotice` | INTERACTIONS "Notice ×". The app's notice is a permission or failure sentence. Weak and reconnecting have no × in the app, nor in the prototype's drawing. |

### Kept inside the screen
- **Audio output** (INTERACTIONS "Audio output"):
  - With two outputs, a tap picks the other one and calls `selectAudioRoute`.
  - With more than two, the screen opens the "Audio output" sheet itself,
    listing `audioRoutes` with `audioRoute` ticked.
  - Today: `CallScreen._chooseRoute` and `onRoute`. The prototype always opens
    a sheet of four (open question 1).
- **Controls shown or hidden** (INTERACTIONS "Video picture"). Tapping the
  video toggles them: a 220 ms fade, none with reduced motion, and they leave
  the screen-reader tree while hidden. Today: `_InCallViewState._controlsVisible`.
- **Self tile position** (INTERACTIONS "drag Your own camera tile"):
  - The tile is 100×142 and starts at the top end, below the header.
  - It stays inside the safe area, follows RTL, and shows a move cursor on a
    desktop.
  - Today: `_VideoLayoutState._previewAt`.
- **Swapped pictures** (INTERACTIONS "tap Your own camera tile"):
  - A tap swaps the tile and the big picture.
  - Screen-reader label: "Show your camera full screen" or "Show <name> full
    screen".
  - Today: `_VideoLayoutState._swapped`.
- **Back.** Back is ignored while `stage` is not `ended`
  (`PopScope(canPop: !isLive)`).
- **The pulse.** The avatar pulses while `incoming` or `dialing`, and not
  with reduced motion.
- **Auto "Outgoing call"** (INTERACTIONS). The screen does not drive this:
  - The engine moves `stage` and `statusText` through calling, ringing,
    connecting and active.
  - `elapsedLabel` counts while the call is live.
  - The prototype's 1.4 s and 3.6 s timings are demo.

### Slots
| Slot | What the app puts there | What the preview shows |
|---|---|---|
| `remoteVideo` | A builder given the screen's placeholder (the avatar stage, or a compact avatar when swapped into the tile). The app wraps `CallScreenState.remote` (`CallVideoSurface`) in a `ListenableBuilder` on `changes`, showing `build()` while `hasFrames` and the placeholder otherwise (`_RemoteTile`). | The `ph-e` gradient block |
| `localVideo` | `CallScreenState.local.build(mirror: CallScreenState.frontCamera)` | The `ph-c` gradient block |

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Answer and Decline disabled while an answer or decline is in flight | `IncomingCallView` (`onAccept: state.busy ? null : …`) | Keep today's behaviour in the new style |
| Camera refused when answering a video call: "Helix needs the camera for video calls. Allow it in your phone's settings, or make a voice call instead." | `CallCopy.cameraDenied`, `CallActions.accept` | Keep (same notice bar as the microphone state) |
| Failure notices during a call: "There is no call to answer any more.", "The microphone or camera could not be started for this call.", the no-relay sentence, "The call could not be placed. Check your connection and try again." | `CallActions._guard` / `_failureText`, `CallCopy.failure`, `CallCopy.noRelay` | Keep (notice bar) |
| End reasons the prototype does not draw: "Call declined", "Call cancelled", "Missed call", "No answer", "Answered on another device", "Declined on another device"; a lost glare reads "Call ended" for 0.4 s | `CallCopy.ended` | Keep (text only; same layout as `call-ended`) |
| Talk time under the reason only for a call that was answered | `CallStatusLine` (`frozen`) | Keep the app's way (see the copy rows) |
| Their camera off, or no frames yet: their avatar fills the big picture (a small avatar when swapped) | `_RemoteTile`, `_AvatarStage` | Add to the design |
| Your camera off on a video call: the app keeps the video layout and drops your tile; the prototype falls back to the voice layout | `_VideoLayoutState` (`local = cameraOn ? … : null`) | Open question 4 |
| A connecting video call shows your camera (the prototype shows the voice layout while connecting) | `InCallView` (`showsVideo`) | Keep the app's way |
| Audio: a connected headset or Bluetooth device wins; a pulled headset falls back to the earpiece or speaker; voice starts on the earpiece and video on the speaker; a call being placed can go to the speaker while it rings | `CallAudioController` (`call_audio.dart`), `CallEffects` | Keep (no UI change) |
| Windows: the route control is shown disabled, with the tooltip "Turn speaker on" (`FEATURE.md` says it hides) | `buildCallControls`, `routeFace` | Hide it when `audioRoutes` is empty |
| Short screens (under 520 px high) shrink the avatar, and the screen scrolls | `IncomingCallView`, `_VoiceLayout` (`compact`) | Keep |
| Screen reader: status as a live region, "Call duration 00:12", "Picture of <name>", the big picture "Your camera" or "Video from <name>" | `CallStatusLine`, `CallAvatar`, `_VideoLayoutState` | Keep |
| App lock: a ringing or dialing call stays behind the lock page; the lock lifts for the call once it is connecting or active | `CallEffects.setLockBypass` → `AppLock.callInProgress` (`core/security/app_lock.dart`) | Keep |
| Over the phone's lock screen: window flags, a full-screen intent when locked or idle, a foreground service, the screen off at the ear (voice on the earpiece), the screen kept on for video | `CallPlatform` (`platform/call_platform.dart`), `CallEffects` | Keep (no UI) |
| Android ringing notification: ringtone, repeats for 60 s, Decline and Answer buttons that open the app. The caller's name shows only with message previews on (else the title is "Helix", private). Body: "Incoming voice call", "Incoming video call" or "Incoming call"; subtext "Helix voice call" | `CallNotifications.showIncoming`, `NotificationCallRinger` | Keep (system UI; only the Helix → Orbit rename) |
| A notification button pressed before the offer arrived is applied when the call rings (within 60 s), including on a cold start | `CallNotificationHandler`, `PendingCallDecision`, `callLaunchResponseProvider` (`call_effects.dart`) | Keep |
| "Missed call" notification (the caller's name, or "Open Helix to see who called.") for a call that rang while the app was not on screen | `CallNotificationHandler._showMissed`, `CallNotifications.showMissed` | Keep |
| Offers that waited on the server ring when the app resumes | `CallHost._ringPending` → `CallsPort.fetchPending` | Keep |
| Windows: no notifications or push (both Android only), a system alert sound every 3 s as the ring, no lock-screen integration. The call opens over whatever is showing | `AlertCallRinger`, `NoCallPlatform`, `core/push/push_token_source.dart` | Keep; `frame.md` covers the full-window call (controls 440 px wide) |
| Copy: ending an unanswered outgoing call. Prototype "Call ended"; app "Call cancelled" (`CallEnd.cancelledByMe`) | `CallCopy.ended` | The app's (it differs in meaning) |
| Copy: time on the ended screen. The prototype always shows a clock, even under "Call failed" or "Busy"; the app shows talk time only for an answered call | `CallStatusLine` | The app's |
| Copy: the line under the name. The prototype shows the number, else `~name`, even when the name already is the number; the app uses `HelixPersonNames.secondary`, so no repeat | `CallScreenState.subtitle` | The app's |
| Copy: the prototype adds "Your microphone is off" under the timer when muted (new) | none today | Prototype; the screen draws it from `muted` |
| Copy: the prototype's Flip shows a toast "Camera flipped" (new); the app shows nothing and the mirrored self view changes | none today | Open question 5 |
| Copy: the audio-output tooltip. Prototype "Audio output: <route>" always; app "Turn speaker on" / "Turn speaker off" when the control is a two-way toggle | `routeFace` | Follows open question 1 |
| INTERACTIONS says Notice × hides "weak connection, reconnecting" notices. Neither the app nor the prototype's drawing has such a notice: weak is a chip, reconnecting a status line | `CallNoticeBar`, `PoorConnectionChip` | Fix the INTERACTIONS label to "a refusal or failure notice" |

### New backend work
| Item | Why the design needs it | Engine / server / protocol | Size: S, M, L |
|---|---|---|---|
| None | Every control in the prototype exists today | | |

Checked and already present:
- Camera flip: `RemoteCallEngine.switchCamera`.
- Audio routes: `WebRtcAudioOutputs`, Android only.
- The poor-connection chip: `CallQualityMetrics.isWeak`.
- Reconnecting: the media state is `disconnected`.
- Ringing with the camera on: `CallsService` publishes the camera while it rings.

These are not in the design, so nothing to build:
- Upgrading a voice call to video: the button is disabled in both.
- Choosing an output device on Windows: `helix_remote_calls` maps Android
  outputs only.

## Call details (`call-detail`)

Dart: `CallDetailScreen`, `CallDetailModel`, `CallDetailActions`.

- **Route.** The page is `/home/calls/:callId` (`CallRoutes.detail`,
  `calls_routes.dart`). It opens from a Calls row and from
  `helix://call/<id>` links.
- **Input.** The connector takes `callId`, the newest call of the tapped row.
- **Name clash.** The app's `CallDetailScreen` has the same name.

### Model
| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `status` | `CallDetailStatus` (`loading`, `ready`, `notFound`, `error`) | have | `callDetailProvider(callId)` (`call_log.dart`): loading, data null, data, error | |
| `title` | `String` | have | `CallDetail.title` | The people-naming order, with the log row's name as fallback. |
| `subtitle` | `String?` | have | `CallDetail.subtitle` | |
| `avatar` | `HelixAvatarModel` | have | `CallDetail.avatar` | Initials only, as on the call screen. |
| `rows` | `List<CallDetailRowModel>` | have | `CallDetail.rows` | Every call with this person among the newest 200 log entries, newest first, not only the folded row. |
| `canCall` | `bool` | derive | `PeopleDirectory.isBlocked(peer)` (`core/people/people_names.dart`) and `ChatGateway.watchBlocksMe(peer)` (`core/chat/chat_gateway.dart`) | Defaults to true. Today the page always shows the call buttons. Used only if open question 3 picks hiding. |

`CallDetailRowModel`:

| Field | Type | Tag | Comes from today | Notes |
|---|---|---|---|---|
| `callId` | `String` | have | `CallDetailRow.callId` | Key. |
| `direction` | `CallLogDirection` (`incoming`, `outgoing`, `missed`, `declined`, `failed`, `cancelled`, `noAnswer`) | have | `CallDetailRow.direction` (`detailDirectionOf`) | Picks the icon. |
| `label` | `String` | derive | `CallDetailRow.directionLabel` + "voice call" or "video call" (composed in `_CallRow` today) | "Incoming voice call". |
| `timeLabel` | `String` | have | `CallDetailRow.timeLabel` (`formatWhen`) | "Yesterday, 21:30". |
| `durationLabel` | `String?` | have | `CallDetailRow.durationLabel` | "32:18"; null when not answered. |
| `spokenDuration` | `String?` | have | `CallDetailRow.spokenDuration` | For the row's screen-reader label: "32 min 18 sec". |
| `video` | `bool` | have | `CallDetailRow.video` | |
| `isProblem` | `bool` | derive | `direction` is `missed` or `failed` | Red title and icon. |

### Actions
| Action | Signature | Tag | Calls today | Notes |
|---|---|---|---|---|
| `voiceCall` | `Future<String?> Function()` | have | `CallLogActions.callBack(peer, video: false)` → `startCallProvider` | INTERACTIONS "Voice call". Null when the call started (the call screen opens by itself), else the sentence for a snackbar (`PlaceCallOutcome.message`). |
| `videoCall` | `Future<String?> Function()` | have | `CallLogActions.callBack(peer, video: true)` | INTERACTIONS "Video call". |
| `openContact` | `void Function()` | have | `context.push(PeoplePaths.person(peer))` (`shared/navigation/people_paths.dart`) | INTERACTIONS "Contact". |
| `deleteAll` | `Future<void> Function()` | have | `CallLogActions.delete(rows.callId…)`, then `Navigator.maybePop` | INTERACTIONS "Delete (app bar)". The screen asks first. |
| `retry` | `void Function()` | have | `ref.invalidate(callDetailProvider(callId))` | Error state only. |

### Kept inside the screen
- **The delete dialog** (INTERACTIONS "Delete (app bar)"):
  - Title "Delete from call history?". Body "All N calls with <title> will be
    removed from your call history.", with N = `rows.length`.
  - Buttons Cancel and Delete. Only Delete calls `deleteAll`.
  - The delete button shows only when `status` is `ready`.
- **The snackbar.** It shows the sentence from `voiceCall` or `videoCall`,
  and the button spins while the call is placed.

### Slots
None.

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |
|---|---|---|
| Loading spinner | `CallDetailScreen` (`AsyncLoading`) | Keep in the new style |
| Error: "This call could not be loaded." with Retry | `HelixErrorState` in `CallDetailScreen` | Keep |
| Gone: "Call not found" / "This call is no longer in your call history." | `HelixEmptyState` in `CallDetailScreen` | Keep |
| Call-back failures as a snackbar: microphone or camera refused, "You are already in a call.", "You blocked this person. Unblock them to call.", "This person has blocked you. You can't message or call them." (ADR-030, `CallFailure.blockedByPeer`), "Too many calls in a short time. Try again in a little while.", the no-relay sentence, "The call could not be placed. Check your connection and try again." | `_Body._call`, `CallCopy.failure`, `start_call.dart` | Keep |
| Row kinds the prototype lacks: video calls, Declined (hang-up icon, not red), Failed (error icon, red), Cancelled, No answer | `_CallRow`, `detailDirectionOf` | Add to the design |
| The page leaves after a delete | `_deleteAll` → `maybePop` | Keep. On a window the right pane should go to "Pick a call" (for `frame.md`) |
| Call buttons stay when either side has blocked; the conversation header hides them (ADR-030) | `_Body` | Open question 3 |
| Copy: the delete count. The prototype uses the folded row's count; the app counts every call with the person on the page, and deletes them all | `_deleteAll` | The app's. For one call, say "This call with <name> will be removed from your call history." (today: "All 1 calls") |
| Copy: the no-answer row reads "No answer voice call" | `CallCopy.directionWord`, `_CallRow` | Reword, for example "Unanswered voice call" |

### New backend work
| Item | Why the design needs it | Engine / server / protocol | Size: S, M, L |
|---|---|---|---|
| None | The page reads the existing call log (`CallsPort.watchLog`, `forget`) | | |

## Open questions for the product owner

1. **Audio output.** Should the control always open a sheet of four (the
   prototype)? Or keep the app's way: a two-way toggle with two outputs, a
   sheet of only the outputs that exist with more, and hidden on Windows?
2. **Esc on a live call, on a window.** `frame.md` has Esc close "a call",
   but back is ignored while a call is live. Should Esc do nothing, or hang
   up?
3. **Blocked people on Call details.** Keep the call buttons and show the
   sentence on tap (today), or hide them like the conversation header?
4. **Your camera off on a video call.** Keep their video full screen without
   your tile (the app), or switch to the voice layout (the prototype)?
5. **The "Camera flipped" toast.** Keep it, or drop it (the app shows
   nothing)?
