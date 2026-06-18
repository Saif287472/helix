# Trust Establishment

## Intended Behavior

Trust is based on cryptographic identity fingerprints. Secret sentences help
humans discover or pair with peers, but they are not the trust anchor.

## Invariants

- Trust records bind peer identity fingerprint to user approval.
- Verification phrases are derived from fingerprints and are safe for human
  comparison.
- Full fingerprints remain available for advanced audit.
- Trust prompts must not auto-approve changed identities.

## Failure Handling

- Fingerprint mismatch produces an explicit warning.
- Missing trust hides or blocks sensitive actions until the user decides.

## Verification

- Identity phrase tests.
- Request/connection integration tests.
- Manual review for trust-copy changes.
