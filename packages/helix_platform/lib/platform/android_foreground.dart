// lib/platform/android_foreground.dart
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:helix_domain/core/constants.dart';

/// Dart-side interface to the Android foreground service.
///
/// All methods are no-ops on non-Android platforms so callers do not need
/// platform guards.
class AndroidForegroundService {
  AndroidForegroundService._();

  static const String channelName = kMethodChannelName;

  static MethodChannel get _channel => MethodChannel(channelName);

  /// Starts the Kotlin [HelixForegroundService].
  ///
  /// Safe to call multiple times — the service ignores duplicate start
  /// commands (START_NOT_STICKY means no auto-restart after it is stopped).
  static Future<void> startService({bool inCall = false}) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>(
        'startService',
        <String, dynamic>{'inCall': inCall},
      );
    } on PlatformException catch (e) {
      // Log but don't crash — the app remains functional without the service.
      // ignore: avoid_print
      print('[AndroidForegroundService] startService failed: ${e.message}');
    }
  }

  /// Stops the Kotlin [HelixForegroundService].
  static Future<void> stopService() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopService');
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[AndroidForegroundService] stopService failed: ${e.message}');
    }
  }

  /// Updates the content text shown in the persistent foreground notification.
  ///
  /// [text] is displayed below the "Helix is active" title line.
  /// Example: "2 active chats · Discoverable"
  static Future<void> updateNotificationText(String text, {bool inCall = false}) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>(
        'updateNotificationText',
        <String, dynamic>{'text': text, 'inCall': inCall},
      );
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print(
        '[AndroidForegroundService] updateNotificationText failed: ${e.message}',
      );
    }
  }
}
