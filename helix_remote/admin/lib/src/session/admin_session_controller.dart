import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:helix_admin/src/api/error_text.dart';
import 'package:helix_admin/src/api/server_address.dart';
import 'package:helix_admin/src/services/admin_services.dart';
import 'package:helix_admin/src/services/admin_settings.dart';
import 'package:helix_admin/src/services/token_vault.dart';
import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// What the console shows: a spinner while starting, the device lock, the
/// sign-in/setup form, or the console itself.
enum SessionPhase { starting, locked, signedOut, signedIn }

/// What every feature controller gets: the one API facade, a way to tell the
/// session about a failed call (a rejected token sends the operator back to
/// sign-in) and the clock.
final class AdminContext {
  const AdminContext({
    required this.api,
    required this.report,
    required this.now,
  });

  final HelixAdminApi api;

  /// Called with every error a call threw; ends the session when the token
  /// is no longer accepted.
  final void Function(Object error) report;
  final DateTime Function() now;
}

/// The admin session: first-run setup, sign-in, the saved token, the 12-hour
/// expiry and the device lock.
///
/// The password is held only for the duration of a call. The token is kept in
/// the `TokenVault` (secure storage) and in the `HelixAdminApi`; it is never
/// logged or shown.
final class AdminSessionController extends ChangeNotifier {
  AdminSessionController(this.services);

  final AdminServices services;

  SessionPhase _phase = SessionPhase.starting;
  AdminSettings? _settings;

  HelixAdminApi? _api;
  ServerAddress? _address;
  AdminSession? _session;
  StreamSubscription<SignedOutException>? _signedOutSub;
  Timer? _expiryTimer;
  bool _disposed = false;

  // The server the sign-in form is pointed at, once checked.
  HelixAdminApi? _pendingApi;
  ServerAddress? _pendingAddress;

  bool _busy = false;
  bool? _setupRequired;
  String? _error;
  String? _notice;
  String? _lockError;
  String _lastServerUrl = '';

  SessionPhase get phase => _phase;

  /// True while a request of the sign-in form is running.
  bool get busy => _busy;

  /// Whether the server the form points at still needs its first admin
  /// password; null until [checkServer] has answered.
  bool? get setupRequired => _setupRequired;

  /// The last sign-in problem, in operator words.
  String? get error => _error;

  /// Why the operator is back at sign-in (session ended or expired).
  String? get notice => _notice;

  /// The device lock's last problem.
  String? get lockError => _lockError;

  /// The address the sign-in form starts with.
  String get lastServerUrl => _lastServerUrl;

  bool get appLockEnabled => _settings?.appLockEnabled ?? false;

  /// The signed-in API; null unless [phase] is [SessionPhase.signedIn].
  HelixAdminApi? get api => _phase == SessionPhase.signedIn ? _api : null;

  ServerAddress? get serverAddress => _address;

  DateTime? get sessionExpiresAt => _session?.expiresAt;

  /// What feature controllers use; non-null while signed in.
  AdminContext? get context {
    final api = this.api;
    if (api == null) return null;
    return AdminContext(api: api, report: reportError, now: services.now);
  }

  // ------------------------------------------------------------------ start

  Future<void> start() async {
    _settings = await services.loadSettings();
    _lastServerUrl = _settings!.serverUrl ?? '';
    if (_settings!.appLockEnabled) {
      _setPhase(SessionPhase.locked);
    } else {
      await _resume();
    }
  }

  /// Asks for the device unlock; on success opens the saved session.
  Future<void> unlock() async {
    if (_phase != SessionPhase.locked || _busy) return;
    _busy = true;
    _lockError = null;
    notifyListeners();
    final ok = await services.deviceLock.authenticate('Unlock Helix Admin');
    _busy = false;
    if (_disposed) return;
    if (ok) {
      _lockError = null;
      _setPhase(SessionPhase.starting);
      await _resume();
    } else {
      _lockError = 'The device was not unlocked.';
      notifyListeners();
    }
  }

