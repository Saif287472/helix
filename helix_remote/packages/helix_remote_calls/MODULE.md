# Package: helix_remote_calls

Status: current. Package-level counterpart to the backend module docs, from
the [structural upgrade plan](../../../docs/architecture/EARNMINUTE_STRUCTURAL_UPGRADE_PLAN.md)
(item A4). States in prose what
[`module_boundaries.json`](../../../docs/architecture/module_boundaries.json)
enforces at build time via `tool/check_boundaries.dart` — the config is the
authority; this is the explanation that sits next to the code.

## Purpose

The client half of calling: the WebRTC engine wrapper, ICE configuration,
call-quality reporting, the video view widget, and the two services that
drive 1:1 and group call state.

## Public surface

`lib/helix_remote_calls.dart` exports `ice_config`, `call_engine`,
`call_quality`, `call_video_view`, `remote_call_service`,
`remote_group_call_service`, `web_rtc_call_engine`.

## Who may depend on this

The app only.

## What this may depend on

`helix_remote_domain`, `helix_remote_storage`, `flutter_webrtc`, `uuid`,
Flutter.

## Gotchas

- **The state machines here have transition tables in the domain package**
  (plan item A6): `RemoteCallSessionStatus` mirrors `RemoteCallState`, and
  `RemoteGroupCallStatus` mirrors `GroupCallStatus`. When you add a state to
  an enum here, add the edge there — the table is what makes an illegal
  move loud rather than silent.
- **`active <-> reconnecting` has to cycle** for ICE restarts. Every other
  call ending is terminal, and a retry is a new call object.
- **ICE servers come from the backend's `/calls/turn-credentials`**, which
  are short-lived (1 hour) and rate-limited. Fetch per call; do not cache
  across calls.
- **Group calls are a 4-participant mesh, not an SFU.** See
  `docs/architecture/adr_group_calls.md`.
- `CURRENT_STATE_2026-06-20.md` classifies Remote calls as Component-only —
  the pieces are tested, the end-to-end path is not.
