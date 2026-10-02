# Package: helix_remote_cli

Status: current. Holds two CLIs side by side until cutover: **v1** (below,
unchanged) and **v2** (`lib/v2.dart`, `lib/src/v2/`, `bin/helix_v2.dart`,
described at the end). Package-level counterpart to the backend module docs, from
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

## v2 CLI (`helix_v2`, Phase C3b)

A thin shell over `helix_remote_engine`: each run opens the encrypted
database, builds `HelixApi` and an `Engine`, runs one command and closes
everything. `dart run helix_remote_cli:helix_v2 help` lists the commands:
`register`, `login` (password), `link` / `link-approve` (QR code text),
`status`, `logout`, `contacts add|find|list`, `block`, `chats`, `send`
(one-shot), `chat` (interactive), `read`, `react`, `fetch`, `watch`,
`devices [revoke|revoke-others]`. `--json` makes every command print JSON.
Peers are `+number`, `~name`, a contact name or an id prefix.

- **State** lives in `--home DIR` (default `~/.helix_cli_v2`): `helix.db`
  (SQLCipher), `config.json` (server address) and, unless the key comes from
  the environment, `db.key`.
- **The database key** is read from `HELIX_DB_KEY` (64 hex characters) or
  `db.key`, created on first `register`/`login`/`link`. It is never printed.
  A key file beside the database protects against nothing a stolen directory
  exposes; for more than a test machine keep the key in the environment.
- **Secrets are never printed:** passwords come from `--password-env VAR` or a
  hidden prompt, the SMS code from `--code-env VAR` or a hidden prompt, tokens
  are never shown, phone numbers are masked (`+880********01`), other
  people's ids are shortened (`--json` carries the full account and device
  ids; they are not secrets). Error messages show codes, never bodies.
  `cli_test.dart` (server) asserts that no phone number, code, key or
  password appears in anything printed.
- **Exit codes:** 0 success, 1 failure, 2 misuse.
- **Rules** (`test/v2/architecture_test.dart`): v2 files import no v1 package,
  no v1 CLI file, no Flutter, drift, sqlite3 or HTTP.
- **Tests:** `test/v2/` (arguments, key handling, safe errors, no server) and
  `server/test/client/engine/cli_test.dart` (two homes exchange messages
  through the real server, a second CLI device is linked, a device is
  revoked).