  /// Opens the saved session when it is still good.
  Future<void> _resume() async {
    final stored = await services.vault.read();
    if (_disposed) return;
    if (stored == null) return _toSignedOut();
    if (!stored.session.expiresAt.isAfter(services.now())) {
      await services.vault.clear();
      return _toSignedOut(notice: 'Your admin session expired. Sign in again.');
    }
    final ServerAddress address;
    try {
      address = ServerAddress.parse(stored.serverUrl);
    } on ServerAddressException {
      await services.vault.clear();
      return _toSignedOut();
    }
    final api = services.apiFactory(address.uri, session: stored.session);
    try {
      // The cheapest authenticated read: proves the token is still accepted.
      await api.admin.config();
    } on Object catch (e) {
      unawaited(api.close());
      if (_disposed) return;
      if (endsAdminSession(e)) {
        await services.vault.clear();
        return _toSignedOut(
          notice: 'Your admin session has ended. Sign in again.',
        );
      }
      return _toSignedOut(error: describeAdminError(e, now: services.now));
    }
    if (_disposed) {
      unawaited(api.close());
      return;
    }
    _enter(api, address, stored.session);
  }

  // ------------------------------------------------------------- sign-in form

  /// Asks the server whether it still needs first-run setup.
  Future<void> checkServer(String raw) async {
    if (_busy) return;
    _error = null;
    final ServerAddress address;
    try {
      address = ServerAddress.parse(raw);
    } on ServerAddressException catch (e) {
      _error = e.message;
      notifyListeners();
      return;
    }
    _discardPending();
    _busy = true;
    notifyListeners();
    final api = services.apiFactory(address.uri);
    try {
      final status = await api.admin.setupStatus();
      if (_disposed) {
        unawaited(api.close());
        return;
      }
      _pendingApi = api;
      _pendingAddress = address;
      _setupRequired = !status.configured;
    } on Object catch (e) {
      unawaited(api.close());
      if (_disposed) return;
      _error = describeAdminError(e, now: services.now);
    }
    _busy = false;
    notifyListeners();
  }

  /// The address text changed: what was checked no longer applies.
  void addressEdited() {
    if (_setupRequired == null && _pendingApi == null && _error == null) {
      return;
    }
    _discardPending();
    _error = null;
    notifyListeners();
  }

  /// Signs in to the checked server. Returns whether it worked.
  Future<bool> signIn(String password) {
    if (password.isEmpty) {
      _error = 'Enter the admin password.';
      notifyListeners();
      return Future.value(false);
    }
    return _authenticate((api) => api.admin.signIn(password));
  }

  /// First-run setup on the checked server: sets the admin password and
  /// signs in. [password] must satisfy [validateNewPassword].
  Future<bool> setup(String password, String confirmation) {
    final problem = validateNewPassword(password, confirmation);
    if (problem != null) {
      _error = problem;
      notifyListeners();
      return Future.value(false);
    }
    return _authenticate((api) => api.admin.setup(password));
  }

  Future<bool> _authenticate(
    Future<AdminSession> Function(HelixAdminApi api) call,
  ) async {
    final api = _pendingApi;
    final address = _pendingAddress;
    if (api == null || address == null || _busy) {
      _error ??= 'Check the server address first.';
      notifyListeners();
      return false;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final session = await call(api);
      await services.vault.write(
        StoredSession(serverUrl: address.text, session: session),
      );
      await _settings?.setServerUrl(address.text);
      if (_disposed) return false;
      _lastServerUrl = address.text;
      _pendingApi = null;
      _pendingAddress = null;
      _busy = false;
      _enter(api, address, session);
      return true;
    } on Object catch (e) {
      if (_disposed) return false;
      _error = describeAdminError(e, now: services.now);
      if (e is ApiException && e.code == ErrorCode.alreadyExists) {
        // Someone finished setup first: the form becomes a sign-in.
        _setupRequired = false;
      }
      _busy = false;
      notifyListeners();
      return false;
    }
  }

