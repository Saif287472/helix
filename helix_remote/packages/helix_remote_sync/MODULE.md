# Package: helix_remote_sync

Status: current. Package-level counterpart to the backend module docs, from
the [structural upgrade plan](../../../docs/architecture/EARNMINUTE_STRUCTURAL_UPGRADE_PLAN.md)
(item A4). States in prose what
[`module_boundaries.json`](../../../docs/architecture/module_boundaries.json)
enforces at build time via `tool/check_boundaries.dart` — the config is the
authority; this is the explanation that sits next to the code.

## Purpose

Reconciling local state with the server: the outbox that carries pending
local changes upward, and the sync engine that folds server changes back
down.

## Public surface

`lib/helix_remote_sync.dart`, which exports `src/sync_engine.dart`.

## Who may depend on this

The app and the CLI.

## What this may depend on

`helix_remote_domain`, `helix_remote_storage`, `helix_remote_api`. This is
the package that legitimately sits across storage and transport, which is
exactly why nothing lower is allowed to import it.

## Gotchas

- **The client outbox and the backend's `outbox` table are different
  things.** This one carries local changes up; the server's carries
  server-side deliveries out. `RemoteOutboxStatus` in the domain package
  describes the server's.
- **An enqueue and the write it describes must be in one transaction**, or a
  crash between them either loses the change or replays it.
- **Delivery is at-least-once, so handlers must be idempotent.** Message
  sends are keyed on `message_id` server-side for this reason.
