import 'dart:async';

import 'package:helix_remote_api/src/v2/transport/errors.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Supplies bearer tokens for one token audience: device routes or admin
/// routes (they never open each other's routes, REST_V2.md).
abstract interface class AuthProvider {
  /// [RouteAccess.device] or [RouteAccess.admin].
  RouteAccess get audience;

  /// A token to send now. Throws [SignedOutException] when there is none.
  Future<String> accessToken();

  /// Called when the server refused [rejected] (HTTP 401, WebSocket 4001).
  /// Returns a token to retry with, or throws [SignedOutException].
  /// Concurrent calls share one refresh.
  Future<String> refresh(String rejected);
}

/// Where the device's [Session] lives between runs. The engine backs this
/// with secure storage; [MemorySessionStore] is for tests and the CLI.
abstract interface class SessionStore {
  Future<Session?> read();

  Future<void> write(Session session);

  Future<void> clear();
}

final class MemorySessionStore implements SessionStore {
  MemorySessionStore([this._session]);

  Session? _session;

  @override
  Future<Session?> read() async => _session;

  @override
  Future<void> write(Session session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}

/// Device tokens with single-flight refresh rotation.
///
/// - An access token that expires within [refreshAhead] is refreshed before
///   it is sent.
/// - A 401 refreshes once, however many requests failed with the same token
///   at the same moment; a request that failed with an older token gets the
///   newer one without another refresh.
/// - When the server refuses the refresh token, [reauthenticate] (device-key
///   sign-in, done by the engine because it needs the DSK) gets one chance.
///   Otherwise the session is cleared and [SignedOutException] is thrown
///   and published on [signedOut].
/// - A refresh that gets no answer (offline, 5xx) throws that error and
///   keeps the session: the refresh token may still be good.
final class DeviceSessionAuth implements AuthProvider {
  DeviceSessionAuth({
    required this._store,
    required this._refresher,
    this.reauthenticate,
    this.refreshAhead = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SessionStore _store;
  final Future<Session> Function(String refreshToken) _refresher;
  final DateTime Function() _now;

  /// Last resort when the refresh token is refused; null when it cannot
  /// sign in either.
  Future<Session?> Function()? reauthenticate;

  final Duration refreshAhead;

  final StreamController<SignedOutException> _signedOut =
      StreamController.broadcast();

  Session? _cached;
  bool _loaded = false;
  Future<Session>? _flight;

  @override
  RouteAccess get audience => RouteAccess.device;

  /// Emits once each time the session is lost.
  Stream<SignedOutException> get signedOut => _signedOut.stream;

  /// The current session, if any.
  Future<Session?> current() async {
    if (!_loaded) {
      _cached = await _store.read();
      _loaded = true;
    }
    return _cached;
  }

  /// Stores a session returned by registration or a sign-in route.
  Future<void> signedIn(Session session) async {
    await _store.write(session);
    _cached = session;
    _loaded = true;
  }

  /// Forgets the session (after `DELETE /v1/auth/sessions/current`, or when
  /// the device learns it was revoked).
  Future<void> forget() async {
    await _store.clear();
    _cached = null;
    _loaded = true;
  }

  @override
  Future<String> accessToken() async {
    final session = await current();
    if (session == null) {
      throw const SignedOutException(SignedOutReason.noSession);
    }
    if (_expiresSoon(session)) return refresh(session.accessToken);
    return session.accessToken;
  }

  @override
  Future<String> refresh(String rejected) async {
    final flight = _flight ??= _refresh(
      rejected,
    ).whenComplete(() => _flight = null);
    return (await flight).accessToken;
  }

  bool _expiresSoon(Session s) =>
      !s.accessExpiresAt.isAfter(_now().add(refreshAhead));

  Future<Session> _refresh(String rejected) async {
    final session = await current();
    if (session == null) {
      throw const SignedOutException(SignedOutReason.noSession);
    }
    // Someone refreshed since this token was sent.
    if (session.accessToken != rejected && !_expiresSoon(session)) {
      return session;
    }
    try {
      final fresh = await _refresher(session.refreshToken);
      await signedIn(fresh);
      return fresh;
    } on ApiException catch (e) {
      if (!_refused(e)) rethrow;
      final again = await reauthenticate?.call();
      if (again != null) {
        await signedIn(again);
        return again;
      }
      await forget();
      final out = SignedOutException(
        SignedOutReason.refreshRejected,
        code: e.code,
      );
      _signedOut.add(out);
      throw out;
    }
  }

  /// The server looked at the refresh token and said no: 401 (unknown,
  /// reused or expired token) or 403 (device revoked, account banned), as
  /// opposed to not answering.
  static bool _refused(ApiException e) => e.status == 401 || e.status == 403;

  Future<void> close() => _signedOut.close();
}

/// Admin console tokens (`helix.admin` audience, 12 hours). There is no
/// refresh: when the token expires or is refused the operator signs in
/// again. `AdminClient` stores the session it gets from setup, sign-in and
/// password changes here.
final class AdminTokenAuth implements AuthProvider {
  AdminTokenAuth({this._session, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  AdminSession? _session;
  final DateTime Function() _now;

  final StreamController<SignedOutException> _signedOut =
      StreamController.broadcast();

  @override
  RouteAccess get audience => RouteAccess.admin;

  AdminSession? get session => _session;

  Stream<SignedOutException> get signedOut => _signedOut.stream;

  void use(AdminSession session) => _session = session;

  void forget() => _session = null;

  @override
  Future<String> accessToken() async {
    final s = _session;
    if (s == null) throw const SignedOutException(SignedOutReason.noSession);
    if (!s.expiresAt.isAfter(_now())) _end();
    return s.token;
  }

  @override
  Future<String> refresh(String rejected) async => _end();

  Never _end() {
    _session = null;
    const out = SignedOutException(SignedOutReason.sessionEnded);
    _signedOut.add(out);
    throw out;
  }

  Future<void> close() => _signedOut.close();
}
