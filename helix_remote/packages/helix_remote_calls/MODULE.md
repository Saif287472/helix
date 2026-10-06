# Package: helix_remote_calls

Status: current. The Flutter half of calling: the WebRTC wrapper the app's
call UI sits on. The call *state machine* (offer, answer, ICE, end reasons,
call log, pending calls) lives in `helix_remote_engine`, which talks to this
package through its `CallMediaFactory` seam. Phase X deleted the v1
`RemoteCallService` / `RemoteGroupCallService` that used to own that state
here.

## Purpose

`RemoteWebRtcCallEngine` and its helpers: ICE configuration, call-quality
reports, the video view widget, audio output selection and the permission
probe. Group calls are not built in v2 (plan section 13).

## Public surface

`lib/helix_remote_calls.dart` exports `ice_config`, `call_engine`,
`call_quality`, `call_setup_failure`, `call_video_view`,
`web_rtc_call_engine` and `call_devices`.

`call_devices` is the app's only door to the plugin for audio output
selection (`WebRtcAudioOutputs`), the microphone/camera permission probe
(`WebRtcMediaPermissions`) and `RemoteVideoSource` (in `call_video_view`), so
the app never imports `flutter_webrtc` itself. The app implements the
engine's `CallMediaFactory` over `RemoteWebRtcCallEngine`
(`app/lib/features/calls/application/media/`).

## Who may depend on this

The app only.

## What this may depend on

`flutter_webrtc` and Flutter. No other Helix package.

## Gotchas

- **ICE servers come from the server's `GET /v1/calls/turn`**, which are
  short-lived (1 hour) and rate-limited. Fetch per call; do not cache across
  calls.
- **Calls are relay-only** (`IpPrivacyMode.relayOnly` is the default): peers
  never learn each other's addresses. A direct mode must be chosen
  explicitly, and an unresolved `directIfVerified` fails closed
  (`test/ice_config_test.dart`).
- **`active <-> reconnecting` has to cycle** for ICE restarts.
- Not testable without a device: the proximity sensor and audio routing
  Android code (see `app/MODULE.md`).
