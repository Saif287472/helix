import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/helix_runtime.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/notifications/local_notifications.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote_db/helix_remote_db.dart' show Setting;
import 'package:helix_remote_engine/helix_remote_engine.dart';

/// Reads one on/off setting (Settings > Notifications).
typedef ReadFlag = Future<bool> Function(Setting<bool> setting);

/// Raises the message notification ([MessageAlerts.show]).
typedef ShowMessageAlert =
    Future<void> Function(
      ReadFlag read, {
      required String account,
      required int count,
      IncomingNotice? only,
      String? accountLabel,
    });

/// Which new messages alert, and the one notification for them.
///
/// Shared by the push isolate, which raises it for what a wake-up fetched,
/// and the running app, which raises it while it is in the background, so
/// both follow Settings > Notifications the same way.
abstract final class MessageAlerts {
  /// Whether [notice] alerts: its chat is not muted, and alerts for its kind
  /// of chat (direct or group) are on. Off still records the message; it
  /// only stays quiet.
  static Future<bool> alerts(IncomingNotice notice, ReadFlag read) async {
    if (notice.muted) return false;
    return read(
      notice.conversationId.startsWith('group:')
          ? AppSettings.notifyGroups
          : AppSettings.notifyMessages,
    );
  }

  /// Shows, or replaces, [account]'s one notification for [count] new
  /// messages. [only] is the message when there is exactly one: its text
  /// appears only when the person turned previews on, and it comes from this
  /// phone's own decrypted copy, never from a push. [accountLabel] (on a
  /// device with several accounts) follows the same setting: it names whose
  /// phone this is.
  static Future<void> show(
    ReadFlag read, {
    required String account,
    required int count,
    IncomingNotice? only,
    String? accountLabel,
  }) async {
    final previews = await read(AppSettings.notificationsPreview);
    await LocalNotifications.showMessages(
      account: account,
      count: count,
      sound: await read(AppSettings.notifySound),
      vibrate: await read(AppSettings.notifyVibrate),
      preview: await preview(read, count: count, only: only),
      accountLabel: previews ? accountLabel : null,
    );
  }

  /// The text the notification may show: the one message's own text, with
  /// previews on; otherwise null, and the notification says only that
  /// something arrived.
  static Future<String?> preview(
    ReadFlag read, {
    required int count,
    IncomingNotice? only,
  }) async {
    if (count != 1 || only == null || only.preview.isEmpty) return null;
    return await read(AppSettings.notificationsPreview) ? only.preview : null;
  }
}

/// Raises the message notification from the running app while it is in the
/// background.
///
/// The app keeps its engine and socket when the person switches away, so
/// messages keep arriving here: the server sends no push to a device that is
/// connected, and the push isolate stands down while this engine holds the
/// database. Before 2026-10-09 nothing here raised a notification, so they
/// went unnoticed until the app was opened again.
final class RunningAppAlerts {
  RunningAppAlerts({
    required this.inForeground,
    required this.onScreen,
    String? Function(String account)? label,
    ShowMessageAlert? show,
    Future<void> Function(String account)? clear,
  }) : _label = label ?? _noLabel,
       _show = show ?? MessageAlerts.show,
       _clear = clear ?? LocalNotifications.clearMessages;

  /// Whether the person is looking at the app (then nothing is raised).
  final bool Function() inForeground;

  /// The account on screen, or null on sign-in.
  final String? Function() onScreen;

  final String? Function(String account) _label;
  final ShowMessageAlert _show;
  final Future<void> Function(String account) _clear;

  static String? _noLabel(String account) => null;

  /// The account whose run [_count] counts.
  String? _account;
  int _count = 0;

  /// A new message arrived for [account] through the running engine.
  Future<void> onNotice(
    IncomingNotice notice,
    ReadFlag read, {
    required String account,
  }) async {
    if (inForeground()) return;
    try {
      if (!await MessageAlerts.alerts(notice, read)) return;
      if (_account != account) {
        _account = account;
        _count = 0;
      }
      final count = ++_count;
      await _show(
        read,
        account: account,
        count: count,
        only: count == 1 ? notice : null,
        accountLabel: _label(account),
      );
    } on Object {
      // Settings unreadable (the runtime is closing) or no notifications on
      // this platform: the message is in the chat list either way.
    }
  }

  /// [account]'s engine started (a launch or a switch): with the app in
  /// front its chats are on screen, so its notification goes.
  Future<void> opened(String account) async {
    if (inForeground()) await _clearFor(account);
  }

  /// Back in the foreground: the chats are on screen, so their account's
  /// notification goes, and the next background run counts from one again.
  /// Other accounts' notifications stay until they are opened.
  Future<void> resumed() async {
    final account = onScreen();
    if (account != null) await _clearFor(account);
  }

  Future<void> _clearFor(String account) async {
    if (_account == account) _count = 0;
    try {
      await _clear(account);
    } on Object {
      // No notifications on this platform.
    }
  }
}

/// Whether the app is on screen. `inactive` (a dialog or the shade over it)
/// still counts as on screen; before the first lifecycle report it is
/// assumed to be, so opening the app never raises a stray notification.
bool appInForeground() => switch (WidgetsBinding.instance.lifecycleState) {
  AppLifecycleState.paused ||
  AppLifecycleState.hidden ||
  AppLifecycleState.detached => false,
  _ => true,
};

/// Follows the running engine's new-message events for [RunningAppAlerts].
/// Read once, by the app root, and kept for the whole run.
final runningAppAlertsProvider = Provider<RunningAppAlerts>((ref) {
  final alerts = RunningAppAlerts(
    inForeground: appInForeground,
    onScreen: () => ref.read(activeAccountProvider)?.id,
    label: (account) => ref.read(accountsProvider).notificationLabel(account),
  );
  StreamSubscription<EngineEvent>? events;
  ref.listen<AsyncValue<HelixRuntime>>(runtimeProvider, (_, next) {
    unawaited(events?.cancel());
    events = null;
    if (next.isLoading) return;
    final runtime = next.value;
    if (runtime == null) return;
    final engine = runtime.engine;
    unawaited(alerts.opened(runtime.account));
    events = engine.events.listen((event) {
      if (event is IncomingMessageEvent) {
        unawaited(
          alerts.onNotice(
            event.notice,
            engine.settings.get,
            account: runtime.account,
          ),
        );
      }
    });
  }, fireImmediately: true);
  ref.onDispose(() => events?.cancel());
  return alerts;
});
