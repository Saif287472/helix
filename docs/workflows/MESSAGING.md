# Messaging

## Intended Behavior

Messages are attached to secure threads, delivered over secure channels, and
updated by acknowledgements, receipts, edits, deletes, reactions, and wipes.

## Invariants

- Message content is never logged.
- Thread state changes notify providers.
- Per-thread wipe clears only the target thread.
- Protocol receive handlers create/update messages idempotently.

## Failure Handling

- Disconnected threads remain visible until manually closed or auto-wiped.
- Unknown optional protocol behavior must fail closed or be ignored safely based
  on capability negotiation.

## Verification

- `test/phase0_test.dart`
- `test/provider_refresh_test.dart`
- Protocol fixture tests.
