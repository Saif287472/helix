import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show DevicePlatform;

/// What this build tells the server it is, when it registers a push token.
DevicePlatform get pushDevicePlatform => switch (defaultTargetPlatform) {
  TargetPlatform.android => DevicePlatform.android,
  TargetPlatform.iOS => DevicePlatform.ios,
  TargetPlatform.windows => DevicePlatform.windows,
  _ => DevicePlatform.other,
};

/// Keeps the account's push token current.
///
/// Push is what lets a closed app learn there is something waiting. It is
/// **not required**: without a token - no `google-services.json`, no
/// permission, a platform with no Firebase - the app still works, and catches
/// up over REST when it is next opened. Every method here answers null or does
/// nothing rather than throwing, because "push unavailable" is a normal state
/// for a development checkout, not a failure.
final class PushTokenSource {
  PushTokenSource({FirebaseMessaging? messaging})
    : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;
  StreamSubscription<String>? _tokens;

  /// Whether this build can register a token at all.
  bool get available => defaultTargetPlatform == TargetPlatform.android;

  /// The current token, or null when there is none.
  Future<String?> currentToken() async {
    if (!available) return null;
    try {
      return await _messaging.getToken();
    } on Object {
      return null;
    }
  }

  /// Asks for permission and reports every token, starting with the current
  /// one. [onToken] failures are swallowed: the engine is signed out or
  /// offline, and will try again.
  Future<void> start({
    required Future<void> Function(String token) onToken,
  }) async {
    if (!available) return;
    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await currentToken();
      if (token != null) await onToken(token);
      await _tokens?.cancel();
      _tokens = _messaging.onTokenRefresh.listen((value) async {
        try {
          await onToken(value);
        } on Object {
          // Retried on the next launch.
        }
      });
    } on Object {
      // Push unavailable on this build.
    }
  }

  Future<void> dispose() async {
    await _tokens?.cancel();
    _tokens = null;
  }
}
