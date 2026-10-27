# ADR 034: Group calls are a mesh of pairwise calls, up to four people

Status: accepted (2026-10-28), after the user chose "mesh, up to 4" and
"voice and video" when asked on 2026-10-28. Steps 1 to 4 of "Build order" are built (2026-10-28); the
end-to-end test, the coturn range and the device checks are not.

Plan of record: `docs/architecture/ARCHITECTURE_V2_PLAN.md` (§3 module list,
`group_calls`; §12 change log). Un-defers the 2026-10-01 decision "group calls
deferred from v2" for this shape only.

## Context

1:1 calls work: sealed pairwise signals over `POST /v1/calls/{call_id}/signals`,
one WebRTC peer connection per call, relay-only candidates through the PC's
coturn (`IpPrivacyMode.relayOnly`), end-to-end encryption by DTLS-SRTP between
the two phones. The server sees a call id, two parties and a kind
(`offer | update | end`), nothing else.

A group call needs more than two media paths. There are two ways to get them:

- **An SFU** (a media server forwards one stream per person). It scales to
  dozens of people, but it is new software to run on the PC, new ports, and a
  server that touches media. Keeping the calls end-to-end encrypted through an
  SFU needs frame-level encryption (SFrame) with a group key schedule. That is
  new crypto, which the repo's rules say needs vectors and a design-review note,
  and which has had no external review.
- **A mesh**: every participant holds one ordinary pairwise connection to every
  other. Nothing new runs on the server, and each link is exactly the proven
  1:1 construction, so the end-to-end claim is unchanged. The price is
  bandwidth: each phone uploads its media once per other person.

The user chose the mesh, capped at four people, voice and video.

## Decision

1. **A group call is a room of pairwise calls.** Every pair of participants
   has one call, with its own call id, signalled and encrypted exactly as a 1:1
   call today. The server's `calls` module does not change: no migration, no new
   route, no new public route, no new `.env` line. The `group_calls` module in
   the plan stays unbuilt, because there is no server-side room to keep.
2. **The room lives in the sealed payload.** `CallSignalPayload` gains
   `room: {id, group, participants, media}` on `offer` (all optional, so a
   peer that does not know it reads a plain 1:1 offer and the user sees an
   ordinary call). `room.id` is a client-made random id; `room.group` is the
   group conversation id; `room.participants` lists the accounts in the room
   when the offer was made. The server never sees any of it.
3. **Who offers to whom.** The starter offers to every other member it invites
   (at most three). A later joiner offers to everyone already in the room, whose
   accounts it learned from the offer that rang it; so, for every pair, the
   person who arrived later makes the offer. That removes glare inside a room.
   Existing members answer.
4. **Limits.** At most four people in a room (`GroupCallLimits.maxParticipants`).
   A fifth person's join is refused with `full` on the first offer they send
   (an `end` with reason `busy` is already the signal for it). The group's
   member list is the invitation list; a person not in the group is never
   invited, and a blocked member's offers are refused by the server as today.
5. **Media is capped to fit a relay.** Because candidates are relay-only, all
   media passes through the user's PC. A four-person video room is twelve
   streams through coturn. So group video is limited to 480p at 15 fps with a
   bitrate cap near 400 kbit/s per link, voice to about 32 kbit/s, and the
   screen-sharing button (D1) stays off in a room in this version. A room that
   cannot carry its video drops to voice per link, not the whole call.
6. **Engine shape.** A new `GroupCallsService` in `helix_remote_engine` owns
   a room: its participants (each with a `CallPhase`), a map of per-peer
   `CallMediaSession`s from the existing seam, and one shared local audio and
   video capture. It reuses the 1:1 service's signalling helpers
   (`CallSignaling`, sealed payloads, ICE queueing) rather than copying them.
   `CallsService` keeps owning 1:1 calls, and the two refuse each other (one
   call of either kind at a time, as today: `busy`).
7. **Media layer.** `RemoteWebRtcCallEngine` today refuses a second call
   ("Only one remote call can own media at a time") and opens its own capture
   per call. It becomes one capture shared by several peer connections (one
   per link), each added to the same local tracks. The `CallMediaSession`
   interface does not change.
8. **The group chat shows it.** A group call is announced in the group chat
   as a `call_log` entry (type exists), posted by the starter's device; each
   member's missed or answered state stays local, as for 1:1.
9. **Late join is not in the first version.** The room is the set of people
   invited when it starts (the offers carry the whole list), so everyone who may
   be in it is known to every participant and nobody needs a roster. Someone not
   invited cannot join later; to add a person, start a new room. (The roster
   request sketched below under "Open points" is dropped for now.)
10. **Ringing.** An invitation is a normal pairwise offer, so offline members
   get the existing pending-call row and push, and the app rings "Group call in
   <group name>" instead of a person's name. Joining late from the group chat
   is decision 9: not in the first version.

## Consequences

- **No server, no wire-route, no schema change.** The sealed payload grows by
  an optional object; `docs/protocol/v2/REST_V2.md` records it; the DTO round
  trip test gets a room case. Old apps still ring and answer as 1:1 calls from
  the starter and simply have no room.
- **Privacy is unchanged per link** (DTLS-SRTP, relay-only, no server-visible
  content). Each participant learns every other participant's account (they
  are group members already) and the relay learns the room's traffic shape,
  as it learns a 1:1 call's. The threat model gets one added line: in a mesh,
  a participant's phone connects to every other, so every participant is on the
  relay for every other.
- **Load on the PC.** A four-person video call is about 12 relayed streams, a
  few Mbit/s each way. Three simultaneous rooms of four would be about 35
  streams. The relay's port range (49160-49200) is 41 ports, enough for about
  20 relayed allocations, so the range in `deploy/coturn` must be widened
  before the feature is turned on. The release notes say so.
- **Battery and data.** Each phone uploads one video stream per other person,
  and decodes up to three. Voice-only rooms are cheap; video rooms are the
  expensive case, hence the caps.
- **Not included (and still in the not-doing list):** call links, waiting
  rooms, scheduled calls, more than four people, an SFU.

## Alternatives considered

- **SFU with SFrame.** Right answer for 8 to 30 people; rejected for now
  because of the crypto it needs and the new server to operate. The signalling
  in this ADR does not stop it: `room` could later name an SFU as the only
  peer.
- **Voice-only mesh to 8.** Cheaper, and could still be offered as a later
  limit for rooms with no video.
- **A server-side room in `group_calls`.** Would let a late joiner ask the
  server who is in; rejected because the server would learn who talks to whom
  and when, which the 1:1 design avoids.

## Build order (each step is committed and tested alone)

1. Protocol: `room` in the sealed payload, round-trip tests, REST_V2.md.
2. Media layer: one capture, several peer connections (`helix_remote_calls`),
   with the bitrate caps; a loopback test of three fake peers.
3. Engine: `GroupCallsService` over the fake media (rooms of 2 to 4, late
   join, leave, a full room, glare, a blocked member, one call at a time).
4. App: the call grid on orbit_ui (a tile per person, mute and camera per
   tile state), a group call button in the group chat header, the ringing and
   missed-call text, the `call_log` entry.
5. Server end-to-end test (two to three real engines through the real server)
   and the coturn port range in `deploy/coturn`.
6. Device checks on three phones.

## Open points

- Late join from the group chat: needs a roster signal; not built, see
  decision 9.
- Whether a voice-only fifth to eighth person is worth a later version.
- The Windows client's capture limits (one camera, one microphone is the
  same as today).
