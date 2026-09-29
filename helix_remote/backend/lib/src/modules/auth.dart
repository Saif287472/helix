import 'dart:convert';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:helix_remote_backend/src/admin_password.dart';
import 'package:helix_remote_backend/src/app_error.dart';
import 'package:helix_remote_backend/src/constant_time.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/invite_codes.dart';
import 'package:helix_remote_backend/src/jwt.dart';
import 'package:helix_remote_backend/src/phone_hash.dart' as phone_hash;
import 'package:helix_remote_backend/src/rate_limiter.dart';
import 'package:helix_remote_backend/src/reserved_identifiers.dart';
import 'package:helix_remote_backend/src/server_name.dart';
import 'package:helix_remote_backend/src/sms_provider.dart';
import 'package:helix_remote_domain/models.dart';

part 'auth/challenge_login.dart';
part 'auth/devices.dart';
part 'auth/invites.dart';
part 'auth/password.dart';
part 'auth/phone_otp.dart';
part 'auth/profile.dart';
part 'auth/recovery.dart';
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
  RateLimiter get lookupRateLimiter;

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

  /// Delivers OTP codes by real SMS. When [SmsProvider.isConfigured] is
  /// false, `_requestPhoneOtpHandler` refuses the request with a 503.
  SmsProvider get smsProvider;

  /// Verifies (without consuming) that `code` matches the latest,
  /// unexpired, unconsumed OTP challenge for `phoneHash`. Declared here so
  /// AuthRegistrationHandlers can call into AuthPhoneOtpHandlers' concrete
  /// implementation, mirroring the cross-mixin pattern already used by
  /// `_notifySiblingDevices`/`_serverAudience`.
  ({String? challengeId, String? error}) _verifyPhoneOtp({
    required String phoneHash,
    required String code,
    String? challengeId,
  });

  String _serverAudience(Request request);

  bool _isValidPublicKey(String value, crypto.KeyPairType type);

  /// How long an unused refresh token stays valid. Every refresh rotates it
  /// and restarts the clock, so this is really "how long a device may stay
  /// closed before it has to sign in again" - and even then the app signs in
  /// again with its device key, not a new SMS code.
  static const refreshTokenLifetime = Duration(days: 60);
  static const accessTokenLifetime = Duration(hours: 1);

  /// Issues a fresh access + refresh token pair for [deviceId] and records
  /// the refresh token so it can be rotated and revoked. The one place a
  /// device session is minted - login, refresh, device linking and password
  /// sign-in all come through here.
  Map<String, dynamic> _issueDeviceSession(String accountId, String deviceId) {
    final token = jwt.generateToken({
      'account_id': accountId,
      'device_id': deviceId,
    }, accessTokenLifetime);
    final refreshToken = jwt.generateToken({
      'account_id': accountId,
      'device_id': deviceId,
      'refresh': true,
      'jti': _authBase64UrlEncode(
        List<int>.generate(16, (_) => Random.secure().nextInt(256)),
      ),
    }, refreshTokenLifetime);
    final expiresAt = _now().add(refreshTokenLifetime).millisecondsSinceEpoch;
    // Every sign-in and hourly refresh marks the device as recently active,
    // which is what the "your devices" list shows.
    db.updateDeviceLastSeen(accountId, deviceId, _now().millisecondsSinceEpoch);
    db.saveRefreshToken(
      tokenHash: crypto_pkg.sha256
          .convert(utf8.encode(refreshToken))
          .toString(),
      accountId: accountId,
      deviceId: deviceId,
      expiresAt: expiresAt,
    );
    return {
      'token': token,
      'refresh_token': refreshToken,
      'refresh_expires_at': expiresAt,
    };
  }

  /// Refuses a session for a device that is no longer ACTIVE, with the code
  /// the client needs to tell "you were signed out" from "the account is
  /// gone". Also revokes whatever refresh tokens the device still holds.
  void _requireActiveDevice(String accountId, String deviceId) {
    if (db.isDeviceActive(accountId, deviceId)) return;
    db.revokeAllRefreshTokensForDevice(accountId, deviceId);
    if (db.isAccountBlocked(accountId)) {
      throw AppError.forbidden(
        'This account has been blocked',
        code: RemoteErrorCode.accountBlocked,
      );
    }
    throw AppError.forbidden(
      'This device was signed out',
      code: RemoteErrorCode.deviceRevoked,
    );
  }

  /// Tells every other signed-in device of [accountId] that [newDeviceId]
  /// just signed in, so an unexpected sign-in is noticed at once.
  ///
  /// Unlike [_notifySiblingDevices] (realtime only) this is written to each
  /// device's event log, so a phone that is offline sees it when it next
  /// syncs, and it is pushed so a closed app still raises a notification.
  void _announceNewSignIn({
    required String accountId,
    required String newDeviceId,
    required String deviceName,
    required String method,
  }) {
    final now = _now().millisecondsSinceEpoch;
    final payload = {
      'device_id': newDeviceId,
      'device_name': deviceName,
      'method': method,
      'signed_in_at': now,
    };
    for (final device in db.getActiveDevices(accountId)) {
      final targetId = device['device_id'] as String;
      if (targetId == newDeviceId) continue;
      final eventId = 'evt_device_linked_${newDeviceId}_$targetId';
      final sequence = db.writeDeviceEvent(
        eventId: eventId,
        recipientDeviceId: targetId,
        eventType: 'device_linked',
        payload: jsonEncode(payload),
      );
      notifyDevice?.call(targetId, {
        'event_id': eventId,
        'schema_version': 1,
        'timestamp': now,
        'type': 'device_linked',
        'payload': payload,
        'server_sequence': sequence,
      });
      // The push carries no device name: it passes through the push
      // provider, and the app fills in the details once it syncs.
      db.enqueueOutbox(
        'outbox_sign_in_${newDeviceId}_$targetId',
        'PUSH_NOTIFICATION',
        jsonEncode({
          'notification_type': 'new_sign_in',
          'recipient_account_id': accountId,
          'recipient_device_id': targetId,
        }),
      );
    }
  }

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
        AuthPasswordHandlers,
        AuthPhoneOtpHandlers,
        AuthProfileHandlers,
        AuthRecoveryHandlers,
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
  @override
  final RateLimiter lookupRateLimiter;

  AuthModule(
    this.db,
    this.jwt, {
    this.notifyDevice,
    DateTime Function()? now,
    this.configuredAudience,
    this.publicBaseUrl = '',
    this.globalInstanceMode = false,
    this.smsProvider = const NoopSmsProvider(),
    RateLimiter? lookupRateLimiter,
  }) : _now = now ?? DateTime.now,
       lookupRateLimiter =
           lookupRateLimiter ??
           RateLimiter(maxTokens: 60, refillRatePerSecond: 1.0);

  Handler get router {
    final router = Router();

    // Public routes
    router.post('/register', _registerHandler);
    router.post('/phone/otp/request', _requestPhoneOtpHandler);
    router.post('/phone/otp/verify', _verifyPhoneOtpHandler);
    // POST is the current form - it keeps the invite code out of access logs
    // and proxy history. GET is retained for clients predating that change.
    router.post('/invite/lookup', _lookupInviteHandler);
    router.get('/invite/lookup', _lookupInviteHandler);
    router.post('/invite/auto-issue', _autoIssueInviteHandler);
    router.get('/challenge', _challengeHandler);
    router.post('/login', _loginHandler);
    router.post('/refresh', _refreshHandler);
    router.post('/recovery/lookup', _lookupRecoveryHandler);
    router.post('/recovery/redeem', _redeemRecoveryHandler);
    router.post('/password/params', _passwordParamsHandler);
    router.post('/password/login', _passwordLoginHandler);
    router.post('/password/verify', _passwordVerifyHandler);

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
    router.post('/devices/revoke-others', _revokeOtherDevicesHandler);
    router.post('/devices/lost-device', _lostDeviceHandler);
    router.put('/devices/push-token', _updatePushTokenHandler);
    router.post('/profile', _updateProfileHandler);
    router.get('/profile', _getProfileHandler);
    router.get('/password', _passwordStatusHandler);
    router.post('/password', _setPasswordHandler);

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
    for (final device in db.getActiveDevices(accountId)) {
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
