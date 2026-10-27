import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/platform/account_slots.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:orbit_ui/models.dart' show HelixWallpaper;

/// Settings the app owns rather than the engine.
///
/// They are stored next to the engine's own typed settings, in the same
/// encrypted table, and never leave the device. The engine declares its keys
/// in `EngineSettings`; UI-only preferences belong here (plan §6.4).
abstract final class AppSettings {
  /// Ask for the device's fingerprint, face or PIN when the app comes back.
  /// Read only to move it to the device: the lock is now a [DeviceLock].
  static const appLockEnabled = Setting<bool>('app.lock_enabled', false);

  /// How long the app may stay in the background before it locks again.
  /// Likewise only read to move it.
  static const appLockRelockAfterSeconds = Setting<int>(
    'app.lock_relock_after_seconds',
    60,
  );

  /// Show who wrote and what they said in the notification, on the shade and on
  /// a locked phone. On by default since 2026-10-25: a notification that names
  /// nobody and says nothing is not worth a wake-up. Off still alerts, and the
  /// notification says only that something arrived.
  static const notificationsPreview = Setting<bool>(
    'app.notifications_preview',
    true,
  );

  // ---- Settings pages (Phase A3b). Every key lives in the encrypted settings
  // table and never leaves the device.

  /// Text size inside the app, as a percentage of the system size. Applied at
  /// the root (`AppTextScale`), so it composes with the phone's own setting
  /// rather than replacing it.
  static const fontScalePercent = Setting<int>('app.font_scale_percent', 100);

  /// What chats are drawn on, unless a chat has its own (see
  /// [chatWallpaper]). The theme's own background by default.
  static const wallpaper = Setting<HelixWallpaper>.enumeration(
    'app.wallpaper',
    HelixWallpaper.values,
    HelixWallpaper.theme,
  );

  /// One chat's own wallpaper: the name of a [HelixWallpaper], or empty to
  /// follow [wallpaper]. Kept per chat, so it stays with the account.
  static Setting<String> chatWallpaper(String conversationId) =>
      Setting<String>('app.wallpaper.chat.$conversationId', '');

  /// Fetch a link's title and description from the website when a message with
  /// a link is sent, and send them as a card. Off by default: the site sees
  /// the sender's address. The reader never fetches anything.
  static const linkPreviews = Setting<bool>('app.link_previews', false);

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
    // Wi-Fi only: a photo a stranger sends should not spend mobile data (or
    // reveal this phone's address to a hostile link) without a tap.
    MediaDownloadPolicy.wifi,
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

/// What the lock needs: the device's lock, which covers every account here.
///
/// The lock screen sits above the navigator and so cannot be handed the
/// runtime; a [StreamProvider] is how it learns the setting without that.
/// Nothing locks without an account on screen.
final appLockSettingProvider = StreamProvider<AppLockSetting>((ref) async* {
  final lock = ref.watch(accountsProvider.select((a) => a.lock));
  final runtime = await ref.watch(runtimeProvider.future);
  if (lock != null) {
    yield AppLockSetting(
      enabled: lock.enabled,
      relockAfterSeconds: lock.relockAfterSeconds,
    );
    return;
  }
  // Before several accounts the lock was the account's own setting, in its
  // database; the first read makes it the device's.
  final settings = runtime.engine.settings;
  final moved = DeviceLock(
    enabled: await settings.get(AppSettings.appLockEnabled),
    relockAfterSeconds: await settings.get(
      AppSettings.appLockRelockAfterSeconds,
    ),
  );
  yield AppLockSetting(
    enabled: moved.enabled,
    relockAfterSeconds: moved.relockAfterSeconds,
  );
  final accounts = ref.read(accountsProvider);
  if (accounts.current?.signedIn ?? false) {
    await ref.read(accountsProvider.notifier).setLock(moved);
  }
});

/// Whether the lock is wanted, and after how long.
final class AppLockSetting {
  const AppLockSetting({
    required this.enabled,
    required this.relockAfterSeconds,
  });

  final bool enabled;
  final int relockAfterSeconds;
}
