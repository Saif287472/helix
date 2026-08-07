# External security review gate

No public Helix Remote release may claim an independent penetration test or
cryptographic review until this gate has evidence from an external reviewer.

## Required evidence

- A dated, scoped penetration-test report covering Android, Windows, backend
  HTTP/WebSocket APIs, admin pairing, federation, and deployment boundaries.
- A cryptographic review that verifies the implementation rather than only the
  design document, including X3DH session setup, ratchet behavior, replay and
  out-of-order handling, key storage, backup encryption, attachments, and
  group epochs.
- Severity disposition for every Critical/High finding, signed by the release
  owner and reviewer.
- Retest evidence for remediated findings and the exact release commit/artifact
  hashes assessed.

## Current status

**Not complete.** Repository tests and the internal design review are useful
inputs but are not substitutes for an independent assessment. The release
checklist must retain this blocker until the above evidence is attached.
