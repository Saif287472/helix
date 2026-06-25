# F8 — Group Calls, Planned Calls, Call Links, and Screen Sharing

**Date:** 2026-06-25
**Phase:** F8
**Status:** Implemented — 2026-06-25

## Implementation summary

All F8 deliverables completed:

| Area | File(s) |
|---|---|
| Backend schema v24 | `backend/lib/src/database/migrations.dart` |
| Backend group-call repository | `backend/lib/src/database/group_calls_repository.dart` |
| Backend REST module (15 endpoints) | `backend/lib/src/modules/group_calls.dart` |
| Server wiring | `backend/lib/src/server_impl.dart` |
| App domain models | `packages/helix_remote_domain/lib/domain/group_call.dart` |
| App storage repository + v20 migration | `packages/helix_remote_storage/lib/src/database/group_calls_repository.dart` |
| `RemoteGroupCallService` (full-mesh N-1 engines) | `packages/helix_remote_calls/lib/src/remote_group_call_service.dart` |
| `GroupCallScreen` UI | `app/lib/screens/group_call_screen.dart` |
| `CallLinkSheet` UI | `app/lib/screens/call_link_sheet.dart` |
| `ScheduledCallsScreen` UI | `app/lib/screens/scheduled_calls_screen.dart` |
| Capability registry | `packages/helix_remote_domain/lib/domain/capabilities.dart` |
| Backend F8 tests | `backend/test/group_calls_f8_test.dart` |
| App service F8 tests | `packages/helix_remote_calls/test/group_call_service_f8_test.dart` |

## Goal

Introduce multi-party calling as a separate call-room platform: full-mesh P2P up to 4
participants, encrypted room keys, call links, scheduled calls, screen sharing,
active-speaker detection, participant controls, and room-key rotation.

---

## Architecture decisions

### 1. Topology — full-mesh P2P (≤ 4 participants)

**Decision:** Full mesh with existing WebRTC infrastructure. Each participant holds
N−1 `RemoteCallEngine` instances (one per remote participant). Rooms with a 5th join
request are rejected with HTTP 409 `room_full`.

**Rationale:** Avoids SFU deployment cost and complexity in F8. 4-participant cap is
within typical device capability. SFU migration is deferred to F8B if needed.

**Bandwidth model (per participant):**
| Participants | Outgoing streams | Max uplink (video 480p) |
|-------------|-----------------|------------------------|
| 2 | 1 | ~1.5 Mbps |
| 3 | 2 | ~3 Mbps |
| 4 | 3 | ~4.5 Mbps |

### 2. E2EE — room key per epoch

Each room carries an encrypted room key (`room_key_id` / `epoch`). The key is never
sent to or stored by the backend in plaintext. The host wraps the room key for each
participant device using that device's existing session encryption (same X3DH-derived
shared secret used for messages). The backend stores `wrapped_key` blobs only.

On join/leave/kick/device-revoke the host increments the epoch and delivers new
wrapped keys to all remaining participants via `POST /api/v1/group-calls/:roomId/key`.
Participants who cannot receive the new key (offline) will be kicked on reconnect.

### 3. Screen sharing

Represented as an additional video track negotiated as a renegotiation offer with
`content_type: screen`. Participants declare `is_screen_sharing: true` in their
participant row; the room event fan-out notifies all other participants to expect a
second incoming video stream.

### 4. Active speaker detection

`RemoteGroupCallService` samples audio levels from each `RemoteCallEngine` and emits
`RemoteGroupCallSpeakerEvent` when the dominant speaker changes. A 1-second hysteresis
prevents rapid flipping.

### 5. Call links

High-entropy link tokens (UUID v4, 36 chars). Stored in `call_links`. Each link
optionally requires host approval (`requires_approval`). Rate-limited: max 20
links/day per account. Auto-expire after 7 days or when explicitly revoked.

### 6. Scheduled calls

`scheduled_calls` with title, host, scheduled_at, attendee list, and RSVP state.
Attendees receive a WebSocket `scheduled_call_invite` event. Reminders are queued into
the outbox 15 minutes before `scheduled_at`. Cancellation sends a
`scheduled_call_cancelled` event to all attendees.

---

## Schema changes — backend v24

