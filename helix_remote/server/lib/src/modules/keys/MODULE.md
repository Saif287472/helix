# keys module

The X3DH key directory (CRYPTO_V2.md §3). Schema `keys`. Facade:
`api.dart` (`KeysApi`).

## Routes

| Route | Rules |
|---|---|
| `PUT /v1/keys/signed-prekey` | Ed25519 signature by the device's DSK over `signedPrekeySignatureBody`. |
| `POST /v1/keys/one-time-prekeys` | At most 200 per call and 1,000 stored (`quota_exceeded`). Repeated ids are ignored, so retries are safe. |
| `GET /v1/keys/status` | Remaining one-time prekeys and the current signed prekey id. |
| `GET /v1/keys/{account}` | Bundles of the account's active devices; `?device=` repeatable. Each returned device gives up one one-time prekey (`FOR UPDATE SKIP LOCKED`, never handed out twice). Limits: 120/hour per requesting device, 600/hour per target account. |

## Behaviour

- **Prekeys arrive with the device.** Initial prekeys are stored by
  identity's `onDeviceAdded` hook, inside the transaction that adds the
  device. A bad signed-prekey signature rolls the whole sign-up back.
- **Revocation purges.** A revoked device's prekeys are removed
  (`onDeviceRevoked`), so it disappears from bundles at once.
- **Low prekeys are signalled.** When a device drops below 20 one-time
  prekeys, `onPrekeysLow` hooks run at most once an hour per device. The
  messaging module (S3) turns that into a `prekeys_low` envelope.
- **Federated accounts** (`id@domain`) are fetched from their home server
  through the federation module's `RemoteKeySource`. The same
  per-requester and per-target limits apply, keyed by the qualified
  address. The answer's `account` is qualified.

No foreign keys to identity (ADR-026): rows are keyed by device id and
purged through hooks.
