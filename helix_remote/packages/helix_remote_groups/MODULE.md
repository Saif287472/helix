# Package: helix_remote_groups

Status: current. Package-level counterpart to the backend module docs, from
the [structural upgrade plan](../../../docs/architecture/EARNMINUTE_STRUCTURAL_UPGRADE_PLAN.md)
(item A4). States in prose what
[`module_boundaries.json`](../../../docs/architecture/module_boundaries.json)
enforces at build time via `tool/check_boundaries.dart` — the config is the
authority; this is the explanation that sits next to the code.

## Purpose

The client half of groups: local group state, membership bookkeeping, and
the Sender Key epoch handling that pairs with the backend's
`groups/epoch_keys.dart`.

## Public surface

`lib/helix_remote_groups.dart`, which exports `src/group_service.dart`.

## Who may depend on this

The app only.

## What this may depend on

`helix_remote_domain`, `helix_remote_storage`, `crypto`, Flutter.

## Gotchas

- **This package depends on `flutter_test` and so cannot build in the
  Dart-only backend container.** That is why the backend Dockerfile copies
  only `backend/` and `helix_remote_domain/` and strips
  `resolution: workspace` from both — a workspace-wide `dart pub get` fails
  on this package. Documented in `helix-remote-vps-handoff.md`; don't
  "fix" it by adding the package to the image.
- **Epoch key rotation must reach every member device, including federated
  ones.** The server fans out; this side has to tolerate arriving out of
  order.
- `CURRENT_STATE_2026-06-20.md` classifies Remote groups as Defective over
  deterministic fallback key behaviour. Treat key-selection changes as
  high-risk.
