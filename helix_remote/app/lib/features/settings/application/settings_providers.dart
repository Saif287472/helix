import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/local_settings.dart';
import 'package:helix_remote/core/notifications/notification_permission.dart';
import 'package:helix_remote/core/platform/profile_image_source.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote/core/security/device_auth.dart';
import 'package:helix_remote/features/settings/application/settings_gateway.dart';
import 'package:helix_remote/features/settings/application/settings_models.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show EngineSettings;

/// Re-exported so the pages can name the choice without importing `core/`.
export 'package:helix_remote/core/security/app_settings.dart'
    show MediaDownloadPolicy;

// ------------------------------------------------------------ the header

/// Who this device is signed in as, for the top of the Settings tab.
final settingsHeaderProvider = StreamProvider<SettingsHeader>(
  (ref) => ref.watch(settingsGatewayProvider).watchHeader(),
);

/// The picture chosen on this phone, if any.
final settingsAvatarProvider = Provider<Uint8List?>(
  (ref) => ref.watch(profileAvatarProvider).value,
);

// --------------------------------------------------------- live settings

final readReceiptsProvider = settingProvider(EngineSettings.sendReadReceipts);
final typingIndicatorsProvider = settingProvider(EngineSettings.sendTyping);
final defaultDisappearingProvider = settingProvider(
  EngineSettings.defaultDisappearingSeconds,
);

final notifyMessagesProvider = settingProvider(AppSettings.notifyMessages);
final notifyGroupsProvider = settingProvider(AppSettings.notifyGroups);
final notifyCallsProvider = settingProvider(AppSettings.notifyCalls);
final notifySoundProvider = settingProvider(AppSettings.notifySound);
final notifyVibrateProvider = settingProvider(AppSettings.notifyVibrate);
final notificationPreviewsProvider = settingProvider(
  AppSettings.notificationsPreview,
);

final fontScaleSettingProvider = settingProvider(AppSettings.fontScalePercent);
final enterToSendProvider = settingProvider(AppSettings.enterToSend);

final mediaImagesProvider = settingProvider(AppSettings.mediaImages);
final mediaAudioProvider = settingProvider(AppSettings.mediaAudio);
final mediaVideoProvider = settingProvider(AppSettings.mediaVideo);
final mediaDocumentsProvider = settingProvider(AppSettings.mediaDocuments);

final crashReportsOptInProvider = settingProvider(
  AppSettings.crashReportsOptIn,
);

/// The kinds of incoming media whose download policy the person sets.
enum MediaKindChoice { images, audio, video, documents }

/// Disappearing-message timer choices for new chats, in seconds (null = off).
const disappearingChoices = <int?>[null, 86400, 604800, 7776000];

String disappearingLabel(int? seconds) => switch (seconds) {
  null => 'Off',
  86400 => '24 hours',
  604800 => '7 days',
  7776000 => '90 days',
  final s => '${(s / 86400).round()} days',
};

/// In-app text size choices, as a percentage of the system size.
const fontScaleChoices = <int>[90, 100, 115, 130];

String fontScaleLabel(int percent) => switch (percent) {
  90 => 'Small',
  100 => 'Default',
  115 => 'Large',
  130 => 'Extra large',
  final p => '$p%',
};

/// The typed setters behind the switches and pickers.
final settingsActionsProvider = Provider<SettingsActions>(SettingsActions.new);

final class SettingsActions {
  SettingsActions(this._ref);

  final Ref _ref;

  LocalSettings get _store => _ref.read(localSettingsProvider);

  Future<void> setReadReceipts(bool on) =>
      _store.set(EngineSettings.sendReadReceipts, on);

  Future<void> setTypingIndicators(bool on) =>
      _store.set(EngineSettings.sendTyping, on);

  Future<void> setDefaultDisappearing(int? seconds) =>
      _store.set(EngineSettings.defaultDisappearingSeconds, seconds);

  Future<void> setNotifyMessages(bool on) =>
      _store.set(AppSettings.notifyMessages, on);

