import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/notifications/call_notifications.dart';
import 'package:helix_remote/features/calls/application/platform/call_platform.dart';

/// Rings through the incoming-call notification (Android): its channel plays
/// the phone's ringtone and vibrates until answered, declined or timed out,
/// and the same notification takes the whole screen over a locked phone.
final class NotificationCallRinger implements CallRinger {
  const NotificationCallRinger();

  @override
  Future<void> startIncoming({
    required String callId,
    required String callerName,
    required bool video,
    required bool fullScreen,
  }) => CallNotifications.showIncoming(
    callId: callId,
    callerName: callerName,
    video: video,
    fullScreen: fullScreen,
  );

  @override
  Future<void> stop(String callId) => CallNotifications.cancel(callId);
}

/// The ringer for this host: the ringtone notification on Android, a repeating
/// system alert elsewhere.
final callRingerProvider = Provider<CallRinger>((ref) {
  if (Platform.isAndroid) return const NotificationCallRinger();
  final ringer = AlertCallRinger();
  return ringer;
});
