import 'package:helix_local_domain/core/product_descriptor.dart';
import 'package:helix_local_protocol/application/contracts/gateways.dart';
import 'package:helix_local_domain/application/contracts/repositories.dart';
import 'package:helix_local_calls/infrastructure/call/webrtc_call_engine.dart';
import 'package:helix_local_platform/infrastructure/platform/android_foreground_service_gateway.dart';
import 'package:helix_local_platform/infrastructure/platform/platform_diagnostics_gateway.dart';
import 'package:helix_local_platform/infrastructure/platform/platform_notification_gateway.dart';
import 'package:helix_local_storage/infrastructure/storage/in_memory_connection_request_repository.dart';
import 'package:helix_local_storage/infrastructure/storage/in_memory_conversation_repository.dart';
import 'package:helix_local_storage/infrastructure/storage/in_memory_ephemeral_media_cache.dart';
import 'package:helix_local_storage/infrastructure/storage/in_memory_group_repository.dart';
import 'package:helix_local_storage/infrastructure/storage/in_memory_transfer_repository.dart';
import 'package:helix_local_storage/infrastructure/storage/secure_session_repository.dart';
import 'package:helix_local_storage/infrastructure/storage/secure_trust_repository.dart';

/// Single wiring point where every concrete infrastructure implementation is
/// bound to its domain interface.  Riverpod providers expose these bindings
/// to the rest of the app; nothing outside this file instantiates concrete
/// infrastructure classes directly.
class AppCompositionRoot {
  AppCompositionRoot._({
    required this.conversationRepository,
    required this.connectionRequestRepository,
    required this.groupRepository,
    required this.transferRepository,
    required this.ephemeralMediaCache,
    required this.trustRepository,
    required this.sessionRepository,
    required this.foregroundServiceGateway,
    required this.notificationGateway,
    required this.diagnosticsGateway,
    required this.callEngine,
  });

  factory AppCompositionRoot.production(ProductDescriptor descriptor) => AppCompositionRoot._(
    conversationRepository: InMemoryConversationRepository(),
    connectionRequestRepository: InMemoryConnectionRequestRepository(),
    groupRepository: InMemoryGroupRepository(),
    transferRepository: InMemoryTransferRepository(),
    ephemeralMediaCache: InMemoryEphemeralMediaCache(),
    trustRepository: SecureTrustRepository(keyPrefix: descriptor.secureStoragePrefix),
    sessionRepository: SecureSessionRepository(keyPrefix: descriptor.secureStoragePrefix),
    foregroundServiceGateway: const AndroidForegroundServiceGateway(),
    notificationGateway: PlatformNotificationGateway(
      appName: descriptor.displayName,
      appUserModelId: descriptor.packageId,
      windowsNotificationGuid: descriptor.windowsNotificationGuid,
      channelPrefix: descriptor.logNamespace,
      methodChannelNamespace: descriptor.methodChannelNamespace,
    ),
    diagnosticsGateway: PlatformDiagnosticsGateway(),
    callEngine: WebRtcCallEngine(),
  );

  final ConversationRepository conversationRepository;
  final ConnectionRequestRepository connectionRequestRepository;
  final GroupRepository groupRepository;
  final TransferRepository transferRepository;
  final EphemeralMediaCache ephemeralMediaCache;
  final TrustRepository trustRepository;
  final SessionRepository sessionRepository;
  final ForegroundServiceGateway foregroundServiceGateway;
  final NotificationGateway notificationGateway;
  final DiagnosticsGateway diagnosticsGateway;
  final CallEngine callEngine;

  void dispose() {
    notificationGateway.dispose();
    callEngine.dispose().ignore();
  }
}
