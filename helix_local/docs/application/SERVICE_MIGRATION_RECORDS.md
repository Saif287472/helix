# Service Migration Records

Status: Stage 5 foundation.

These records define the migration targets before code moves. Existing services
remain active until strangler adapters and consumers are migrated.

| Service | Responsibilities | Dependencies | Owned State | Public Consumers | Target Use Cases | Target Domain Interfaces | Target Infra Adapters | Migration Order | Required Tests | Deletion Criteria |
|---|---|---|---|---|---|---|---|---|---|---|
| `MessagingService` | Threads, message routing, receipts, file/media events, per-thread wipe | Domain, protocol, transport, trust | Threads, messages, wipe timers | Providers, chat UI, request/file/group services | `SendMessageUseCase`, `ReceiveMessageCoordinator`, `DeliveryReceiptTracker` | `ConversationRepository`, `MessageTransport`, `MessageCipher`, `MessageCodec` | `EphemeralConversationRepository`, `CborMessageGateway` | Extract repository facade, then send/receive use cases, then provider controller | Phase 0, provider refresh, request integration | UI/providers no longer depend on `MessagingService` |
| `RequestService` | Connection requests, handshakes, one-way messages | TCP sockets, secure channel, trust, domain | Pending requests, inbox | Providers, requests UI, reconnect | `ConnectionRequestUseCase`, `HandshakeCoordinator`, `PeerConnectionManager` | Connection state machine, `SecureSessionGateway` | `TlsSecureSessionGateway`, `TcpListenerManager` | Extract state machine, then handshake coordinator | Request integration | No direct socket logic in request use case |
| `GroupService` | Lobby/groups, election, admin commands, routing | Protocol, secure channels | Group records, bans, seen IDs | Providers, home UI, secure channel events | `CreateGroupUseCase`, `GroupMembershipManager`, `GroupMessageRouter` | `GroupRepository`, `GroupSignalingGateway` | `LocalGroupRepository`, `CborGroupSignalingGateway` | Extract election engine first | Phase 4 | Election/admin logic outside monolith |
| `FileTransferService` | Disk streaming, resume, hash, cancel | Protocol, transport, messaging | Transfer progress, partial files | Chat UI, providers | `SendFileUseCase`, `ReceiveFileCoordinator` | `TransferRepository`, `TransferStateMachine` | `StreamingTransferGateway` | Extract state machine and transfer repository | Phase 0, file manual checks | Transfer state not stored in messaging service |
| `EphemeralMediaService` | RAM-only private media chunks/cache | Protocol, messaging | RAM cache | Chat UI, providers | `SendEphemeralMediaUseCase` | `EphemeralMediaCache`, `MediaSanitizer` | Pure Dart image sanitizer | Extract cache first | Phase 0 media tests | Cache isolated from messaging |
| `ProfileService` | Profile, identity, secure storage | Secure storage, crypto, secret sentences | Profile and identity | Providers, setup/settings | `IdentityManager` | `ProfileRepository`, `SecureIdentityStore` | `FlutterSecureIdentityStore` | Extract identity store first | Profile/crypto tests | Private keys only in secure store adapter |
| `TrustService` | TOFU trust records | Secure storage, domain | Trusted peers | Messaging/request/UI | `TrustUseCase` | `TrustRepository` | `SecureTrustRepository` | Extract repository first | Trust/request tests | Trust state behind repository |
| `ReconnectService` | Retry and disconnect wipe scheduling | Discovery, request, session, messaging | Retry timers | Providers/session | `ReconnectionCoordinator`, `DisconnectWipeScheduler` | Connection state machine | Timer scheduler adapter | Extract wipe scheduler first | Auto-wipe tests | Timers outside messaging/request |
| `SessionService` | Active peer/session tracking | Domain, Android foreground | Session state | Providers | `ActiveSessionTracker` | `PeerConnectionManager` | Foreground service adapter | Fold into connection manager | Smoke/widget tests | No independent session singleton |
| `NotificationService` | Local notifications | Flutter notifications plugin | Plugin init state | Providers/messaging | Notification use cases | `NotificationGateway` | `PlatformNotificationGateway` | Define gateway then adapter | Smoke/manual checks | Plugin hidden behind gateway |
| `DiagnosticsService` | Network/app diagnostics | Core/domain | Bind errors | Diagnostics UI | `DiagnosticsCollector` | Diagnostics port | Local diagnostics collector | Move as-is under application | Smoke tests | UI reads collector interface |
| `QrCodeService` | Pairing payload encode/decode | CBOR/domain | None | QR UI | `QrCodeGenerator` | Pairing payload mapper | Pure Dart QR payload codec | Fold into pairing use cases | Smoke tests | QR UI uses pairing controller |
| `SecretCodeService` | Secret sentence lookup/broadcast/rate limit | Crypto, sockets, domain | Rate-limit attempts | Profile/discovery | `SecretSentenceLookup`, `RateLimiter` | Pairing repository/gateway | LAN secret lookup gateway | Extract rate limiter first | Profile/discovery tests | Socket code outside pairing use case |
| `TcpServerService` | TCP listener lifecycle | Sockets/request service | Listener state | Providers | `TcpListenerManager` | Transport listener port | TCP listener adapter | Move to transport after request split | Request integration | No request behavior in listener |

## Current Stage 5 Foundation

- Contracts added in `lib/application/contracts/`.
- Workflow state machines added in `lib/application/state_machines/`.
- Composition root placeholder added in `lib/app/composition_root.dart`.

Consumer migration is intentionally incremental and must keep `scripts/verify.ps1`
green after each slice.