  void _discardPending() {
    final pending = _pendingApi;
    _pendingApi = null;
    _pendingAddress = null;
    _setupRequired = null;
    if (pending != null) unawaited(pending.close());
  }

  // ----------------------------------------------------------------- signed in

  void _enter(HelixAdminApi api, ServerAddress address, AdminSession session) {
    _api = api;
    _address = address;
    _session = session;
    _error = null;
    _notice = null;
    _setupRequired = null;
    _signedOutSub = api.auth.signedOut.listen(
      (_) => _end('Your admin session has ended. Sign in again.'),
    );
    _scheduleExpiry(session.expiresAt);
    _setPhase(SessionPhase.signedIn);
  }

  void _scheduleExpiry(DateTime expiresAt) {
    _expiryTimer?.cancel();
    final left = expiresAt.difference(services.now());
    _expiryTimer = Timer(
      left.isNegative ? Duration.zero : left,
      () => _end('Your admin session expired after 12 hours. Sign in again.'),
    );
  }

  /// Feature controllers hand every failed call here.
  void reportError(Object error) {
    if (_phase == SessionPhase.signedIn && endsAdminSession(error)) {
      _end('Your admin session has ended. Sign in again.');
    }
  }

  /// Changes the admin password. Every other admin session ends; this one
  /// continues with the new token. Errors reach the caller (the dialog).
  Future<void> changePassword({
    required String current,
    required String next,
  }) async {
    final api = _api;
    final address = _address;
    if (api == null || address == null) {
      throw const SignedOutException(SignedOutReason.noSession);
    }
    final session = await api.admin.changePassword(
      current: current,
      next: next,
    );
    _session = session;
    await services.vault.write(
      StoredSession(serverUrl: address.text, session: session),
    );
    _scheduleExpiry(session.expiresAt);
  }

  /// Signs out: forgets the token everywhere. (There is no server call: the
  /// token simply expires.)
  Future<void> signOut() => _end(null);

  Future<void> _end(String? notice) async {
    final api = _api;
    // Several things can end a session at once (the expiry timer, a 401 on
    // two screens); only the first does the work.
    if (_phase != SessionPhase.signedIn || api == null) return;
    _api = null;
    _session = null;
    _address = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final sub = _signedOutSub;
    _signedOutSub = null;
    api.auth.forget();
    unawaited(sub?.cancel());
    unawaited(api.close());
    _toSignedOut(notice: notice);
    await services.vault.clear();
  }

  void _toSignedOut({String? notice, String? error}) {
    _discardPending();
    _error = error;
    _notice = notice;
    _setPhase(SessionPhase.signedOut);
  }

  void _setPhase(SessionPhase phase) {
    _phase = phase;
    notifyListeners();
  }

  // ----------------------------------------------------------------- app lock

  /// Turns App lock on or off. Turning it on needs a device screen lock;
  /// returns a problem to show, or null.
  Future<String?> setAppLock(bool enabled) async {
    if (enabled && !await services.deviceLock.isSupported()) {
      return 'No screen lock is set up on this device. Set a PIN, pattern, '
          'password or fingerprint in the device settings first.';
    }
    await _settings?.setAppLockEnabled(enabled);
    notifyListeners();
    return null;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _expiryTimer?.cancel();
    unawaited(_signedOutSub?.cancel());
    unawaited(_api?.close());
    unawaited(_pendingApi?.close());
    super.dispose();
  }
}

/// The rule for a new admin password: 12 to 256 characters (the server's
/// `AdminPasswordRequest` limits), typed twice. Null when it is fine.
String? validateNewPassword(String password, String confirmation) {
  if (password.length < AdminPasswordRequest.minLength) {
    return 'The password needs at least ${AdminPasswordRequest.minLength} '
        'characters.';
  }
  if (password.length > AdminPasswordRequest.maxLength) {
    return 'The password can have at most ${AdminPasswordRequest.maxLength} '
        'characters.';
  }
  if (password != confirmation) return 'The two passwords do not match.';
  return null;
}
