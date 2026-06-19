import 'dart:convert';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/jwt.dart';

class AuthModule {
  final BackendDatabase db;
  final JwtHelper jwt;
  final void Function(String deviceId, Map<String, dynamic> payload)?
  notifyDevice;
  final DateTime Function() _now;
  final Map<String, _LoginChallenge> _challenges =
      {}; // key: "account_id:device_id"
  final crypto.Ed25519 _ed25519 = crypto.Ed25519();

  AuthModule(this.db, this.jwt, {this.notifyDevice, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  Router get router {
    final router = Router();

    // Public routes
    router.post('/register', _registerHandler);
    router.get('/challenge', _challengeHandler);
    router.post('/login', _loginHandler);
    router.post('/refresh', _refreshHandler);

    // Auth routes (enforced by middleware in main, but we can verify here too)
    router.get('/devices', _listDevicesHandler);
    router.post('/devices/link/request', _requestDeviceLinkHandler);
    router.post('/devices/link/verify', _verifyDeviceLinkHandler);
    router.post('/devices/link/complete', _completeDeviceLinkHandler);
    router.post('/devices/revoke', _revokeDeviceHandler);
    router.post('/devices/lost-device', _lostDeviceHandler);
    router.post('/username', _changeUsernameHandler);

    return router;
  }

  Future<Response> _registerHandler(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final accountId = body['account_id'] as String?;
      final username = body['username'] as String?;
      final registrationVersion = body['registration_version'];
      final identityPublicKey = body['account_identity_public_key'] as String?;
      final deviceId = body['device_id'] as String?;
      final deviceSigningPublicKey =
          body['device_signing_public_key'] as String?;
      final deviceAgreementPublicKey =
          body['device_agreement_public_key'] as String?;
      final accountRegistrationSignature =
          body['account_registration_signature'] as String?;
      final deviceRegistrationSignature =
          body['device_registration_signature'] as String?;
      final deviceName = body['device_name'] as String?;

      if (registrationVersion != 2 ||
          accountId == null ||
          username == null ||
          identityPublicKey == null ||
          deviceId == null ||
          deviceSigningPublicKey == null ||
          deviceAgreementPublicKey == null ||
          accountRegistrationSignature == null ||
          deviceRegistrationSignature == null ||
          deviceName == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing required fields'}),
        );
      }

      final keyValidation = await _validateRegistrationKeys(
        accountId: accountId,
        username: username,
        accountIdentityPublicKey: identityPublicKey,
        deviceId: deviceId,
        deviceSigningPublicKey: deviceSigningPublicKey,
        deviceAgreementPublicKey: deviceAgreementPublicKey,
        deviceName: deviceName,
        accountRegistrationSignature: accountRegistrationSignature,
        deviceRegistrationSignature: deviceRegistrationSignature,
      );
      if (keyValidation != null) {
        return Response.badRequest(body: jsonEncode({'error': keyValidation}));
      }

      final existingAccount = db.getAccount(accountId);
      if (existingAccount == null) {
        db.createAccount(accountId, username, identityPublicKey);
        db.logAudit(
          accountId,
          deviceId,
          'ACCOUNT_REGISTERED',
          request.context['client_ip'] as String?,
          null,
        );
      } else {
        return Response.forbidden(
          jsonEncode({
            'error':
                'Existing accounts must link devices from an active device',
          }),
        );
      }

      db.registerDevice(
        deviceId,
        accountId,
        deviceSigningPublicKey,
        deviceAgreementPublicKey,
        deviceName,
      );
      db.logAudit(
        accountId,
        deviceId,
        'DEVICE_REGISTERED',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(
        jsonEncode({
          'message': 'Registration successful',
          'account_id': accountId,
          'device_id': deviceId,
        }),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<Response> _challengeHandler(Request request) async {
    final params = request.url.queryParameters;
    final accountId = params['account_id'];
    final deviceId = params['device_id'];
    final purpose = params['purpose'] ?? 'login';

    if (accountId == null || deviceId == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing account_id or device_id'}),
      );
    }

    if (purpose.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing purpose'}),
      );
    }

    final key = '$accountId:$deviceId';
    final random = Random.secure();
    final challengeBytes = List<int>.generate(32, (i) => random.nextInt(256));
    final issuedAt = _now();
    final expiresAt = issuedAt.add(const Duration(minutes: 5));
    final challenge = _LoginChallenge(
      accountId: accountId,
      deviceId: deviceId,
      nonce: base64UrlEncode(challengeBytes).replaceAll('=', ''),
      purpose: purpose,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      audience: _serverAudience(request),
    );

    _challenges[key] = challenge;

    return Response.ok(
      jsonEncode({
        'challenge': challenge.signedPayload,
        'purpose': challenge.purpose,
        'expires_at': challenge.expiresAt.millisecondsSinceEpoch,
        'audience': challenge.audience,
      }),
    );
  }

  Future<Response> _loginHandler(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final accountId = body['account_id'] as String?;
      final deviceId = body['device_id'] as String?;
      final signatureBase64 = body['signature'] as String?;
      final purpose = body['purpose'] as String? ?? 'login';

      if (accountId == null || deviceId == null || signatureBase64 == null) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'Missing account_id, device_id, or signature',
          }),
        );
      }

      final key = '$accountId:$deviceId';
      final challenge = _challenges.remove(key);
      if (challenge == null) {
        return Response.forbidden(
          jsonEncode({'error': 'Challenge not found or expired'}),
        );
      }
      if (challenge.accountId != accountId ||
          challenge.deviceId != deviceId ||
          challenge.purpose != purpose ||
          challenge.purpose != 'login' ||
          !_now().isBefore(challenge.expiresAt)) {
        return Response.forbidden(
          jsonEncode({'error': 'Challenge not valid for this login'}),
        );
      }

      // Fetch device public key
      final devices = db.getDevices(accountId);
      final device = devices.firstWhere(
        (d) => d['device_id'] == deviceId,
        orElse: () => <String, dynamic>{},
      );

      if (device.isEmpty) {
        return Response.forbidden(
          jsonEncode({'error': 'Device not registered or inactive'}),
        );
      }

      final devicePubKeyStr = device['device_signing_public_key'] as String;

      // Verify signature
      try {
        final publicKeyBytes = base64Url.decode(
          base64Url.normalize(devicePubKeyStr),
        );
        final publicKey = crypto.SimplePublicKey(
          publicKeyBytes,
          type: crypto.KeyPairType.ed25519,
        );

        final signatureBytes = base64Url.decode(
          base64Url.normalize(signatureBase64),
        );
        final signature = crypto.Signature(
          signatureBytes,
          publicKey: publicKey,
        );

        final isValid = await _ed25519.verify(
          utf8.encode(challenge.signedPayload),
          signature: signature,
        );

        if (!isValid) {
          return Response.forbidden(jsonEncode({'error': 'Invalid signature'}));
        }
      } catch (e) {
        return Response.forbidden(
          jsonEncode({'error': 'Signature verification failed'}),
        );
      }

      // Generate Access Token (1 hour expiry)
      final accessToken = jwt.generateToken({
        'account_id': accountId,
        'device_id': deviceId,
      }, const Duration(hours: 1));

      // Generate Refresh Token (7 days expiry)
      final refreshToken = jwt.generateToken({
        'account_id': accountId,
        'device_id': deviceId,
        'refresh': true,
        'jti': Random.secure().nextInt(1000000000).toString(),
      }, const Duration(days: 7));

      // Hash refresh token and save in database
      final tokenHash = crypto_pkg.sha256
          .convert(utf8.encode(refreshToken))
          .toString();
      final expiresAt = DateTime.now()
          .add(const Duration(days: 7))
          .millisecondsSinceEpoch;
      db.saveRefreshToken(
        tokenHash: tokenHash,
        accountId: accountId,
        deviceId: deviceId,
        expiresAt: expiresAt,
      );

      db.logAudit(
        accountId,
        deviceId,
        'DEVICE_LOGIN',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(
        jsonEncode({
          'token': accessToken,
          'refresh_token': refreshToken,
          'message': 'Login successful',
        }),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<Response> _listDevicesHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    final accountId = auth['account_id'] as String;
    final devices = db.getDevices(accountId);

    return Response.ok(jsonEncode({'devices': devices}));
  }

  Future<Response> _requestDeviceLinkHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final newDeviceId = body['device_id'] as String?;
      final newDevicePublicKey = body['device_public_key'] as String?;
      final newDeviceName = body['device_name'] as String?;

      if (newDeviceId == null ||
          newDevicePublicKey == null ||
          newDeviceName == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing device link fields'}),
        );
      }

      final accountId = auth['account_id'] as String;
      final requesterDeviceId = auth['device_id'] as String;
      if (!db.isDeviceActive(accountId, requesterDeviceId)) {
        return Response.forbidden(jsonEncode({'error': 'Device is inactive'}));
      }
      if (db.getDevicesOfDevice(newDeviceId).isNotEmpty) {
        return Response.forbidden(
          jsonEncode({'error': 'Device id is already registered'}),
        );
      }

      final linkId = _randomToken('link');
      final verificationCode = _humanVerificationCode();
      db.createDeviceLinkRequest(
        linkId: linkId,
        accountId: accountId,
        requestedByDeviceId: requesterDeviceId,
        newDeviceId: newDeviceId,
        newDevicePublicKey: newDevicePublicKey,
        newDeviceName: newDeviceName,
        verificationCodeHash: _hashVerificationCode(verificationCode),
      );
      db.logAudit(
        accountId,
        requesterDeviceId,
        'DEVICE_LINK_REQUESTED',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(
        jsonEncode({
          'link_id': linkId,
          'verification_code': verificationCode,
          'status': 'PENDING',
        }),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<Response> _verifyDeviceLinkHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final linkId = body['link_id'] as String?;
      final verificationCode = body['verification_code'] as String?;
      if (linkId == null || verificationCode == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing link_id or verification_code'}),
        );
      }

      final accountId = auth['account_id'] as String;
      final approved = db.approveDeviceLinkRequest(
        linkId: linkId,
        accountId: accountId,
        verificationCodeHash: _hashVerificationCode(verificationCode),
      );
      if (!approved) {
        return Response.forbidden(
          jsonEncode({'error': 'Device link verification failed'}),
        );
      }

      db.logAudit(
        accountId,
        auth['device_id'] as String?,
        'DEVICE_LINK_VERIFIED',
        request.context['client_ip'] as String?,
        null,
      );
      return Response.ok(jsonEncode({'status': 'APPROVED'}));
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<Response> _completeDeviceLinkHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final linkId = body['link_id'] as String?;
      if (linkId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing link_id'}),
        );
      }

      final accountId = auth['account_id'] as String;
      final link = db.getDeviceLinkRequest(linkId);
      if (link == null ||
          link['account_id'] != accountId ||
          link['status'] != 'APPROVED') {
        return Response.forbidden(
          jsonEncode({'error': 'Device link is not approved'}),
        );
      }

      final newDeviceId = link['new_device_id'] as String;
      db.registerDevice(
        newDeviceId,
        accountId,
        link['new_device_public_key'] as String,
        link['new_device_public_key'] as String,
        link['new_device_name'] as String,
      );
      db.completeDeviceLinkRequest(linkId);
      db.logAudit(
        accountId,
        auth['device_id'] as String?,
        'DEVICE_LINK_COMPLETED',
        request.context['client_ip'] as String?,
        null,
      );

      _notifySiblingDevices(
        accountId,
        exceptDeviceId: newDeviceId,
        payload: {
          'type': 'device_linked',
          'device_id': newDeviceId,
          'device_name': link['new_device_name'],
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );

      return Response.ok(
        jsonEncode({'status': 'LINKED', 'device_id': newDeviceId}),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<Response> _revokeDeviceHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final deviceToRevoke = body['device_id'] as String?;

      if (deviceToRevoke == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing device_id'}),
        );
      }

      final accountId = auth['account_id'] as String;

      db.revokeDevice(accountId, deviceToRevoke);
      db.revokeAllRefreshTokensForDevice(accountId, deviceToRevoke);
      db.recordDeviceRevocation(
        revocationId: _randomToken('rev'),
        accountId: accountId,
        revokedDeviceId: deviceToRevoke,
        revokedByDeviceId: auth['device_id'] as String?,
        reason: 'USER_REVOKED',
      );
      db.logAudit(
        accountId,
        auth['device_id'] as String?,
        'DEVICE_REVOKED',
        request.context['client_ip'] as String?,
        null,
      );
      _notifySiblingDevices(
        accountId,
        exceptDeviceId: deviceToRevoke,
        payload: {
          'type': 'device_revoked',
          'device_id': deviceToRevoke,
          'reason': 'USER_REVOKED',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );

      return Response.ok(
        jsonEncode({'message': 'Device revoked successfully'}),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<Response> _lostDeviceHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final lostDeviceId = body['device_id'] as String?;
      if (lostDeviceId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing device_id'}),
        );
      }

      final accountId = auth['account_id'] as String;
      db.revokeDevice(accountId, lostDeviceId);
      db.revokeAllRefreshTokensForDevice(accountId, lostDeviceId);
      db.deleteMessagesForDevice(lostDeviceId);
      db.recordDeviceRevocation(
        revocationId: _randomToken('rev'),
        accountId: accountId,
        revokedDeviceId: lostDeviceId,
        revokedByDeviceId: auth['device_id'] as String?,
        reason: 'LOST_DEVICE',
      );
      db.logAudit(
        accountId,
        auth['device_id'] as String?,
        'LOST_DEVICE_REPORTED',
        request.context['client_ip'] as String?,
        null,
      );
      _notifySiblingDevices(
        accountId,
        exceptDeviceId: lostDeviceId,
        payload: {
          'type': 'device_revoked',
          'device_id': lostDeviceId,
          'reason': 'LOST_DEVICE',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );

      return Response.ok(
        jsonEncode({
          'message': 'Lost device revoked',
          'device_id': lostDeviceId,
        }),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<Response> _changeUsernameHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final username = body['username'] as String?;
      if (username == null || !_isValidUsername(username)) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid username'}),
        );
      }

      final existing = db.getAccountByUsername(username);
      final accountId = auth['account_id'] as String;
      if (existing != null && existing['account_id'] != accountId) {
        return Response.forbidden(
          jsonEncode({'error': 'Username is not available'}),
        );
      }

      db.updateUsername(accountId, username);
      db.logAudit(
        accountId,
        auth['device_id'] as String?,
        'USERNAME_CHANGED',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(
        jsonEncode({'message': 'Username changed', 'username': username}),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  bool _isValidUsername(String username) {
    if (username.length < 3 || username.length > 30) return false;
    if (username.startsWith('helix_')) return false;
    return RegExp(r'^[a-z0-9_]+$').hasMatch(username);
  }

  static String base64UrlEncode(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _randomToken(String prefix) {
    final random = Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    return '${prefix}_${base64UrlEncode(bytes)}';
  }

  String _humanVerificationCode() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10).toString()).join();
  }

  String _hashVerificationCode(String code) {
    return crypto_pkg.sha256.convert(utf8.encode(code)).toString();
  }

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

  Future<Response> _refreshHandler(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final refreshToken = body['refresh_token'] as String?;
      if (refreshToken == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing refresh_token'}),
        );
      }

      final claims = jwt.verifyToken(refreshToken);
      if (claims == null || claims['refresh'] != true) {
        return Response.forbidden(
          jsonEncode({'error': 'Invalid or expired refresh token'}),
        );
      }

      final accountId = claims['account_id'] as String;
      final deviceId = claims['device_id'] as String;
      if (!db.isDeviceActive(accountId, deviceId)) {
        db.revokeAllRefreshTokensForDevice(accountId, deviceId);
        return Response.forbidden(jsonEncode({'error': 'Device revoked'}));
      }

      final tokenHash = crypto_pkg.sha256
          .convert(utf8.encode(refreshToken))
          .toString();
      final storedToken = db.getRefreshToken(tokenHash);

      if (storedToken == null) {
        return Response.forbidden(
          jsonEncode({'error': 'Refresh token not recognized'}),
        );
      }

      if (storedToken['revoked'] == 1) {
        // REPLAY ATTACK! Revoke ALL refresh tokens for this device for safety
        db.revokeAllRefreshTokensForDevice(accountId, deviceId);
        return Response.forbidden(
          jsonEncode({
            'error': 'Compromised refresh token. All sessions revoked.',
          }),
        );
      }

      // Revoke the used token (rotation)
      db.revokeRefreshToken(tokenHash);

      // Generate new pair
      final newAccessToken = jwt.generateToken({
        'account_id': accountId,
        'device_id': deviceId,
      }, const Duration(hours: 1));

      final newRefreshToken = jwt.generateToken({
        'account_id': accountId,
        'device_id': deviceId,
        'refresh': true,
        'jti': Random.secure().nextInt(1000000000).toString(),
      }, const Duration(days: 7));

      final newTokenHash = crypto_pkg.sha256
          .convert(utf8.encode(newRefreshToken))
          .toString();
      final expiresAt = DateTime.now()
          .add(const Duration(days: 7))
          .millisecondsSinceEpoch;

      db.saveRefreshToken(
        tokenHash: newTokenHash,
        accountId: accountId,
        deviceId: deviceId,
        expiresAt: expiresAt,
      );

      return Response.ok(
        jsonEncode({'token': newAccessToken, 'refresh_token': newRefreshToken}),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<String?> _validateRegistrationKeys({
    required String accountId,
    required String username,
    required String accountIdentityPublicKey,
    required String deviceId,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
    required String deviceName,
    required String accountRegistrationSignature,
    required String deviceRegistrationSignature,
  }) async {
    final accountKey = _decodePublicKey(accountIdentityPublicKey);
    final signingKey = _decodePublicKey(deviceSigningPublicKey);
    final agreementKey = _decodePublicKey(deviceAgreementPublicKey);
    if (accountKey == null) return 'Invalid account identity key';
    if (signingKey == null) return 'Invalid device signing key';
    if (agreementKey == null) return 'Invalid device agreement key';
    if (deviceSigningPublicKey == deviceAgreementPublicKey) {
      return 'Device signing and agreement keys must be distinct';
    }

    final transcript = _registrationTranscript(
      accountId: accountId,
      username: username,
      accountIdentityPublicKey: accountIdentityPublicKey,
      deviceId: deviceId,
      deviceSigningPublicKey: deviceSigningPublicKey,
      deviceAgreementPublicKey: deviceAgreementPublicKey,
      deviceName: deviceName,
    );
    final accountOk = await _verifyEd25519(
      publicKeyBytes: accountKey,
      signedPayload: transcript,
      signatureBase64: accountRegistrationSignature,
    );
    if (!accountOk) return 'Invalid account registration signature';
    final deviceOk = await _verifyEd25519(
      publicKeyBytes: signingKey,
      signedPayload: transcript,
      signatureBase64: deviceRegistrationSignature,
    );
    if (!deviceOk) return 'Invalid device registration signature';
    return null;
  }

  List<int>? _decodePublicKey(String value) {
    try {
      final bytes = base64Url.decode(base64Url.normalize(value));
      return bytes.length == 32 ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _verifyEd25519({
    required List<int> publicKeyBytes,
    required String signedPayload,
    required String signatureBase64,
  }) async {
    try {
      final publicKey = crypto.SimplePublicKey(
        publicKeyBytes,
        type: crypto.KeyPairType.ed25519,
      );
      final signatureBytes = base64Url.decode(
        base64Url.normalize(signatureBase64),
      );
      return _ed25519.verify(
        utf8.encode(signedPayload),
        signature: crypto.Signature(signatureBytes, publicKey: publicKey),
      );
    } catch (_) {
      return false;
    }
  }

  String _registrationTranscript({
    required String accountId,
    required String username,
    required String accountIdentityPublicKey,
    required String deviceId,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
    required String deviceName,
  }) {
    return [
      'helix.remote.registration.v2',
      accountId,
      username,
      accountIdentityPublicKey,
      deviceId,
      deviceSigningPublicKey,
      deviceAgreementPublicKey,
      deviceName,
    ].join('\n');
  }

  String _serverAudience(Request request) {
    final host = request.requestedUri.host;
    final port = request.requestedUri.hasPort
        ? ':${request.requestedUri.port}'
        : '';
    return host.isEmpty ? 'helix_remote_backend' : '$host$port';
  }
}

class _LoginChallenge {
  _LoginChallenge({
    required this.accountId,
    required this.deviceId,
    required this.nonce,
    required this.purpose,
    required this.issuedAt,
    required this.expiresAt,
    required this.audience,
  });

  final String accountId;
  final String deviceId;
  final String nonce;
  final String purpose;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String audience;

  String get signedPayload {
    final payload = {
      'version': 1,
      'account_id': accountId,
      'device_id': deviceId,
      'nonce': nonce,
      'purpose': purpose,
      'issued_at': issuedAt.millisecondsSinceEpoch,
      'expires_at': expiresAt.millisecondsSinceEpoch,
      'audience': audience,
    };
    return base64UrlEncode(
      utf8.encode(jsonEncode(payload)),
    ).replaceAll('=', '');
  }
}
