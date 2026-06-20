// Infrastructure providers: composition root, repositories, gateways.
// These are the lowest-level providers; everything else depends on them.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_local_storage/data/database.dart';
import 'package:helix_local_storage/data/database_provider.dart';
import 'package:helix_local_domain/application/contracts/repositories.dart';
import 'package:helix_local_protocol/application/contracts/gateways.dart';
import 'package:helix_local_protocol/application/contracts/use_cases.dart' show DisconnectWipeScheduler;
import 'package:helix/providers/session_provider.dart';
import 'package:helix/app/composition_root.dart' show LocalCompositionRoot;

final compositionRootProvider = Provider<LocalCompositionRoot>((ref) {
  final descriptor = ref.watch(productDescriptorProvider);
  final root = LocalCompositionRoot.production(descriptor);
  // unawaited is intentional: Riverpod onDispose is synchronous; the Future
  // is started deterministically and the internal dispose() sequences correctly.
  ref.onDispose(() => unawaited(root.dispose()));
  return root;
});

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  return ref.watch(compositionRootProvider).conversationRepository;
});

final connectionRequestRepositoryProvider =
    Provider<ConnectionRequestRepository>((ref) {
      return ref.watch(compositionRootProvider).connectionRequestRepository;
    });

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return ref.watch(compositionRootProvider).groupRepository;
});

final transferRepositoryProvider = Provider<TransferRepository>((ref) {
  return ref.watch(compositionRootProvider).transferRepository;
});

final ephemeralMediaCacheProvider = Provider<EphemeralMediaCache>((ref) {
  return ref.watch(compositionRootProvider).ephemeralMediaCache;
});

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return ref.watch(compositionRootProvider).sessionRepository;
});

final foregroundServiceGatewayProvider = Provider<ForegroundServiceGateway>((
  ref,
) {
  return ref.watch(compositionRootProvider).foregroundServiceGateway;
});

final diagnosticsGatewayProvider = Provider<DiagnosticsGateway>((ref) {
  return ref.watch(compositionRootProvider).diagnosticsGateway;
});

final notificationGatewayProvider = Provider<NotificationGateway>((ref) {
  return ref.watch(compositionRootProvider).notificationGateway;
});

final disconnectWipeSchedulerProvider = Provider<DisconnectWipeScheduler>((
  ref,
) {
  return ref.watch(compositionRootProvider).wipeScheduler;
});

final databaseProvider = FutureProvider<HelixDatabase>((ref) async {
  ref.onDispose(DatabaseProvider.close);
  final descriptor = ref.watch(productDescriptorProvider);
  return DatabaseProvider.initialize(
    databaseFilename: descriptor.databaseFilename,
  );
});
