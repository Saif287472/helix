# Module: prekeys

Status: current. Follows the template in `messaging.module.md`.

## Purpose

The X3DH key-agreement surface: a device publishes its signed prekey and a
batch of one-time prekeys, and any account that wants to start a session
fetches a bundle for every one of the target's active devices.

## Owned files

- `prekeys.dart` - `PrekeysModule` and its router. ~175 lines; no split
  needed.

## Route table

Mounted at `/api/v1/prekeys`. Both routes require a session.

| Method | Path | Handler | Notes |
|---|---|---|---|
| POST | `/publish` | `_publishHandler` | Publishes this device's signed prekey plus one-time prekeys. |
| GET | `/bundle` | `_bundleHandler` | `?account_id=`. One bundle per active device. Transparently proxies to the account's home server when the id is external. |

## Error codes this module throws

The [`AppError`](../app_error.dart) shape: `.badRequest` for missing fields
or a missing `account_id`, `.notFound` when the target account has no active
devices, `.forbidden` for a missing session, and `.serviceUnavailable` when
`account_id` is external but federation is not configured.

## Dependencies

- `BackendDatabase` (`../database.dart`).
- `FederationClient?` (`../federation.dart`) - optional; required only for
  external account ids.

## Gotchas

- **`/bundle` is where the client-transparent federation split happens.**
  The caller passes `user@domain` and does not need to know whether that is
  local; `_isExternal` decides, and an external id becomes a proxied
  `GET /api/v1/s2s/prekeys/bundle` against the home server.
- **A bundle is returned per *device*, not per account.** Sending to an
  account means encrypting separately for every device in the response,
  which is what makes multi-device E2EE work.
- **Both paths write an audit row**, with different actions
  (`PREKEY_BUNDLE_REQUEST` vs `FEDERATED_PREKEY_BUNDLE_REQUEST`) so
  federated fetches are distinguishable after the fact.
- **One-time prekeys are consumed on fetch.** A target whose one-time keys
  are exhausted still yields a usable bundle from the signed prekey alone,
  with the weaker forward-secrecy that implies - the client is not told.
