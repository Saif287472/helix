# ADR: Remote Group Call Architecture - SFU over Peer-to-Peer Mesh

**Status:** Draft
**Date:** 2026-06-19
**Phase:** P16-015

---

## Context

Helix Remote supports one-to-one audio/video calls using peer-to-peer WebRTC with STUN/TURN
for NAT traversal (Phase 15). Phase 16 adds persistent Remote groups. Users will eventually
expect group calling capability within those groups.

This ADR records the architectural decision for how group calls should be implemented when
that work is prioritized. No group call code is added in Phase 16.

---

## Decision

When group calls are implemented, use a **Selective Forwarding Unit (SFU)** architecture
rather than a peer-to-peer mesh or an MCU.

The Local app's LAN host-election mechanism (`helix_local_groups`) MUST NOT be reused,
adapted, or imported for Remote group authority. Remote group authority is established
through the `ADMIN` role stored in `conversation_members` on the backend, not through
peer election.

---

## Rationale

### Why not peer-to-peer mesh?

- Each participant uploads N-1 streams and downloads N-1 streams, where N is the group size.
- Bandwidth scales as O(N^2). At 4 participants on a typical mobile upload of 500 Kbps
  this is already saturated.
- Acceptable only for 2-person calls (Phase 15) and possibly 3-person under ideal conditions.

### Why SFU over MCU?

| Property            | SFU                              | MCU                              |
|---------------------|----------------------------------|----------------------------------|
| Server load         | Routing only (no transcoding)    | Transcoding every stream         |
| Latency             | Lower (no mix-encode pipeline)   | Higher (mix-encode pipeline)     |
| Client complexity   | Each client manages N streams    | Each client receives 1 mix       |
| Solo-operator cost  | Lower                            | Higher CPU/GPU required          |

For a solo-maintained product the SFU model is preferred. The reduced server cost and
lower latency outweigh the additional client-side complexity of managing multiple incoming
streams.

### Why not reuse Local host election?

- Local host election (`LobbyElectionEngine`) is designed for LAN peer discovery: it uses
  mDNS broadcasts, LAN-private IP addresses, and transient peer sets.
- Remote participants are internet-connected, identified by Remote account/device IDs, and
  their membership is authoritative on the backend.
- Importing any `helix_local_*` package into Remote code violates the isolation boundary
  enforced by architecture tests and the workspace package firewall.
- Remote group admin authority is a persistent server-side role, not a runtime election.

---

## Consequences

- Group calls require a dedicated media SFU server (e.g., mediasoup, Janus, Jitsi Videobridge).
- SFU deployment is deferred until the group call feature is explicitly prioritized and funded.
- The call signaling infrastructure from Phase 15 (`POST /api/v1/calls/signal`) can be
  reused for group call setup, but the WebRTC topology and SFU session management require
  a separate implementation pass.
- When group calls are added, all participants MUST be identified by Remote account/device
  IDs. Local LAN peer IDs must not appear in any group call payload or session state.
- This ADR must be reviewed before any group call implementation begins.

---

## Rejected Alternatives

| Alternative             | Reason rejected                                         |
|-------------------------|---------------------------------------------------------|
| P2P mesh                | O(N^2) bandwidth; unacceptable beyond 2-3 participants  |
| MCU                     | High server transcoding cost; added latency             |
| Local host election     | LAN-only protocol; isolation violation                  |
| Deferred indefinitely   | Decision should be recorded now to avoid ad-hoc choices |
