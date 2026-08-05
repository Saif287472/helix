# Package: helix_remote_cli

Status: current. Package-level counterpart to the backend module docs, from
the [structural upgrade plan](../../../docs/architecture/EARNMINUTE_STRUCTURAL_UPGRADE_PLAN.md)
(item A4). States in prose what
[`module_boundaries.json`](../../../docs/architecture/module_boundaries.json)
enforces at build time via `tool/check_boundaries.dart` — the config is the
authority; this is the explanation that sits next to the code.

## Purpose

A headless client used for end-to-end testing and operator debugging:
register, log in, publish prekeys, send and receive messages without the
Flutter app.

## Public surface

`lib/helix_remote_cli.dart` exports `cli_secure_storage`, `cli_client`,
`cli_rest_client`, `cli_message_envelope`.

## Who may depend on this

Nothing. It is a leaf — tests and tooling invoke it, no package imports it.

## What this may depend on

`helix_remote_domain`, `helix_remote_api`, `helix_remote_crypto`,
`helix_remote_storage`, plus `crypto`, `cryptography` and `path`.

## Gotchas

- **`cli_secure_storage` is a file-backed stand-in for the platform
  keychain.** It exists so the CLI can run headless; it is not a secure
  store and must not be used by the app.
- **`verify.sh` runs this package's tests with `flutter test`, not `dart
  test`**, even though its own pubspec has no `sdk: flutter`. It transitively
  depends on `helix_remote_crypto`, which is Flutter-based, and plain `dart
  test` fails to resolve `dart:ui` in that case. The comment in
  `scripts/verify.sh` says so; don't "simplify" it back.
