# ADR 021: Federated Call Signaling — Bilateral Relay, No Home-Server Authority

Status: accepted
Date: 2026-07-17

## Context
Milestone 5 extends 1:1 WebRTC call signaling (offer/answer/ICE/decline/
busy/cancel/end) across server boundaries. Unlike groups (ADR 020), a call
has exactly two participants and no shared, persistent resource that needs
a single authoritative owner — there is nothing analogous to "whichever
server created this" to elect as home. A federated equivalent of the local
`contacts` trust gate also doesn't exist anywhere in the codebase (contacts
remain fully local, FK-locked, with no S2S counterpart), and building one
was out of scope for what this milestone asks for.

## Decision
Call signaling is relayed **bilaterally**: each server forwards a signal to
whichever domain the *other* party lives on, via `POST /api/v1/s2s/calls/signal`,
mirroring the message-proxy pattern already established in Milestone 3
(`FederationClient.proxyMessage`) rather than the groups home-authority
pattern. Each side maintains its own `pending_calls` row for the call —
the caller's server tracks it with no local target devices when the callee
is remote (fan-out is delegated entirely to the callee's server), and vice
versa; there is no shared/synced call state.

**Trust gate**: a federated offer is only permitted between two accounts
that already share a federated DIRECT conversation (`hasSharedDirectConversation`),
reusing Milestone 3/4's established conversation-membership authorization
rather than inventing a federated contacts system. This check runs only on
the *originating* server, before it proxies — the receiving server trusts
the sending server's S2S signature alone (same posture as
`/s2s/messages/proxy`, which doesn't re-validate conversation membership
either) and skips local-device-active checks for the asserted remote
party, since those can't be verified against a device table it doesn't own.

**TURN/STUN**: each client fetches TURN credentials only from its own home
server (already the existing, unchanged behavior of `GET /calls/turn-credentials`).
No S2S credential-sharing route was added — ICE naturally negotiates the
best available candidate pair using each side's own relay if a direct P2P
path fails, satisfying Phase 5.2 without new protocol surface.

## Consequences
- No new signing scheme or per-call authority record — reuses the existing
  S2S Ed25519 server-identity trust and the conversation-membership check
  Milestone 3 already established.
- A federated call cannot proceed if the two accounts have never had a
  federated DIRECT conversation created between them; this is an accepted
  scope boundary, not an oversight — building a standalone federated
  contacts/friend-request flow was not requested by this milestone.
- Group (multi-party) call federation is explicitly out of scope — the
  plan's Phase 5.1 language ("caller's home server and callee's home
  server") is 1:1-specific, and `call_rooms` retains no home-server concept.
