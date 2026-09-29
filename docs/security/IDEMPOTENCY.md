# Idempotency Policy

> **Scope: Helix Local only.** Written for the June 2026 single-workspace layout (`apps/`, `packages/local/`); Local code now lives under `helix_local/`. For Helix Remote see `helix_remote/docs/` and `AGENTS.md`.

Retried network operations must be safe.

## Required Protections

- Connection requests: deduplicate by peer identity and request ID.
- Group joins/admin operations: include membership version or election epoch.
- File transfer resume: verify byte offset and hash state before appending.
- Protocol envelopes: future `frameId` and `correlationId` fields should enable
  request-response matching and deduplication.
- Wipe operations: repeated wipe commands must leave the same final state.

## Transactional Consistency

Operations that combine trust records, session state, group membership, or file
state need atomic updates once persistence seams exist. Until then, tests should
assert the in-memory final state after retries.
