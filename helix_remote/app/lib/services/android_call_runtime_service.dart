import 'dart:io';

import 'package:flutter/services.dart';

class AndroidCallRuntimeService {
  AndroidCallRuntimeService._();

  static const _channel = MethodChannel('com.helix.remote/calls');

  static Future<void> setCallActive({
    required bool active,
    required bool keepScreenOn,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setCallActive', {
        'active': active,
        'keepScreenOn': keepScreenOn,
      });
    } catch (_) {
      // Window flags are a best-effort Android integration, not call-critical.
    }
  }

  static Future<bool> shouldUseFullScreenIncomingCall() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'shouldUseFullScreenIncomingCall',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> startForegroundCall({
    required String callId,
    required String callerDisplayName,
    required bool isVideo,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('startForegroundCall', {
        'callId': callId,
        'callerDisplayName': callerDisplayName,
        'isVideo': isVideo,
      });
    } catch (_) {
      // Active call persistence falls back to the Dart ongoing notification.
    }
  }

  static Future<void> stopForegroundCall() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopForegroundCall');
    } catch (_) {}
  }
}
