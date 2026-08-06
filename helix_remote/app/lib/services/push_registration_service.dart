import 'dart:async';

import 'package:helix_remote/services/app_logger.dart';
import 'package:helix_remote/services/push_token_source.dart';
import 'package:helix_remote_api/api/rest_client.dart';

/// Keeps the server's copy of this device's push token in step with the one
/// the push SDK actually holds.
///
/// Without this, a call to a closed app can never ring: the backend enqueues
/// a wake notification, finds no token for the device, and completes the
/// outbox entry silently (see `outbox_worker.dart`). The server side of that
/// path was already built and tested; this is the half that was missing.
///
/// Three things have to hold for push to keep working, and each is a way it
/// quietly dies:
///
///  * register once the session can authenticate — the endpoint is
///    authenticated, so registering before login just 401s;
///  * re-register when the SDK rotates the token, or the server keeps
///    sending to an address the device stopped answering on;
///  * deregister *before* sign-out purges the credentials, or the server goes
///    on waking a device that is no longer signed in — and there is no way to
///    reach the endpoint afterwards.
class PushRegistrationService {
  PushRegistrationService({
    required PushTokenSource source,
    required HelixRemoteRestClient Function() restClient,
  }) : _source = source,
       _restClient = restClient;

  final PushTokenSource _source;

  /// Resolved lazily: the REST client is rebuilt when the server URL or
  /// session changes, so holding a reference here would pin a stale one.
  final HelixRemoteRestClient Function() _restClient;

  StreamSubscription<String>? _refreshSub;
  String? _registeredToken;
  bool _available = false;
  bool _started = false;

  /// Whether a push transport is present and permitted. False is normal —
  /// see [UnavailablePushTokenSource].
  bool get isAvailable => _available;

  /// The token currently registered with the server, for diagnostics. Never
  /// logged: a push token is a capability to send to this device.
  String? get registeredToken => _registeredToken;

  /// Brings push up and registers the current token.
  ///
  /// Safe to call more than once — a second call re-syncs rather than
  /// duplicating subscriptions, which matters because the runtime restarts
  /// on reconnect and on account switch.
  Future<void> start() async {
    if (_started) {
      await _syncToken();
      return;
    }
    _started = true;
    try {
      _available = await _source.initialize();
    } catch (e) {
      // A misconfigured or missing Firebase setup must not take down startup.
      // Push is an enhancement; messaging works without it.
      _available = false;
      AppLogger.instance.warn('push', 'push init failed, continuing: $e');
    }
    if (!_available) {
      AppLogger.instance.info(
        'push',
        'push unavailable — calls cannot wake a closed app',
      );
      return;
    }
    _refreshSub = _source.tokenRefreshes.listen(
      _onTokenRefreshed,
      onError: (Object e) =>
          AppLogger.instance.warn('push', 'token refresh stream error: $e'),
    );
    await _syncToken();
  }

  Future<void> _onTokenRefreshed(String token) async {
    AppLogger.instance.info('push', 'push token rotated, re-registering');
    await _register(token);
  }

  Future<void> _syncToken() async {
    if (!_available) return;
    try {
      final token = await _source.currentToken();
      if (token == null || token.isEmpty) {
        AppLogger.instance.warn('push', 'no push token available to register');
        return;
      }
      await _register(token);
    } catch (e) {
      AppLogger.instance.warn('push', 'push token lookup failed: $e');
    }
  }

  Future<void> _register(String token) async {
    // Skip an unchanged token: start() runs on every runtime start, and the
    // token only rarely changes.
    if (token == _registeredToken) return;
    try {
      await _restClient().registerPushToken(
        pushToken: token,
        tokenType: _source.tokenType,
      );
      _registeredToken = token;
      AppLogger.instance.info('push', 'push token registered');
    } catch (e) {
      // Left unregistered on purpose: _registeredToken is not updated, so the
      // next start() retries. Failing here must not block the runtime.
      AppLogger.instance.warn('push', 'push token registration failed: $e');
    }
  }

  /// Drops the server's token for this device.
  ///
  /// Must run *before* the session credentials are purged — the endpoint is
  /// authenticated. Failures are swallowed: sign-out cannot be blocked by a
  /// server that is unreachable, and the token is invalidated locally either
  /// way.
  Future<void> deregister() async {
    if (_registeredToken == null) return;
    try {
      await _restClient().deregisterPushToken();
      AppLogger.instance.info('push', 'push token deregistered');
    } catch (e) {
      AppLogger.instance.warn('push', 'push token deregistration failed: $e');
    } finally {
      _registeredToken = null;
    }
  }

  Future<void> dispose() async {
    await _refreshSub?.cancel();
    _refreshSub = null;
    _started = false;
    _registeredToken = null;
    await _source.dispose();
  }
}
