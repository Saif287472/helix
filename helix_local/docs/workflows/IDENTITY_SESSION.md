# Identity Generation & Session Lifecycle

## Intended Behavior

Helix creates a local identity, derives a device suffix/fingerprint, and
uses a session ID for current LAN presence. Identity is long-lived until reset;
session IDs are runtime presence markers.

## Invariants

- Private identity material never appears in UI, logs, diagnostics, or protocol
  payloads.
- Fingerprints are the trust anchor.
- Session IDs must not replace identity fingerprints for trust decisions.
- Identity reset invalidates trust/session state tied to the old identity.

## Failure Handling

- Secure-storage failures should surface as setup/session errors, not silent
  identity regeneration.
- Missing identity blocks secure chat startup.

## Verification

- Profile validation tests.
- Crypto tests for suffix/session helpers.
- Full verification for any secure-storage or identity-key change.
