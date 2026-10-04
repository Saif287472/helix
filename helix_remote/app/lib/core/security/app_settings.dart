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

  // ---- Settings pages (Phase A3b). Every key lives in the encrypted settings
  // table and never leaves the device.

  /// Text size inside the app, as a percentage of the system size. Applied at
  /// the root (`AppTextScale`), so it composes with the phone's own setting
  /// rather than replacing it.
  static const fontScalePercent = Setting<int>('app.font_scale_percent', 100);

  /// The Enter key sends a message (hardware keyboards, Windows). Read by the
  /// composer.
  static const enterToSend = Setting<bool>('app.enter_to_send', false);

  /// Alerts per kind. Off still records the message; it only stays quiet.
  static const notifyMessages = Setting<bool>('app.notify.messages', true);
  static const notifyGroups = Setting<bool>('app.notify.groups', true);
  static const notifyCalls = Setting<bool>('app.notify.calls', true);
  static const notifySound = Setting<bool>('app.notify.sound', true);
  static const notifyVibrate = Setting<bool>('app.notify.vibrate', true);

  /// When incoming media downloads by itself, per kind. The engine's own
  /// settings are size limits that do not know Wi-Fi from mobile data, so
  /// these are what the person chose and `MediaPolicySync` turns them into
  /// limits as the network changes.
  static const mediaImages = Setting<MediaDownloadPolicy>.enumeration(
    'app.media.images',
    MediaDownloadPolicy.values,
    MediaDownloadPolicy.always,
  );
  static const mediaAudio = Setting<MediaDownloadPolicy>.enumeration(
    'app.media.audio',
    MediaDownloadPolicy.values,
    MediaDownloadPolicy.always,
  );
  static const mediaVideo = Setting<MediaDownloadPolicy>.enumeration(
    'app.media.video',
    MediaDownloadPolicy.values,
    MediaDownloadPolicy.never,
  );
  static const mediaDocuments = Setting<MediaDownloadPolicy>.enumeration(
    'app.media.documents',
    MediaDownloadPolicy.values,
    MediaDownloadPolicy.never,
  );

  /// Whether the history backup may upload over mobile data.
  static const backupOverMobile = Setting<bool>(
    'app.backup_over_mobile',
    false,
  );

  /// Send an anonymous crash report when the app fails. Off until the person
  /// turns it on, and only ever offered while the server allows it.
  static const crashReportsOptIn = Setting<bool>(
    'app.crash_reports_opt_in',
    false,
  );

  /// The "about" line of this account's profile. The engine publishes it,
  /// encrypted, but does not keep a readable copy locally.
  static const profileAbout = Setting<String>('app.profile_about', '');
}

/// When incoming media of one kind is fetched without being asked.
enum MediaDownloadPolicy {
  /// Only when the person taps it.
  never,

  /// On Wi-Fi (or any unmetered network), not on mobile data.
  wifi,

  /// On any network.
  always,
}

/// The in-app text size as a percentage, live.
final fontScalePercentProvider = StreamProvider<int>((ref) async* {
  final settings = (await ref.watch(runtimeProvider.future)).engine.settings;
  yield* settings.watch(AppSettings.fontScalePercent);
});

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
