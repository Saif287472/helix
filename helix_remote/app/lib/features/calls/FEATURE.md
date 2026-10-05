# features/calls

1:1 voice and video calls (Phase A3a). The engine owns the signalling state
machine (`engine.calls`, `CallSnapshot`, `CallPhase`, the call log); this
feature draws it, supplies the media, and wires the phone around it. Group
calls stay deferred (plan section 13).

```
application/
  calls_port.dart           CallsPort (interface) + EngineCallsPort over CallsService;
                            callsPortProvider (also gives the engine its CallMediaFactory),
                            currentCallProvider (+ a short hold on an ended call)
  call_controller.dart      callScreenStateProvider (CallScreenState), callElapsedProvider,
                            callActionsProvider (accept/decline/hang up/mute/camera/flip/route)
  call_screen_state.dart    CallScreenState, CallStage, CallQuality (plain values)
  call_copy.dart            every sentence: statuses, ended reasons, failures, durations
  call_audio.dart           audio route state (earpiece / speaker / bluetooth / headset)
  call_log.dart             call log -> HelixCallLogItem (folding, naming, time labels),
                            call detail, delete, call back
  call_effects.dart         the phone around a call (ring, lock-screen flags, foreground
                            service, proximity, app-lock bypass) + notification buttons
  start_call.dart           startCallProvider: THE SEAM for every call button
  media/                    WebRtcCallMediaFactory/Session over helix_remote_calls,
                            CallMediaHub (video surfaces, camera facing, quality)
  platform/                 CallPlatform (Android channel), CallPermissions,
                            CallAudioPlatform, CallRinger - interfaces + real adapters
presentation/               CallsTabScreen (the tab), CallDetailScreen, CallScreen with the
                            incoming and in-call views
calls_routes.dart           /call (the full-screen call), /home/calls/:callId (detail)
```

Core wiring: `core/calls/call_host.dart` (above the app lock, in `main.dart`),
`core/calls/place_call.dart` (the seam), `core/notifications/call_notifications.dart`
(the ringing notification, shared with the FCM isolate). Names come from
`core/people/people_names.dart` (the one naming source).

## The call-button seam

A feature that offers a call must not import `features/calls`. Its
`application/` layer reads `placeCallProvider` from `core/calls/place_call.dart`:

```dart
final outcome = await ref.read(placeCallProvider)(peerAccountId, video: false);
if (!outcome.started) showSnackBar(outcome.message!);   // one plain sentence
```

It asks for the microphone (and the camera for video), then
`engine.calls.startCall`. The full-screen call opens by itself (the call host
follows the engine's call state), so a caller does nothing more. A2a (the
conversation header) and A2b (contact info) bind their buttons to this;
`PlaceCallStatus` says why not (`microphoneDenied`, `cameraDenied`, `busy`,
`blocked`, `rateLimited`, `noRelay`, `unavailable`). Tests override
`placeCallProvider`.

## Calls tab and the people-search seam

`CallsTabScreen({peopleSearch})`. The router hands it to `HomeScreen(callsTab:)`.
`peopleSearch` is a `CallsPeopleSearchBuilder(context, query, onCall)`: the router
mounts the people feature's `PeopleSearchPanel(mode: calls)` there (features never
import each other); a tap calls through `placeCallProvider`. Without one, the search
button filters the call log by name. Names come from `peopleDirectoryProvider`
(`core/people/people_names.dart`): phone book, nickname, number, `~Helix name`.

## How a call reaches the screen

The call host (`core/calls/call_host.dart`) reads `callScreenStateProvider`, which
derives from `engine.calls.watchCurrent()` (not from `IncomingCallEvent`, which
cannot be replayed), and pushes `/call` the moment a call exists - ringing here,
dialing, anywhere in the app, over the lock screen (the activity already shows
when locked; the effects set the window flags and `AppLock.callInProgress`).
Closed app: the FCM isolate shows the full-screen ringing notification
(`CallNotifications.showIncoming`, caller name only); its buttons open the app,
which rings the call (`fetchPending`) and applies a button pressed before the
offer was known (`PendingCallDecision`, valid for the ring time).

## Platform pieces (all behind interfaces; Windows compiles with stubs)

- Foreground service, window flags, full-screen-intent check: the existing
  `com.helix.remote/calls` channel and `CallForegroundService`.
- Proximity (screen off at the ear on a voice call on the earpiece): new
  `setProximityScreenOff` in `MainActivity` (a proximity wake lock, 3 h cap).
- Audio routing: `WebRtcAudioOutputs` (new, in `helix_remote_calls`): earpiece,
  speaker, Bluetooth, wired headset where the plugin reports them; none on Windows
  (the route control hides).
- Permissions: `WebRtcMediaPermissions` opens and closes the device to raise the
  OS prompt, so the person meets it before the call, not in it.
- Media: relay-only candidates (`IpPrivacyMode.relayOnly`) with the engine's TURN
  credentials; no relay means no call and a "no call relay" sentence, never a
  silent direct connection.

## Rules and limits

- Back is ignored while a call is live (leaving is hanging up); there is no
  minimised "return to call" bar yet.
- The notification's Decline opens the app (no background engine to decline from).
- Group calls, call links and scheduled calls: not built.
- No APK is needed to review the code; one is needed to try calls on a phone
  (Kotlin changed).
