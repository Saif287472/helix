# Transport Context

## Responsibility

Transport owns secure TCP/TLS session establishment, frame I/O, connection
state, keepalive behavior, and delivery of decoded transport events to
application controllers.

## Public Entry Points

- `secure_channel.dart`
- `frame_io.dart`
- `protocol_messages.dart`

## Dependencies

Transport may depend on protocol, crypto, domain constants, and `dart:io`.
It must not import UI, providers, Riverpod, SQLite adapters, or platform
channels.

## Invariants

- Never log keys, message contents, proofs, tokens, private media bytes, or full
  fingerprints.
- Plain request sockets may only carry request negotiation before the secure
  channel is established.
- Framed I/O must enforce maximum frame sizes.
- Session establishment must preserve trust and replay checks.

## Required Tests

- `test/request_channel_integration_test.dart`
- `test/phase0_test.dart`
- `test/phase4_test.dart`

## High-Risk Areas

TLS socket lifecycle, request-to-secure-channel handoff, frame length parsing,
file/media chunk routing, keepalive timeout handling, and key erasure limits in
the Dart runtime.
