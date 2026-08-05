# Package: helix_remote_api

Status: current. Package-level counterpart to the backend module docs, from
the [structural upgrade plan](../../../docs/architecture/EARNMINUTE_STRUCTURAL_UPGRADE_PLAN.md)
(item A4). States in prose what
[`module_boundaries.json`](../../../docs/architecture/module_boundaries.json)
enforces at build time via `tool/check_boundaries.dart` — the config is the
authority; this is the explanation that sits next to the code.

## Purpose

The typed HTTP/WebSocket client for the Remote backend. Turns the REST
surface documented in the backend's module docs into Dart calls, and owns
request/response serialization.

## Public surface

`lib/api.dart`.

## Who may depend on this

The app, the CLI, and `helix_remote_sync`. Not `helix_remote_domain` —
the domain ring must never reach outward to a client.

## What this may depend on

`helix_remote_domain` and `meta`. Forbidden from importing Local-classified
packages or app code.

## Gotchas

- **Error responses now carry a machine-readable `code`.** Since the A1
  migration every backend error body is `{error, code, details?}` with the
  `code` drawn from `RemoteErrorCode`. Branch on `code`, not on the message
  text — messages are wording, codes are contract.
- **`code` and HTTP status are independent.** A `conflict` code can arrive
  on a 403; don't infer one from the other.
- **Pure Dart, no Flutter.** Keep it that way so the CLI can use it.
