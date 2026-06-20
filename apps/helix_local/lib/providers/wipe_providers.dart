// Wipe providers: panic wipe orchestrator, app state, wipe recovery helpers.
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix_local_domain/core/product_descriptor.dart';
import 'package:helix/providers/session_provider.dart';
import 'package:helix/providers/infrastructure_providers.dart';
import 'package:helix/providers/connection_providers.dart'
    show
        reconnectServiceProvider,
        tcpServerServiceProvider,
        sessionServiceProvider;
import 'package:helix/providers/messaging_providers.dart'
    show messagingServiceProvider;
import 'package:helix/providers/discovery_providers.dart'
    show discoveryCoordinatorProvider;
import 'package:helix/providers/groups_providers.dart' show groupServiceProvider;
import 'package:helix/providers/calls_providers.dart' show callServiceProvider;
import 'package:helix/providers/transfer_providers.dart'
    show fileTransferServiceProvider, ephemeralMediaServiceProvider;
import 'package:helix/application/wipe/local_panic_wipe_orchestrator.dart';
import 'package:helix/services/app_logger.dart';

final appStateProvider = StateProvider<AppState>((ref) {
  final profileSvc = ref.watch(profileServiceProvider);
  if (profileSvc.isFirstRun) return AppState.firstRun;
  final session = ref.watch(sessionStateProvider);
  switch (session.phase) {
    case SessionPhase.active:
      return AppState.sessionActive;
    case SessionPhase.starting:
    case SessionPhase.stopping:
      return AppState.sessionActive;
    case SessionPhase.idle:
      return AppState.setupComplete;
  }
});

Future<void> _deleteDirectoryContents(Directory dir) async {
  if (!await dir.exists()) return;
  await for (final entity in dir.list(followLinks: false)) {
    try {
      await entity.delete(recursive: true);
    } catch (e) {
      unawaited(
        AppLogger.instance.warn(
          'wipe_cleanup',
          'directory entry delete failed: ${e.runtimeType}',
        ),
      );
    }
  }
}

Future<void> _clearLocalAppPrivateFiles(ProductDescriptor descriptor) async {
  final cacheDir = await getApplicationCacheDirectory();
  if (isPathInScopeForDestructiveOperation(
    cacheDir.absolute.path,
    descriptor,
  )) {
    await _deleteDirectoryContents(cacheDir);
  }

  final tempDir = await getTemporaryDirectory();
  if (isPathInScopeForDestructiveOperation(tempDir.absolute.path, descriptor)) {
    await _deleteDirectoryContents(tempDir);
    return;
  }

  await for (final entity in tempDir.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    final isHelixTemp =
        (name.startsWith('helix_') && name.endsWith('_export.whis')) ||
        (name.startsWith('wa_') && name.endsWith('.tmp')) ||
        name == '${descriptor.exportPrefix}.txt';
    if (!isHelixTemp) continue;
    try {
      await entity.delete();
    } catch (e) {
      unawaited(
        AppLogger.instance.warn(
          'wipe_cleanup',
          'temp file delete failed: ${e.runtimeType}',
        ),
      );
    }
  }
}

Future<void> _clearHelixMediaDirectory() async {
  Directory? base;
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    base = await getDownloadsDirectory();
  }
  base ??= await getExternalStorageDirectory();
  base ??= await getApplicationDocumentsDirectory();

  final mediaDir = Directory(p.join(base.path, 'Helix', 'Media'));
  await _deleteDirectoryContents(mediaDir);
}

Future<File> _panicWipeRecoveryMarker(ProductDescriptor descriptor) async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return File(
    p.join(dir.path, '${descriptor.logNamespace}_panic_wipe.pending'),
  );
}

Future<void> _markPanicWipePending(ProductDescriptor descriptor) async {
  final marker = await _panicWipeRecoveryMarker(descriptor);
  await marker.writeAsString('pending');
}

Future<void> _clearPanicWipePending(ProductDescriptor descriptor) async {
  final marker = await _panicWipeRecoveryMarker(descriptor);
  if (await marker.exists()) await marker.delete();
}

Future<bool> _hasPanicWipePending(ProductDescriptor descriptor) async {
  final marker = await _panicWipeRecoveryMarker(descriptor);
  return marker.exists();
}

final panicWipeOrchestratorProvider =
    FutureProvider<LocalPanicWipeOrchestrator>((ref) async {
      final db = await ref.watch(databaseProvider.future);
      final descriptor = ref.watch(productDescriptorProvider);
      return LocalPanicWipeOrchestrator(
        messaging: ref.watch(messagingServiceProvider),
        discovery: ref.watch(discoveryCoordinatorProvider),
        groupService: ref.watch(groupServiceProvider),
        wipeScheduler: ref.watch(disconnectWipeSchedulerProvider),
        database: db,
        reconnect: ref.watch(reconnectServiceProvider),
        tcpServer: ref.watch(tcpServerServiceProvider),
        storagePrefix: descriptor.secureStoragePrefix,
        notifications: ref.watch(notificationGatewayProvider),
        session: ref.watch(sessionServiceProvider),
        profile: ref.watch(profileServiceProvider),
        callService: ref.watch(callServiceProvider),
        fileTransfer: ref.watch(fileTransferServiceProvider),
        ephemeralMedia: ref.watch(ephemeralMediaServiceProvider),
        onClearLogs: AppLogger.instance.clearLogs,
        onClearAppPrivateFiles: () => _clearLocalAppPrivateFiles(descriptor),
        onClearReceivedFiles: _clearHelixMediaDirectory,
        onMarkWipePending: () => _markPanicWipePending(descriptor),
        onClearWipePending: () => _clearPanicWipePending(descriptor),
      );
    });

final localAppInitProvider = FutureProvider<void>((ref) async {
  final descriptor = ref.watch(productDescriptorProvider);
  if (await _hasPanicWipePending(descriptor)) {
    final orchestrator = await ref.watch(panicWipeOrchestratorProvider.future);
    final result = await orchestrator.execute();
    if (!result.succeeded) {
      throw StateError(
        'Panic wipe recovery failed: ${result.errors.join('; ')}',
      );
    }
  }
  await ref.watch(appInitProvider.future);
});
