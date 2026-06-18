# Calls

## Intended Behavior

Future Phase 5 calls use local-only WebRTC media negotiated over existing secure
peer channels. Calls should work on an offline LAN without STUN/TURN.

## Invariants

- Capability negotiation gates call UI.
- Candidate filtering keeps traffic local-only unless a future relay feature is
  explicitly designed.
- Microphone/camera permissions are requested only when needed.
- Call setup must not expose message content, keys, or fingerprints in logs.

## Failure Handling

- Missing permissions produce recoverable UI state.
- Unsupported peer capabilities hide or reject calls gracefully.

## Verification

- Unit tests around future call state machines.
- Offline Windows-to-Android LAN manual check before release.
