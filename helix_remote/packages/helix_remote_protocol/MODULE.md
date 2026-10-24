# helix_remote_protocol

The Helix Remote v2 wire contract (ADR-028, `docs/protocol/v2/`). Pure Dart:
no Flutter, no `dart:io` in `lib/` (architecture test). Depends only on
`crypto` and `meta`.

## Contents

| File | What |
|---|---|
| `src/routes.dart` | Route catalog (`Routes.all`): method, path, module, access. Server and clients build from it. |
| `src/modules/*.dart` | REST DTOs per server module (identity, keys, messaging, people, groups, calls, media, backup, ops). |
| `src/envelope.dart` | Mailbox envelopes and server-generated event payloads. |
| `src/realtime.dart` | WebSocket frames and close codes. |
| `src/sealed.dart` | Encrypted payload forms (prekey, ratchet, sender-key messages). |
| `src/content/` | Everything inside the encryption: `ContentMessage`, bodies, media pointers, padding. |
| `src/errors.dart` | `ErrorCode`, `ApiError`, `StaleDevices`. |
| `src/json.dart` | `JsonReader` (strict, path-tracking decode, every read bounded, never echoes values), base64url bytes, epoch-ms times. |
| `src/ids.dart` | UUIDv7. |

## Rules

- Every DTO decodes through `JsonReader` and has a round-trip test.
- **Nothing decodes unbounded.** `string`, `bytes` and the list readers each
  take a limit and default it to the backstops in `src/json.dart`
  (`maxWireStringLength`, `maxWireBytes`, `maxWireListItems`), so a field
  nobody thought about is still capped. `ContentLimits` (and the DTO's own
  `maxBytes`/`maxBatch`-style constant) names the real size where the contract
  knows it; `bytesOf` fixes the length of a key or digest. A new field gets no
  extra work — it inherits the backstop; a new *large* field names its own
  limit at the call site, or the decode refuses what the sender sends.
- Wire changes are additive. A changed golden fixture
  (`contracts/v2/fixtures/`) is a reviewed decision, not an incidental diff.
- Every route in the catalog appears in `REST_V2.md` (`docs_test.dart`); the
  public-route list is snapshotted (`routes_test.dart`).
- `toString()` of anything carrying a secret redacts it.
