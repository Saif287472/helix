import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:helix_remote/services/push_token_source.dart';

/// [PushTokenSource] backed by Firebase Cloud Messaging.
///
/// Deliberately tolerant of an unconfigured build. `google-services.json` is
/// not in the repository — it is deployment material, and a developer
/// checkout will not have one — so `Firebase.initializeApp()` throwing is an
/// expected outcome, not a crash. Every failure path answers "push is
/// unavailable" and the app carries on without it.
///
/// Nothing about a message is carried in the push payload: the server sends
/// only a wake hint (see `outbox_worker.dart`, which rejects payloads
/// containing content keys). The notification exists to bring the app far
/// enough forward to open its own authenticated connection and fetch the
/// call over the normal path.
class FirebasePushTokenSource implements PushTokenSource {
  FirebasePushTokenSource();

  final StreamController<String> _refreshes =
      StreamController<String>.broadcast();
  StreamSubscription<String>? _sdkRefreshSub;
  bool _initialized = false;

  @override
  String get tokenType => 'FCM';

  @override
  Future<bool> initialize() async {
    if (_initialized) return true;
    // FCM is Android-only for this product today: there is no iOS target, and
    // the desktop builds have no push transport. Calling into the plugin on
    // Windows throws a MissingPluginException on every launch.
    if (!Platform.isAndroid) return false;

    try {
      await Firebase.initializeApp();
    } catch (e) {
      // Almost always a missing or malformed google-services.json. Treated as
      // "push not configured for this build" rather than a fatal error.
      return false;
    }

    final messaging = FirebaseMessaging.instance;
    try {
      final settings = await messaging.requestPermission();
      // Provisional counts: on Android 13+ a user who has not answered the
      // prompt yet can still receive a token, and denying only suppresses the
      // banner - the data message still wakes the app, which is what a call
      // needs.
      final denied = settings.authorizationStatus == AuthorizationStatus.denied;
      if (denied) return false;
    } catch (_) {
      // An older embedding without the permission API - carry on and let the
      // token lookup decide.
    }

    _sdkRefreshSub = messaging.onTokenRefresh.listen(
      _refreshes.add,
      onError: _refreshes.addError,
    );
    _initialized = true;
    return true;
  }

  @override
  Future<String?> currentToken() async {
    if (!_initialized) return null;
    return FirebaseMessaging.instance.getToken();
  }

  @override
  Stream<String> get tokenRefreshes => _refreshes.stream;

  @override
  Future<void> dispose() async {
    await _sdkRefreshSub?.cancel();
    _sdkRefreshSub = null;
    await _refreshes.close();
    _initialized = false;
  }
}