  Future<void> setNotifyGroups(bool on) =>
      _store.set(AppSettings.notifyGroups, on);

  Future<void> setNotifyCalls(bool on) =>
      _store.set(AppSettings.notifyCalls, on);

  Future<void> setNotifySound(bool on) =>
      _store.set(AppSettings.notifySound, on);

  Future<void> setNotifyVibrate(bool on) =>
      _store.set(AppSettings.notifyVibrate, on);

  Future<void> setNotificationPreviews(bool on) =>
      _store.set(AppSettings.notificationsPreview, on);

  Future<void> setFontScale(int percent) =>
      _store.set(AppSettings.fontScalePercent, percent);

  Future<void> setEnterToSend(bool on) =>
      _store.set(AppSettings.enterToSend, on);

  Future<void> setMediaPolicy(MediaKindChoice kind, MediaDownloadPolicy p) =>
      switch (kind) {
        MediaKindChoice.images => _store.set(AppSettings.mediaImages, p),
        MediaKindChoice.audio => _store.set(AppSettings.mediaAudio, p),
        MediaKindChoice.video => _store.set(AppSettings.mediaVideo, p),
        MediaKindChoice.documents => _store.set(AppSettings.mediaDocuments, p),
      };

  Future<void> setCrashReportsOptIn(bool on) =>
      _store.set(AppSettings.crashReportsOptIn, on);
}

// -------------------------------------------------------------- app lock

String relockLabel(int seconds) => switch (seconds) {
  0 => 'Immediately',
  60 => 'After 1 minute',
  300 => 'After 5 minutes',
  1800 => 'After 30 minutes',
  final s => 'After ${(s / 60).round()} minutes',
};

const relockChoices = <int>[0, 60, 300, 1800];

class AppLockView {
  const AppLockView({this.enabled = false, this.relockAfterSeconds = 60});

  final bool enabled;
  final int relockAfterSeconds;
}

final appLockViewProvider = Provider<AsyncValue<AppLockView>>(
  (ref) => ref
      .watch(appLockSettingProvider)
      .whenData(
        (s) => AppLockView(
          enabled: s.enabled,
          relockAfterSeconds: s.relockAfterSeconds,
        ),
      ),
);

final appLockActionsProvider = Provider<AppLockActions>(AppLockActions.new);

final class AppLockActions {
  AppLockActions(this._ref);

  final Ref _ref;

  /// Turns the lock on or off. Turning it **on** first checks that the phone
  /// has a screen lock and that the person can pass it, so nobody is locked
  /// out of their own app by a lock they cannot open. Returns a sentence when
  /// it could not, else null.
  Future<String?> setEnabled(bool on) async {
    if (on) {
      final auth = _ref.read(deviceAuthenticatorProvider);
      if (!await auth.isAvailable()) {
        return 'This phone has no screen lock. Set a PIN, pattern or '
            'fingerprint in the phone\'s own settings first.';
      }
      if (!await auth.confirm('Turn on the Helix app lock')) {
        return 'The app lock was not turned on, because the phone\'s unlock '
            'was not completed.';
      }
    }
    await _ref.read(localSettingsProvider).set(AppSettings.appLockEnabled, on);
    return null;
  }

  Future<void> setRelockAfter(int seconds) => _ref
      .read(localSettingsProvider)
      .set(AppSettings.appLockRelockAfterSeconds, seconds);
}

// ------------------------------------------------- notification permission

/// Whether the phone lets Helix show notifications. Asking again re-reads it.
final notificationPermissionProvider =
    AsyncNotifierProvider.autoDispose<NotificationPermission, bool>(
      NotificationPermission.new,
    );

final class NotificationPermission extends AsyncNotifier<bool> {
  @override
  Future<bool> build() =>
      ref.read(notificationPermissionSourceProvider).allowed();

  Future<void> request() async {
    final source = ref.read(notificationPermissionSourceProvider);
    state = AsyncData(await source.request());
  }
}