```sql
CREATE TABLE call_rooms (
  room_id        TEXT PRIMARY KEY,
  host_account_id TEXT NOT NULL,
  host_device_id  TEXT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'WAITING',  -- WAITING | ACTIVE | ENDED
  is_video        INTEGER NOT NULL DEFAULT 0,
  max_participants INTEGER NOT NULL DEFAULT 4,
  room_key_id     TEXT,
  room_key_epoch  INTEGER NOT NULL DEFAULT 0,
  created_at      INTEGER NOT NULL,
  started_at      INTEGER,
  ended_at        INTEGER
);

CREATE TABLE call_room_participants (
  room_id           TEXT NOT NULL REFERENCES call_rooms(room_id) ON DELETE CASCADE,
  account_id        TEXT NOT NULL,
  device_id         TEXT NOT NULL,
  role              TEXT NOT NULL DEFAULT 'PARTICIPANT',  -- HOST | PARTICIPANT
  status            TEXT NOT NULL DEFAULT 'INVITED',      -- INVITED | JOINED | LEFT | KICKED
  is_screen_sharing INTEGER NOT NULL DEFAULT 0,
  joined_at         INTEGER,
  left_at           INTEGER,
  PRIMARY KEY (room_id, device_id)
);

CREATE TABLE call_room_keys (
  room_id       TEXT NOT NULL REFERENCES call_rooms(room_id) ON DELETE CASCADE,
  epoch         INTEGER NOT NULL,
  device_id     TEXT NOT NULL,
  wrapped_key   TEXT NOT NULL,
  delivered_at  INTEGER,
  PRIMARY KEY (room_id, epoch, device_id)
);

CREATE TABLE call_links (
  link_id           TEXT PRIMARY KEY,
  link_token        TEXT NOT NULL UNIQUE,
  room_id           TEXT REFERENCES call_rooms(room_id) ON DELETE SET NULL,
  created_by        TEXT NOT NULL,
  requires_approval INTEGER NOT NULL DEFAULT 0,
  max_uses          INTEGER NOT NULL DEFAULT 0,  -- 0 = unlimited
  use_count         INTEGER NOT NULL DEFAULT 0,
  created_at        INTEGER NOT NULL,
  expires_at        INTEGER NOT NULL,
  revoked_at        INTEGER
);
CREATE INDEX idx_call_links_token ON call_links(link_token);
CREATE INDEX idx_call_links_owner ON call_links(created_by, created_at DESC);

CREATE TABLE scheduled_calls (
  scheduled_call_id TEXT PRIMARY KEY,
  room_id           TEXT REFERENCES call_rooms(room_id) ON DELETE SET NULL,
  host_account_id   TEXT NOT NULL,
  title             TEXT NOT NULL,
  scheduled_at      INTEGER NOT NULL,
  created_at        INTEGER NOT NULL,
  cancelled_at      INTEGER
);

CREATE TABLE scheduled_call_attendees (
  scheduled_call_id TEXT NOT NULL REFERENCES scheduled_calls(scheduled_call_id) ON DELETE CASCADE,
  account_id        TEXT NOT NULL,
  rsvp_status       TEXT NOT NULL DEFAULT 'PENDING',  -- PENDING | YES | NO
  notified_at       INTEGER,
  PRIMARY KEY (scheduled_call_id, account_id)
);
```

---

## New REST endpoints — `/api/v1/group-calls`

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/` | Create room |
| GET | `/:roomId` | Get room state + participant list |
| POST | `/:roomId/join` | Join room (or request approval via link) |
| POST | `/:roomId/leave` | Leave room |
| POST | `/:roomId/end` | Host ends room |
| POST | `/:roomId/kick` | Host kicks a participant |
| POST | `/:roomId/key` | Deliver wrapped room key (host only) |
| POST | `/:roomId/screen-sharing` | Toggle screen sharing status |
| POST | `/links` | Create call link |
| GET | `/links/:token` | Resolve call link → room info |
| DELETE | `/links/:token` | Revoke call link |
| POST | `/scheduled` | Create scheduled call |
| GET | `/scheduled` | List scheduled calls for account |
| POST | `/scheduled/:id/rsvp` | RSVP to scheduled call |
| DELETE | `/scheduled/:id` | Cancel scheduled call (host only) |

---

## New capabilities

| Constant | String |
|----------|--------|
| `groupCallsV1` | `helix.remote.group-calls.v1` |
| `callLinksV1` | `helix.remote.call-links.v1` |
| `scheduledCallsV1` | `helix.remote.scheduled-calls.v1` |
| `backendSchemaV24` | `helix.remote.backend-schema.v24` |

---

## Test coverage

- `backend/test/group_calls_f8_test.dart`: room CRUD, join/leave, capacity limit,
  screen sharing toggle, call link lifecycle, scheduled call + RSVP + cancellation,
  room-key delivery
- `packages/helix_remote_calls/test/group_call_service_f8_test.dart`: participant
  tracking, active-speaker detection, room-key rotation trigger, screen sharing state
