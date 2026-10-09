import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
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

/// Where push tokens come from. Behind an interface so the logic that decides
/// *when* to register (`PushRegistration`) is tested without Firebase.
abstract interface class PushTokens {
  /// Sets push up in this isolate, once, and asks for the permission to
  /// notify. False when this build has no push at all.
  Future<bool> prepare();

  /// The current token, or null when there is none.
  Future<String?> currentToken();

  /// Every token the platform rotates to, after [prepare].
  Stream<String> get refreshes;
}

/// Firebase Cloud Messaging tokens, on Android.
///
/// Push is what lets a closed app learn there is something waiting. It is
/// **not required**: without a token - no `google-services.json`, no
/// permission, a platform with no Firebase - the app still works, and catches
/// up over REST when it is next opened. Every method here answers false, null
/// or nothing rather than throwing, because "push unavailable" is a normal
/// state for a development checkout, not a failure.
final class PushTokenSource implements PushTokens {
  PushTokenSource({FirebaseMessaging? messaging}) : _injected = messaging;

  final FirebaseMessaging? _injected;
  FirebaseMessaging? _messaging;
  Future<bool>? _prepared;

  /// Whether this build can register a token at all.
  bool get available => defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> prepare() => _prepared ??= _prepare();

  Future<bool> _prepare() async {
    if (!available) return false;
    final FirebaseMessaging messaging;
    try {
      // This isolate needs its own Firebase app: the background handler's
      // lives in its isolate. Without it `FirebaseMessaging.instance` throws,
      // which is how the token went unregistered before 2026-10-09.
      messaging = _injected ?? await _firebaseMessaging();
    } on Object {
      return false; // No google-services.json in this build, or no Play services.
    }
    try {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
    } on Object {
      // Refused or unanswerable: the token still wakes the app for calls and
      // catching up; only the notifications stay hidden.
    }
    _messaging = messaging;
    return true;
  }

  static Future<FirebaseMessaging> _firebaseMessaging() async {
    await Firebase.initializeApp();
    return FirebaseMessaging.instance;
  }

  @override
  Future<String?> currentToken() async {
    final messaging = _messaging;
    if (messaging == null) return null;
    try {
      return await messaging.getToken();
    } on Object {
      return null;
    }
  }

  @override
  Stream<String> get refreshes =>
      _messaging?.onTokenRefresh ?? const Stream<String>.empty();
}
