# Stage 0 Baseline

Status: complete
Date: 2026-06-15
Protocol baseline: 2.2

This file records the known-good baseline before structural refactoring begins.
It is intentionally factual and should be updated only when the baseline is
intentionally advanced.

## Verification Baseline

Commands run:

```powershell
flutter analyze
flutter test --coverage
```

Result:

- Analyzer: no issues found
- Tests: 86 passed
- Skipped/flaky tests observed: none
- Coverage file: `coverage/lcov.info`
- Coverage summary: 1710 / 9102 instrumented lines hit, 18.79%

Reference verification command sequence for this baseline:

```powershell
dart format --set-exit-if-changed .
flutter analyze
flutter test --coverage
```

Stage 1 will replace this with `scripts/verify.ps1` and `scripts/verify.sh`.

Additional targeted checks run while completing Stage 0:

```powershell
flutter test test\protocol_fixtures_test.dart
flutter test test\service_smoke_test.dart
flutter test
```

## Source Inventory

Largest files and refactor pressure points:

| File | Bytes | Primary responsibility |
|---|---:|---|
| `lib/ui/screens/chat/chat_screen.dart` | 112763 | Chat presentation, composer, trust UI, files/media UI |
| `lib/ui/screens/home/home_screen.dart` | 76785 | Home presentation, session bootstrap hooks, discovery UI, group entry UI |
| `lib/services/transport/secure_channel.dart` | 41971 | TLS channel, identity exchange, capability negotiation, frame read/write, keepalive |
| `lib/services/transport/protocol_messages.dart` | 35860 | CBOR protocol frame definitions and wire helpers |
| `lib/services/messaging_service.dart` | 35121 | Thread state, message routing, transfer/event routing, auto-wipe |
| `lib/services/request_service.dart` | 32233 | Connection requests, TCP handshake, one-way messages, resume accept |
| `lib/ui/screens/settings/settings_screen.dart` | 42316 | Settings presentation |
| `lib/ui/screens/requests/requests_screen.dart` | 29447 | Requests and one-way inbox presentation |
| `lib/ui/screens/setup/setup_screen.dart` | 23696 | Setup/onboarding presentation |
| `lib/providers/app_providers.dart` | 22764 | Riverpod composition and cross-service bridges |
| `lib/services/group_service.dart` | 21581 | Group state, election, admin commands, forwarding decisions |
| `lib/data/database.dart` | 19243 | SQLite schema and persistence |
| `lib/services/profile_service.dart` | 16987 | Profile, identity generation, secure storage |
| `lib/services/file_transfer_service.dart` | 15076 | Disk streaming transfer lifecycle |

Other service files:

| File | Bytes |
|---|---:|
| `lib/services/discovery/discovery_coordinator.dart` | 12078 |
| `lib/services/secret_code_service.dart` | 12039 |
| `lib/services/discovery/udp_discovery.dart` | 11743 |
| `lib/services/notification_service.dart` | 8210 |
| `lib/services/ephemeral_media_service.dart` | 7629 |
| `lib/services/reconnect_service.dart` | 6684 |
| `lib/services/discovery/mdns_discovery.dart` | 6187 |
| `lib/services/diagnostics_service.dart` | 5724 |
| `lib/services/trust_service.dart` | 4982 |
| `lib/services/session_service.dart` | 4644 |
| `lib/services/discovery/peer_registry.dart` | 3808 |
| `lib/services/tcp_server_service.dart` | 2236 |

## Dependency Observations

- `protocol_messages.dart` can be imported by a pure Dart tool.
- `GroupService` currently imports `SecureChannel`, which imports domain models
  that depend on Flutter foundation. This made the first fixture generator
  attempt fail outside Flutter. This confirms the roadmap's concern that
  application services are coupled to transport and Flutter-adjacent types.
- `SecureChannel` owns transport, protocol dispatch, identity verification,
  capability negotiation, keepalive, and ratchet state. It is the main critical
  extraction target after protocol fixtures are locked.
- `app_providers.dart` performs cross-service bridge wiring. Stage 1 boundary
  rules should initially allow this but prevent deeper UI/provider access to
  protocol internals over time.
- `domain/models.dart` is a shared model bucket and imports Flutter foundation.
  It should not be treated as pure domain during later clean-architecture moves.

## Protocol Fixture Baseline

Fixtures are stored in:

```text
test/fixtures/protocol/v2.2/frames.json
```

The fixture corpus covers 28 current legacy CBOR payload frame types:

- request, accept, reject, cancel
- identity, identity_ack, capability
- chat_message, chat_ack, keepalive, close, profile_update, busy,
  version_mismatch
- typing_indicator, read_receipt, reaction
- file_transfer, edit_message, delete_message, wipe
- file_probe, file_resume, file_complete, file_cancel
- ephemeral_media
- group_control, group_message

Regression test:

```text
test/protocol_fixtures_test.dart
```

Regeneration command:

```powershell
dart run tool\generate_protocol_fixtures.dart
```

Regenerate only when intentionally advancing the protocol fixture baseline.

## Service Smoke Coverage

Service smoke coverage is documented in:

```text
docs/refactor/SERVICE_SMOKE_COVERAGE.md
```

Stage 0 intentionally adds stable smoke tests for pure or low-platform services
and documents plugin, secure-storage, and real-socket services that need seams
before deeper unit coverage is practical.

## Stage 0 Closure

- Repository audit recorded.
- Clean analyzer, test, and coverage baselines recorded.
- Protocol fixture corpus and decode regression test added.
- Service smoke test coverage matrix added.
- Fixture regeneration remains manual unless Stage 1 CI policy chooses to make
  fixture drift a blocking check.
