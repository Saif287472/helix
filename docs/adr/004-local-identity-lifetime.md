# ADR 004: Local Identity Lifetime and Rotation

Status: accepted  
Date: 2026-06-19  

## Context
Helix Local must preserve user privacy and not rely on global, cross-session accounts. Users must be able to rotate or completely destroy their identities.

## Decision
Local identities are strictly install-scoped:
- Created locally on first run.
- Long-lived to allow trusted reconnection with nearby devices.
- Fully destroyed and rotated upon a manual identity reset or panic wipe.
- Never mapped to any server registry.

## Consequences
- A local reset ensures that all peer linkages are broken.
- No global account registration is required for Helix Local.
