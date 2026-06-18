/// Ordered, idempotent panic-wipe for the Helix Local product.
///
/// Steps are executed in a defined order. Each step is individually wrapped
/// in try/catch so a failure in one step does not prevent the remaining steps
/// from running. The final [WipeResult] exposes any per-step errors so the
/// caller can surface them to the user.
///
/// Design constraints (per ADR and P6-024 through P6-049):
///   - Never invokes a Remote API (P6-045)
///   - Never enumerates Remote directories or keys (P6-046)
///   - Idempotent: calling execute() on a non-idle instance returns the
///     current phase immediately (P6-043)
///   - Partial failures are visible via [WipeResult.errors] (P6-044)
///   - Secure-storage deletion is scoped to the Local key prefix (P6-039)
library;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:helix_local_protocol/application/contracts/gateways.dart';
import 'package:helix_local_protocol/application/contracts/use_cases.dart';
import 'package:helix_local_storage/data/database.dart';

import 'package:helix_local_discovery/helix_discovery.dart';

import 'package:helix/providers/controllers/group_service.dart';
import 'package:helix/providers/controllers/messaging_service.dart';
import 'package:helix/providers/controllers/profile_service.dart';
import 'package:helix/providers/controllers/reconnect_service.dart';
import 'package:helix/providers/controllers/session_service.dart';
import 'package:helix/providers/controllers/tcp_server_service.dart';
import 'package:helix/providers/controllers/file_transfer_service.dart';
import 'package:helix/providers/controllers/ephemeral_media_service.dart';
import 'package:helix_local_calls/services/call_service.dart';

/// Current lifecycle phase of a [LocalPanicWipeOrchestrator].
enum WipePhase { idle, inProgress, complete, partialFailure }

/// Result returned from [LocalPanicWipeOrchestrator.execute].
class WipeResult {
  const WipeResult({required this.phase, this.errors = const []});

  final WipePhase phase;

  /// Per-step error strings. Empty when [phase] is [WipePhase.complete].
  final List<String> errors;

  bool get succeeded => errors.isEmpty;
}

class LocalPanicWipeOrchestrator {
  LocalPanicWipeOrchestrator({
    required this.messaging,
    required this.discovery,
    required this.groupService,
    required this.wipeScheduler,
    required this.database,
    required this.reconnect,
    required this.tcpServer,
    required this.storagePrefix,
    required this.notifications,
    required this.session,
    required this.profile,
    required this.callService,
    required this.fileTransfer,
    required this.ephemeralMedia,
    this.onClearLogs,
    this.onClearAppPrivateFiles,
    this.onMarkWipePending,
    this.onClearWipePending,
  }) : _overrideSteps = null;

  /// For tests only — injects explicit step callbacks to exercise the state
  /// machine without requiring real service objects.
  @visibleForTesting
  LocalPanicWipeOrchestrator.withSteps(
    List<(String, Future<void> Function())> steps,
  ) : messaging = null,
      discovery = null,
      groupService = null,
      wipeScheduler = null,
      database = null,
      reconnect = null,
      tcpServer = null,
      storagePrefix = '',
      notifications = null,
      session = null,
      profile = null,
      callService = null,
      fileTransfer = null,
      ephemeralMedia = null,
      onClearLogs = null,
      onClearAppPrivateFiles = null,
      onMarkWipePending = null,
      onClearWipePending = null,
      _overrideSteps = steps;

  @visibleForTesting
  LocalPanicWipeOrchestrator.withStepsAndRecovery(
    List<(String, Future<void> Function())> steps, {
    this.onMarkWipePending,
    this.onClearWipePending,
  }) : messaging = null,
       discovery = null,
       groupService = null,
       wipeScheduler = null,
       database = null,
       reconnect = null,
       tcpServer = null,
       storagePrefix = '',
       notifications = null,
       session = null,
       profile = null,
       callService = null,
       fileTransfer = null,
       ephemeralMedia = null,
       onClearLogs = null,
       onClearAppPrivateFiles = null,
       _overrideSteps = steps;

  final MessagingService? messaging;
  final DiscoveryCoordinator? discovery;
  final GroupService? groupService;
  final DisconnectWipeScheduler? wipeScheduler;
  final HelixDatabase? database;
  final ReconnectService? reconnect;
  final TcpServerService? tcpServer;
  final String storagePrefix;
  final NotificationGateway? notifications;
  final SessionService? session;
  final ProfileService? profile;
  final CallService? callService;
  final FileTransferService? fileTransfer;
  final EphemeralMediaService? ephemeralMedia;

