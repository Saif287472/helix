# ADR 020: Federated Group Home-Server Authority

Status: accepted
Date: 2026-07-17

## Context
Milestone 4 extends groups (Milestone 1) across server boundaries using the
S2S trust anchor established in Milestone 3 (ADR 012, ADR 019): a signed
Ed25519 handshake that proves which server sent a request, but says nothing
about whether the account named inside that request is actually a member or
admin of a given group. Federated group membership/role mutations need a
trust model that answers that second question without inventing new
cryptographic primitives (ADR 012) or distributed-consensus machinery
disproportionate to a modular monolith (ADR 010).

## Decision
The server that processes a group's `POST /groups/create` becomes that
group's **home server** and is the single source of truth for its
membership, roles, invites, and settings for the group's lifetime. Every
other server hosting a member is a **participant**: it keeps a synced
read-model (`federated_groups`, `federated_conversation_members`,
`federated_group_invites`) and proxies its local admins' mutating requests
to the home server over the existing signed S2S channel
(`POST /api/v1/s2s/groups/action`). The home server validates, mutates its
own database, and pushes the resulting state to every participating domain
(`POST /api/v1/s2s/groups/sync`). Trust is anchored entirely in the
already-established S2S server-identity signature — a sync push for a given
`group_id` is only accepted from the `server_id` that has previously been
associated with that group as home (first-write, then pinned).

Sender Key epoch-key distribution (Milestone 4.2) is deliberately **not**
home-gated: any account holding an ADMIN role — home or participant, once
recognized via the synced roster — may rotate and redistribute group keys
directly to all members' devices. Membership authority and key-distribution
authority are separate concerns; only the former needs a single mutation
point.

## Consequences
- No new signing scheme, per-action device signatures, or conflict
  resolution logic is required — federated group authority reuses exactly
  the server-identity trust already proven in Milestone 3.
- A participant server cannot mutate group membership/roles while
  disconnected from home; this is an accepted availability trade-off
  (ADR 010) rather than building leaderless replication for groups.
- Read-only participant views may lag home by one round-trip during a
  mutation; `GET /api/v1/s2s/groups/state` exists as a pull-based self-heal
  escape hatch for a participant that suspects its mirror has drifted.
- If a group's home server is permanently lost, the group has no path to a
  new home in this milestone — a known limitation for a future milestone,
  not addressed here.
