# Package: helix_remote_crypto

Status: current. Package-level counterpart to the backend module docs, from
the [structural upgrade plan](../../../docs/architecture/EARNMINUTE_STRUCTURAL_UPGRADE_PLAN.md)
(item A4). States in prose what
[`module_boundaries.json`](../../../docs/architecture/module_boundaries.json)
enforces at build time via `tool/check_boundaries.dart` — the config is the
authority; this is the explanation that sits next to the code.

## Purpose

Every cryptographic primitive Remote relies on: X3DH key agreement, the
Double Ratchet session, prekey management, group (Sender Key) encryption,
attachment and backup encryption, and the device-transfer handshake.

## Public surface

`lib/helix_remote_crypto.dart` exports `x3dh`, `double_ratchet`,
`secure_key_storage`, `prekey_manager`, `group_encryption`,
`attachment_crypto`, `backup_crypto`, `transfer_handshake`.

## Who may depend on this

The app, the CLI, and `helix_remote_groups`. The backend does **not** — it
never holds a key capable of decrypting user content, which is the whole
point of the architecture.

## What this may depend on

`helix_remote_domain`, `cryptography`, `cryptography_flutter`, `crypto`,
`flutter_secure_storage`. Forbidden from importing Local packages or app
code.

## Gotchas

- **This package is why the backend cannot read messages.** Anything that
  would give the server a usable key is a design violation, not a feature.
- **Double Ratchet session state must be persisted atomically with the
  message write it belongs to**, or a crash between the two desynchronizes
  the ratchet and the session has to be reset.
  `docs/architecture/CURRENT_STATE_2026-06-20.md` classifies Remote crypto
  sessions as Defective for this class of bug; treat changes here as
  high-risk.
- **Skipped-message keys are retained bounded, not forever.** Out-of-order
  delivery works within that bound and fails outside it.
- **`docs/ai/AI_GUARDRAILS.md` lists the E2EE guarantees as
  non-negotiable.** Read it before changing anything in this package.