  /// Optional hook for clearing log files. Injected to keep the orchestrator
  /// testable without path_provider or AppLogger singleton dependencies.
  final Future<void> Function()? onClearLogs;
  final Future<void> Function()? onClearAppPrivateFiles;
  final Future<void> Function()? onMarkWipePending;
  final Future<void> Function()? onClearWipePending;

  final List<(String, Future<void> Function())>? _overrideSteps;

  WipePhase _phase = WipePhase.idle;

  /// Current lifecycle phase. Starts [WipePhase.idle]; transitions to
  /// [WipePhase.inProgress] during execute(), then to [WipePhase.complete]
  /// or [WipePhase.partialFailure] when finished.
  WipePhase get phase => _phase;

  /// Executes the ordered wipe sequence.
  ///
  /// If [phase] is not [WipePhase.idle] returns immediately with the current
  /// phase and no errors — idempotent (P6-043).
  Future<WipeResult> execute() async {
    if (_phase != WipePhase.idle) {
      return WipeResult(phase: _phase);
    }
    _phase = WipePhase.inProgress;

    final errors = <String>[];
    await _runStep('wipeRecovery.markPending', onMarkWipePending, errors);

    for (final (label, fn) in _overrideSteps ?? _productionSteps()) {
      await _runStep(label, fn, errors);
    }

    if (errors.isEmpty) {
      await _runStep('wipeRecovery.clearPending', onClearWipePending, errors);
    }

    _phase = errors.isEmpty ? WipePhase.complete : WipePhase.partialFailure;
    return WipeResult(phase: _phase, errors: List.unmodifiable(errors));
  }

  Future<void> _runStep(
    String label,
    Future<void> Function()? fn,
    List<String> errors,
  ) async {
    if (fn == null) return;
    try {
      await fn();
    } catch (e) {
      errors.add('$label: $e');
    }
  }

  List<(String, Future<void> Function())> _productionSteps() => [
    // 1. Block auto-reconnect (no new sessions start during wipe)
    ('reconnect.stop', () async => reconnect!.stop()),

    // 2. Stop discovery broadcast and peer scanning
    ('discovery.stop', () => discovery!.stop()),

    // 3. Stop the runtime session and clear the persisted session ID
    ('session.stop', () async => session!.stopSession()),

    // 4. Release local call media without sending a network signal
    (
      'callService.releaseLocalMediaForWipe',
      () => callService!.releaseLocalMediaForWipe(),
    ),

    // 5. Cancel all per-thread disconnect-wipe timers
    ('wipeScheduler.cancelAll', () async => wipeScheduler!.cancelAll()),

    // 6. Wipe messaging: close channels, clear RAM threads/messages
    ('messaging.wipeAll', () => messaging!.wipeAll()),

    // 7. Stop TCP server (reject new incoming connections)
    ('tcpServer.stop', () => tcpServer!.stop()),

    // 8. Clear in-memory group state and stop announcements
    ('groupService.dispose', () => groupService!.dispose()),

    // 9. Cancel transfers, delete .part files, and clear ephemeral media
    (
      'fileTransfer.cancelAllTransfers',
      () => fileTransfer!.cancelAllTransfers(),
    ),
    ('ephemeralMedia.clearAll', () async => ephemeralMedia!.clearAll()),

    // 10. Clear peers_cache rows then delete DB files (+ WAL + SHM)
    ('database.clearAll', () async => database!.clearAll()),
    ('database.deleteFiles', () async => database!.deleteFiles()),

    // 11. Delete app-private cache/temp files and logs
    ('clearAppPrivateFiles', () async => onClearAppPrivateFiles?.call()),
    ('clearLogs', () async => onClearLogs?.call()),

    // 12. Reset Local setup/profile state and delete scoped secure keys only
    ('profile.reset', () => profile!.reset()),
    (
      'secureStorage.deleteScoped',
      () async {
        const storage = FlutterSecureStorage();
        final all = await storage.readAll();
        await Future.wait(
          all.keys
              .where((k) => k.startsWith(storagePrefix))
              .map((k) => storage.delete(key: k)),
        );
      },
    ),

    // 13. Cancel Local notifications
    ('notifications.cancelAll', () => notifications!.cancelAll()),
  ];
}
