# Package: helix_remote_crypto

Status: current. Helix Remote client cryptography, **not externally
reviewed** (ADR-028). The v1 crypto (per-conversation X3DH, symmetric-only
ratchet, v1 backup and transfer handshake) was deleted at Phase X.

## Purpose

Every cryptographic primitive the Remote client relies on, implementing
`docs/protocol/v2/CRYPTO_V2.md`: AIK device certificates, per-device-pair
X3DH, the full Double Ratchet (DH steps, skipped-key caps), a session manager,
Sender Keys behind `GroupCryptoProtocol`, prekey replenishment policy, safety
numbers, the password-wrapped AIK, attachment STREAM v2, backup envelope v3,
history backup, provisioning and sealed group-state and profile blobs.

## Public surface

`lib/v2.dart` is the package's only public library (sources in
`lib/src/v2/`; the name stays `v2.dart`, it was not renamed). It is pure
Dart: no Flutter, no `dart:io`, no storage, no v1 imports
(`test/v2/architecture_test.dart`).

## Who may depend on this

The engine, the CLI and the app (for random bytes and safety numbers). The
server does **not** depend on it except in tests (`server/test/client/`): it
never holds a key capable of decrypting user content, which is the whole
point of the architecture.

## What this may depend on

`helix_remote_protocol` (wire types, padding), `cryptography` and `crypto`.
Nothing that touches storage or the platform.

## Gotchas

- **Every operation returns new state for the engine to commit; nothing
  writes.** The engine commits session state in its own transaction before it
  sends, so a crash cannot desynchronise the ratchet.
- **Skipped-message keys are retained bounded, not forever** (1,000 per chain,
  2,000 per session, 30 days).
- **This package is why the server cannot read messages.** Anything that
  would give the server a usable key is a design violation, not a feature.

## Tests and vectors

- `dart test` runs the whole package (`flutter test` also works).
- Golden vectors live in `test/v2/vectors/`. Regenerate only deliberately,
  with `HELIX_UPDATE_VECTORS=1 dart test test/v2`, and review the diff.
- A crypto change needs vectors and a note in
  `docs/security/remote_cryptographic_design_review.md` §11.
