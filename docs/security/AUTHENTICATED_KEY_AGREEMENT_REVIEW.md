# Authenticated Key-Agreement Review

Status: internal review complete for Phase 7

## Scope

This review covers the current Helix Local peer-channel handshake, identity
binding, capability advertisement, and per-message chain-key derivation.

## Findings

- Static identity fingerprints are the Local trust anchor.
- TLS protects the transport, and the peer static public key fingerprint is
  checked against the expected fingerprint on trusted reconnect paths.
- The current app derives per-message chain keys and ratchets them in RAM.
- The current app must not advertise forward secrecy as a product capability.

## Decision

`kCapForwardSecrecy` remains reserved but is not included in `kCapAll`.

Forward-secrecy claims require a later authenticated DH/ECDH design, protocol
fixtures, downgrade tests, and external cryptographic review.

## Verification

- `tool/check_release_hardening.dart` fails if `kCapForwardSecrecy` is
  advertised in `kCapAll`.
- `apps/helix_local/test/phase7_test.dart` checks the same claim boundary.
