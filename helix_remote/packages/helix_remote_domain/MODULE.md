# Package: helix_remote_domain

Status: current. Package-level counterpart to the backend module docs, from
the [structural upgrade plan](../../../docs/architecture/EARNMINUTE_STRUCTURAL_UPGRADE_PLAN.md)
(item A4). States in prose what
[`module_boundaries.json`](../../../docs/architecture/module_boundaries.json)
enforces at build time via `tool/check_boundaries.dart` — the config is the
authority; this is the explanation that sits next to the code.

## Purpose

The innermost ring: entities, value types, repository contracts, and the
status transition tables. Pure Dart with no I/O, no platform bindings, and
no Flutter dependency — its only dependency is `meta`.

## Public surface

`lib/models.dart` is the barrel. It exports one file per concept:
`account`, `identity`, `device`, `contact`, `conversation`, `message`,
`message_content`, `capabilities`, `attachment`, `group`, `call`,
`group_call`, `sync`, plus the two lifecycle files:

- `remote_status.dart` — `RemoteMessageStatus`, `RemoteContactStatus`,
  `RemoteConversationStatus`, and the shared
  `RemoteIllegalStatusTransitionException`.
- `call_room_transitions.dart` — `RemoteCallRoomStatus`,
  `RemoteCallRoomParticipantStatus`, `RemoteGroupCallStatus`,
  `RemoteCallSessionStatus`, `RemoteOutboxStatus` (plan item A6).

## Who may depend on this

Everyone. Every other Remote package, the backend, the app and the admin
console all import it. That is precisely why it must stay dependency-free.

## What this may depend on

Nothing but `meta`. `module_boundaries.json` forbids it from importing
`helix_remote_api`, any Local-classified package, or app code. Adding a
Flutter dependency here would be a build-breaking boundary violation, not a
style opinion — it would drag Flutter into the Dart-only backend container.

## Gotchas

- **The transition tables are the one place lifecycle rules are allowed to
  live.** Both the app and the backend import them, so the two sides cannot
  disagree about what a legal state change is.
- **Statuses are strings, not enums, in the tables.** They cross the wire
  and the SQLite boundary as strings; validating the string form is what
  makes an unknown status a loud error instead of a silent parse fallback.
- **Keeping this package Flutter-free is load-bearing for deployment.** The
  backend's Dockerfile builds against `dart:stable`, which has no Flutter
  SDK; it copies only `backend/` and this package for exactly that reason
  (see `helix-remote-vps-handoff.md`).
