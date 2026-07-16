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
}
