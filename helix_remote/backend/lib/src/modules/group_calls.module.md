# Module: group_calls

Status: current. Follows the template in `messaging.module.md`.

## Purpose

F8 multi-party calling: rooms with a host and participants, shareable call
links, and scheduled calls with RSVPs. Distinct from `calls/`, which is
strictly 1:1.

## Owned files

- `group_calls.dart` - `GroupCallsModule` and its router.

## Route table

Mounted at `/api/v1/group-calls`. All routes require a session.

| Method | Path | Handler | Notes |
|---|---|---|---|
| POST | `/` | `_handleCreateRoom` | Creator becomes HOST and is joined immediately. Room opens WAITING. |
| GET | `/<roomId>` | `_handleGetRoom` | Room state plus participants. |
| POST | `/<roomId>/join` | `_handleJoinRoom` | Max 4 participants. First join flips the room to ACTIVE. |
| POST | `/<roomId>/leave` | `_handleLeaveRoom` | The last participant leaving ends the room. |
| POST | `/<roomId>/end` | `_handleEndRoom` | Host only. |
| POST | `/<roomId>/kick` | `_handleKickParticipant` | Host only. |
| POST | `/<roomId>/key` | `_handleDeliverRoomKey` | Host only. Wrapped key capped at 2048 chars. |
| POST | `/<roomId>/screen-sharing` | `_handleScreenSharing` | JOINED participants only. |
| POST | `/links` | `_handleCreateLink` | 7-day expiry, optional use limit. |
| GET | `/links/<token>` | `_handleResolveLink` | 410 when revoked or expired. |
| DELETE | `/links/<token>` | `_handleRevokeLink` | Creator only. |
| POST | `/scheduled` | `_handleCreateScheduled` | Title capped at 200 chars. |
| GET | `/scheduled` | `_handleListScheduled` | |
| POST | `/scheduled/<id>/rsvp` | `_handleRsvp` | `RsvpStatus`: pending / yes / no. |
| DELETE | `/scheduled/<id>` | `_handleCancelScheduled` | Host only. 409 if already cancelled. |

## Error codes this module throws

The [`AppError`](../app_error.dart) shape, via three small factories
(`_unauthorized`, `_badRequest`, `_notFound`) that return the error so their
call sites read as throws. Also `.forbidden` (host-only actions),
`.conflict` (room full, already cancelled), and a bare status-410
`AppError` for a revoked or expired link or a cancelled scheduled call.
The room-full conflict attaches `max` through `AppError.withDetails`.

## Dependencies

- `BackendDatabase` (`../database.dart`) - rooms, participants, links,
  scheduled calls.
- `WebSocketRelay` (`../websocket.dart`) - notifying participants of joins,
  leaves, kicks and key rotations.

## Gotchas

- **`_maxParticipants` is 4.** This is a mesh, not an SFU - see
  `docs/architecture/adr_group_calls.md`.
- **The room lifecycle is enforced by `RemoteCallRoomStatus`** in
  `helix_remote_domain`, not only by the SQL `WHERE` clauses (plan item
  A6). `joinCallRoom` now throws on an ended room instead of updating zero
  rows and reporting success.
- **Ending a room is idempotent on purpose.** Both the host's explicit end
  and the last participant leaving can reach `endCallRoom`; whichever
  arrives second must not fail.
- **A kicked participant cannot rejoin, but one who left can.**
  `RemoteCallRoomParticipantStatus` encodes that: `left -> joined` is legal,
  `kicked -> joined` is not, or kicking would achieve nothing.
- **Room keys are wrapped per recipient by the host**, not generated
  server-side. The server relays opaque bytes and enforces only a length
  cap.
