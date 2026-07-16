# Stage 3 Protocol Split

Status: complete
Date: 2026-06-15

Stage 3 moves protocol frame definitions and codec helpers out of transport
without changing the legacy CBOR wire format.

## Code Changes

- Moved protocol implementation to `lib/protocol/protocol_messages.dart`.
- Added compatibility export at
  `lib/services/transport/protocol_messages.dart`.
- Updated app, test, and tool imports to
  `package:helix/protocol/protocol_messages.dart`.
- Added protocol barrels for frames, codecs, frame types, versioning, and future
  envelope migration.
- Added `lib/protocol/AI_CONTEXT.md`.
- Tightened boundary rules for `lib/protocol/**`.

## Documentation

- `docs/protocol/COMPATIBILITY_MATRIX.md`
- `docs/protocol/ROLLBACK.md`

## Validation

Commands run:

```powershell
flutter test test\protocol_fixtures_test.dart test\phase0_test.dart test\phase4_test.dart
dart run tool\generate_protocol_fixtures.dart
flutter test test\protocol_fixtures_test.dart
.\scripts\verify.ps1
```

Result:

- Protocol fixture decode: passed
- Phase 0/Phase 4 protocol regression tests: passed
- Analyzer: no issues found
- Boundary check: passed
- Secret scan: passed
- Full tests: 93 passed
- Canonical verification: passed

## Compatibility Notes

The wire format remains `legacy-cbor-map-v1` at protocol `2.2`. The
`ProtocolEnvelope` type is present as a target shape only; it is not used on the
wire until a later dual-codec capability-gated migration.
