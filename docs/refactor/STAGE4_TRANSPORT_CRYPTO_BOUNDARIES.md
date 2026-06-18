# Stage 4 Transport, Crypto, and Protocol Boundaries

Status: complete
Date: 2026-06-15

Stage 4 separates the first transport and crypto seams from `SecureChannel`
while preserving current behavior.

## Transport Boundary

- Added `lib/services/transport/frame_io.dart`.
- Moved length-prefixed `encodeFrame`, `writeFrame`, and buffered frame reading
  out of protocol.
- Replaced `SecureChannel`'s private duplicate reader with
  `LengthPrefixedFrameReader`.
- Added `test/transport_frame_io_test.dart`.

## Crypto Boundary

- Added `lib/crypto/session_key_derivation.dart`.
- Moved identity proof payload construction, chain seed construction,
  directional chain-key derivation, ratcheting, and best-effort zeroing helpers.
- `SecureChannel` now delegates key setup and ratcheting to the crypto module.
- Added `test/session_key_derivation_test.dart`.
- Added `lib/crypto/AI_CONTEXT.md`.
- Tightened boundary rules for `lib/crypto/**`.

## Validation

Commands run:

```powershell
flutter test test\session_key_derivation_test.dart test\transport_frame_io_test.dart test\request_channel_integration_test.dart
flutter analyze
dart run tool\check_boundaries.dart
.\scripts\verify.ps1
```

Result:

- Analyzer: no issues found
- Boundary check: passed
- Secret scan: passed
- Full tests: 99 passed
- Canonical verification: passed

## Security Caveat

This stage preserves the existing key-derivation behavior and extracts it behind
a crypto boundary. It does not claim stronger forward secrecy. The current
design still needs the planned crypto security gate before any stronger claim is
made.
