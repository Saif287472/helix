# Package: helix_remote_storage

Status: current. Package-level counterpart to the backend module docs, from
the [structural upgrade plan](../../../docs/architecture/EARNMINUTE_STRUCTURAL_UPGRADE_PLAN.md)
(item A4). States in prose what
[`module_boundaries.json`](../../../docs/architecture/module_boundaries.json)
enforces at build time via `tool/check_boundaries.dart` — the config is the
authority; this is the explanation that sits next to the code.

## Purpose

The client's on-device database: schema, migrations, and typed accessors
for messages, conversations, contacts, groups and sync state.

## Public surface

`lib/helix_remote_storage.dart`, which exports `src/database.dart`.

## Who may depend on this

`helix_remote_sync`, `helix_remote_calls`, `helix_remote_groups`, the CLI,
and the app.

## What this may depend on

`helix_remote_domain`, `path`, `meta`, and `sqlite3` via the workspace hook.

## Gotchas

- **This is the sqlcipher side of the sqlite3 split.** The root
  `pubspec.yaml` sets `sqlite3: source: sqlcipher` for on-device encrypted
  storage, while `backend/pubspec.yaml` overrides it to `source: system`
  (plain SQLite). Both are correct for their side — do not "fix" one to
  match the other. See `helix-remote-vps-handoff.md`.
- **Multi-row writes belong in a transaction.** The outbox/sync atomicity
  defects fixed during the Phase 9-11 closure were all of this shape.
