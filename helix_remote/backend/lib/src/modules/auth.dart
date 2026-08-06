import 'dart:convert';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:helix_remote_backend/src/app_error.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/invite_codes.dart';
import 'package:helix_remote_backend/src/jwt.dart';
import 'package:helix_remote_backend/src/phone_hash.dart' as phone_hash;
import 'package:helix_remote_backend/src/reserved_identifiers.dart';
import 'package:helix_remote_backend/src/server_name.dart';
import 'package:helix_remote_backend/src/sms_provider.dart';

part 'auth/challenge_login.dart';
part 'auth/devices.dart';
part 'auth/invites.dart';
part 'auth/phone_otp.dart';
part 'auth/profile.dart';
part 'auth/refresh.dart';
part 'auth/registration.dart';

abstract class AuthModuleBase {
  BackendDatabase get db;
  JwtHelper get jwt;
  void Function(String deviceId, Map<String, dynamic> payload)?
  get notifyDevice;
  DateTime Function() get _now;
  Map<String, _LoginChallenge> get _challenges;
  crypto.Ed25519 get _ed25519;

  /// Server-side audience for signed challenges. When set, it takes
  /// precedence over the client-controlled Host header.
  String? get configuredAudience;

  /// This server's public base URL, used to record `server_address` on
  /// Global-auto-issued invites (empty string if unconfigured).
  String get publicBaseUrl;

  /// True only for the actual Helix Global deployment. Set once at process
  /// startup (see `BackendServer.create`), never toggleable through any
  /// HTTP endpoint - a self-hosted admin token must never be able to flip
  /// this and bypass their own invite-only registration requirement.
  bool get globalInstanceMode;

  /// Delivers OTP codes by real SMS when configured. When
  /// [SmsProvider.isConfigured] is false (no deployment credentials set),
  /// `_requestPhoneOtpHandler` falls back to returning the code directly in
  /// the response instead of calling this - see that handler's doc comment.
  SmsProvider get smsProvider;

  /// Verifies (without consuming) that `code` matches the latest,
  /// unexpired, unconsumed OTP challenge for `phoneHash`. Declared here so
  /// AuthRegistrationHandlers can call into AuthPhoneOtpHandlers' concrete
  /// implementation, mirroring the cross-mixin pattern already used by
  /// `_notifySiblingDevices`/`_serverAudience`.
  ({String? challengeId, String? error}) _verifyPhoneOtp({
    required String phoneHash,
    required String code,
  });

  String _serverAudience(Request request);

  void _notifySiblingDevices(
    String accountId, {
    required String exceptDeviceId,
    required Map<String, dynamic> payload,
  });
}

class AuthModule extends AuthModuleBase
    with
        AuthChallengeLoginHandlers,
        AuthDeviceHandlers,
        AuthInviteHandlers,
        AuthPhoneOtpHandlers,
        AuthProfileHandlers,
        AuthRefreshHandlers,
        AuthRegistrationHandlers {
  @override
  final BackendDatabase db;
  @override
  final JwtHelper jwt;
  @override
  final void Function(String deviceId, Map<String, dynamic> payload)?
  notifyDevice;
  @override
  final DateTime Function() _now;
  @override
  final Map<String, _LoginChallenge> _challenges = {}; // key: "account_id:device_id"
  @override
  final crypto.Ed25519 _ed25519 = crypto.Ed25519();
  @override
  final String? configuredAudience;
  @override
  final String publicBaseUrl;
  @override
  final bool globalInstanceMode;
  @override
  final SmsProvider smsProvider;

  AuthModule(
    this.db,
    this.jwt, {
    this.notifyDevice,
    DateTime Function()? now,
    this.configuredAudience,
    this.publicBaseUrl = '',
    this.globalInstanceMode = false,
    this.smsProvider = const NoopSmsProvider(),
  }) : _now = now ?? DateTime.now;

  Handler get router {
    final router = Router();

    // Public routes
    router.post('/register', _registerHandler);
    router.post('/phone/otp/request', _requestPhoneOtpHandler);
    router.get('/invite/lookup', _lookupInviteHandler);
    router.post('/invite/auto-issue', _autoIssueInviteHandler);
    router.get('/challenge', _challengeHandler);
    router.post('/login', _loginHandler);
    router.post('/refresh', _refreshHandler);

    // Auth routes (enforced by middleware in main, but we can verify here too)
    router.get('/devices', _listDevicesHandler);
    router.post('/devices/rename', _renameDeviceHandler);
    router.get('/devices/security-history', _deviceSecurityHistoryHandler);
    router.post('/devices/link/request', _requestDeviceLinkHandler);
    router.post('/devices/link/request-new', _requestNewDeviceLinkHandler);
    router.post('/devices/link/verify', _verifyDeviceLinkHandler);
    router.post('/devices/link/reject', _rejectDeviceLinkHandler);
    router.post('/devices/link/complete', _completeDeviceLinkHandler);
    router.post('/devices/link/complete-new', _completeNewDeviceLinkHandler);
    router.post('/devices/revoke', _revokeDeviceHandler);
    router.post('/devices/lost-device', _lostDeviceHandler);
    router.put('/devices/push-token', _updatePushTokenHandler);
    router.post('/profile', _updateProfileHandler);
    router.get('/profile', _getProfileHandler);

    return withAppErrorHandling(router.call);
  }

  static String base64UrlEncode(List<int> bytes) => _authBase64UrlEncode(bytes);

  @override
  void _notifySiblingDevices(
    String accountId, {
    required String exceptDeviceId,
    required Map<String, dynamic> payload,
  }) {
    final notifier = notifyDevice;
    if (notifier == null) return;
    for (final device in db.getDevices(accountId)) {
      final deviceId = device['device_id'] as String;
      if (deviceId != exceptDeviceId) {
        notifier(deviceId, payload);
      }
    }
  }
}

String _authBase64UrlEncode(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}
