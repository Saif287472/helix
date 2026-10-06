# Package: helix_remote_cli

Status: current. The headless client, `helix_v2`. The v1 CLI was deleted at
Phase X.

## Purpose

A headless client used for end-to-end testing and operator debugging:
register, sign in, send and receive messages without the Flutter app. It is
a thin shell over `helix_remote_engine`: each run opens the encrypted
database, builds `HelixApi` and an `Engine`, runs one command and closes
everything.

## Public surface

`lib/v2.dart` is the package's only public library (sources in
`lib/src/v2/`; the name stays `v2.dart`). The executable is
`bin/helix_v2.dart`.

## Who may depend on this

Nothing but tests: `server/test/client/engine/cli_test.dart` drives it.

## What this may depend on

`helix_remote_engine`, `helix_remote_api`, `helix_remote_db`,
`helix_remote_crypto` and `helix_remote_protocol`. No Flutter, drift,
sqlite3 or HTTP imports of its own (`test/v2/architecture_test.dart`).

## Commands

`dart run helix_remote_cli:helix_v2 help` lists the commands:
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
- **Tests:** `test/v2/` (arguments, key handling, safe errors, no server) and
  `server/test/client/engine/cli_test.dart` (two homes exchange messages
  through the real server, a second CLI device is linked, a device is
  revoked).
