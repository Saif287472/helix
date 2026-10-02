import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote_db/helix_remote_db.dart';

/// Settings the app owns rather than the engine.
///
/// They are stored next to the engine's own typed settings, in the same
/// encrypted table, and never leave the device. The engine declares its keys
/// in `EngineSettings`; UI-only preferences belong here (plan §6.4).
abstract final class AppSettings {
  /// Ask for the device's fingerprint, face or PIN when the app comes back.
  static const appLockEnabled = Setting<bool>('app.lock_enabled', false);

  /// How long the app may stay in the background before it locks again.
  static const appLockRelockAfterSeconds = Setting<int>(
    'app.lock_relock_after_seconds',
    60,
  );

  /// Show message text in the notification shade. Off by default: the
  /// notification says something arrived, not what it said.
  static const notificationsPreview = Setting<bool>(
    'app.notifications_preview',
    false,
  );
}

/// What the lock needs, read live from the engine's settings.
///
/// The lock screen sits above the navigator and so cannot be handed the
/// runtime; a [StreamProvider] is how it learns the setting without that.
final appLockSettingProvider = StreamProvider<AppLockSetting>((ref) async* {
  final settings = (await ref.watch(runtimeProvider.future)).engine.settings;
  yield* _latestPair(
    settings.watch(AppSettings.appLockEnabled),
    settings.watch(AppSettings.appLockRelockAfterSeconds),
  );
});

/// Emits whenever either stream emits, carrying the most recent value of
/// both.
///
/// Drift's watch queries only fire on a change to the row they name, so each
/// of these fires on its own key. The lock needs the pair together, so it is
/// combined here rather than watched twice at the call site.
Stream<AppLockSetting> _latestPair(Stream<bool> enabled, Stream<int> after) {
  late StreamController<AppLockSetting> controller;
  StreamSubscription<bool>? enabledSub;
  StreamSubscription<int>? afterSub;
  var latestEnabled = AppSettings.appLockEnabled.defaultValue;
  var latestAfter = AppSettings.appLockRelockAfterSeconds.defaultValue;

  controller = StreamController<AppLockSetting>(
    onListen: () {
      void publish() {
        if (!controller.isClosed) {
          controller.add(
            AppLockSetting(
              enabled: latestEnabled,
              relockAfterSeconds: latestAfter,
            ),
          );
        }
      }

      enabledSub = enabled.listen((value) {
        latestEnabled = value;
        publish();
      });
      afterSub = after.listen((value) {
        latestAfter = value;
        publish();
      });
    },
    onCancel: () async {
      await enabledSub?.cancel();
      await afterSub?.cancel();
      enabledSub = null;
      afterSub = null;
    },
  );
  return controller.stream;
}

/// Whether the lock is wanted, and after how long.
final class AppLockSetting {
  const AppLockSetting({
    required this.enabled,
    required this.relockAfterSeconds,
  });

  final bool enabled;
  final int relockAfterSeconds;
}
