# Audit Event Policy

Helix is an ephemeral messenger. Audit events must not become a permanent
interaction history by accident.

## Default Retention

- Audit events are RAM-only by default.
- Persistent audit events require a documented privacy justification.
- Diagnostic export requires explicit user action.

## Event Content

Audit events must not contain message content, media names, secret sentences,
cryptographic keys, or full fingerprints. Use truncated or pseudonymous
identifiers where practical.

## Event Categories

- RAM-only: trust prompts, group admin attempts, wipe starts/completions,
  identity verification prompts, protocol compatibility warnings.
- Persisted only with approval: crash-safe migration markers and explicit
  security-recovery events.

Thread wipe, application wipe, and identity reset must remove RAM-only audit
state and any approved persisted audit state tied to the wiped identity.
