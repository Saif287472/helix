# Service Smoke Coverage

Status: Stage 0 baseline
Date: 2026-06-15

This matrix records the first-pass smoke coverage before structural refactoring.
It is not a claim of complete behavioral coverage; it identifies the current
safety net and the places that need seams before deeper tests are practical.

| Service/module | Current smoke/regression coverage | Notes |
|---|---|---|
| `QrCodeService` | `test/service_smoke_test.dart` | Encode/decode, malformed input, direct-IP peer stubs |
| `DiagnosticsService` | `test/service_smoke_test.dart` | Returns caller-supplied listener state and protocol version |
| `SessionService` | `test/service_smoke_test.dart` | Initial idle state only; start/resume/stop uses secure storage/platform paths |
| `PeerRegistry` | `test/discovery_test.dart` | Upsert, dedup, stale eviction, limit, streams |
| `MessagingService` | `test/phase0_test.dart`, `test/provider_refresh_test.dart`, integration tests | File routing, per-thread wipe, provider updates, one-way inbox |
| `FileTransferService` | `test/phase0_test.dart` | File ID consistency, probe/resume/cancel routing, resume offset behavior |
| `EphemeralMediaService` | `test/phase0_test.dart` | Assembly, malformed chunk rejection |
| `GroupService` | `test/phase4_test.dart` | Election, stale host rejection, duplicate IDs, group code, admin operations |
| `RequestService` | `test/request_channel_integration_test.dart` | Accepted request, duplicate pending replacement, one-way message |
| `SecureChannel` / protocol | `test/phase0_test.dart`, `test/phase4_test.dart`, `test/protocol_fixtures_test.dart` | Loopback channel behavior and protocol fixture decode corpus |
| `ProfileService` | `test/profile_validation_test.dart`, `test/crypto_test.dart` | Validation and crypto helpers; secure-storage flows need a storage port before deeper unit tests |
| `SecretCodeService` | `test/profile_validation_test.dart`, request integration indirectly | Broadcast socket flows need a gateway seam before deeper unit tests |
| `ReconnectService` | `test/phase0_test.dart` indirectly | Auto-wipe/reconnect timer behavior currently covered through `MessagingService`; reconnect attempts need gateway seams |
| `NotificationService` | Not directly unit-tested | Plugin-backed; should move behind a notification gateway before unit tests |
| `TrustService` | Not directly unit-tested | Secure-storage backed; should move behind a trust repository/secure-store port first |
| `TcpServerService` | Not directly unit-tested | Real TLS socket binding; should be covered after transport seams are introduced |
| `DiscoveryCoordinator`, `UdpDiscovery`, `MdnsDiscovery` | `test/discovery_test.dart` covers registry; direct socket/platform discovery needs manual/integration checks | Needs discovery gateway seams for unit tests |

## Stage 0 Decision

Stage 0 adds smoke tests only where they are stable without introducing broad
mocks or changing production behavior. Platform-plugin, secure-storage, and
real-socket services are documented here and deferred until Stage 4/5 seams make
them testable without real platform resources.
