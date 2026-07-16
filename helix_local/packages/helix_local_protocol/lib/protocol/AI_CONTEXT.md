# Protocol Context

## Responsibility

Protocol owns frame types, frame data classes, CBOR payload encoding/decoding,
capability constants, version helpers, and the future envelope type.

## Public Entry Points

- `protocol_messages.dart`
- `frame_type.dart`
- `frames/*`
- `codecs/*`
- `versioning/*`
- `envelope.dart`

## Dependencies

Protocol may depend on `dart:*`, `cbor`, and core constants. It must not import
services, transport sockets, UI, providers, data, or platform wrappers.

## Invariants

- Stage 3 preserves the legacy wire format byte-for-byte.
- `ProtocolFrame.decode` must decode all Stage 0 fixtures.
- Unknown required frame types fail closed with `ProtocolException`.
- Frame payloads remain bounded by `kMaxFrameBytes`.

## Required Tests

- `test/protocol_fixtures_test.dart`
- Protocol round-trip tests in `test/phase0_test.dart` and `test/phase4_test.dart`

## High-Risk Areas

Frame type constants, CBOR map keys, binary payload handling, and future envelope
dual-codec migration.
