import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/local_settings.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/notifications/call_notifications.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote/features/calls/application/platform/call_platform.dart';

/// Rings through the incoming-call notification (Android): its channel plays
/// the phone's ringtone and vibrates until answered, declined or timed out,
/// and the same notification takes the whole screen over a locked phone.
final class NotificationCallRinger implements CallRinger {
  const NotificationCallRinger({this.previews, this.account});

  /// The notification-previews setting. Without it (or while it cannot be
  /// read) the caller's name stays off the notification.
  final Future<bool> Function()? previews;

  /// The account on screen, whose engine rings: a press on the notification
  /// after a switch opens it again.
  final String? Function()? account;

  @override
  Future<void> startIncoming({
    required String callId,
    required String callerName,
    required bool video,
    required bool fullScreen,
  }) async => CallNotifications.showIncoming(
    callId: callId,
    callerName: callerName,
    video: video,
    fullScreen: fullScreen,
    showCaller: await _previews(),
    account: account?.call(),
  );

  Future<bool> _previews() async {
    try {
      return await previews?.call() ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> stop(String callId) => CallNotifications.cancel(callId);
}

/// The ringer for this host: the ringtone notification on Android, a repeating
/// system alert elsewhere.
final callRingerProvider = Provider<CallRinger>((ref) {
  if (Platform.isAndroid) {
    return NotificationCallRinger(
      previews: () =>
          ref.read(localSettingsProvider).get(AppSettings.notificationsPreview),
      account: () => ref.read(activeAccountProvider)?.id,
    );
  }
  final ringer = AlertCallRinger();
  return ringer;
});
