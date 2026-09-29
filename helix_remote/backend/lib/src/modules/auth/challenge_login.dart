part of '../auth.dart';

mixin AuthChallengeLoginHandlers on AuthModuleBase {
  Future<Response> _challengeHandler(Request request) async {
    final params = request.url.queryParameters;
    final accountId = params['account_id'];
    final deviceId = params['device_id'];
    final purpose = params['purpose'] ?? 'login';

    if (accountId == null || deviceId == null) {
      throw AppError.badRequest('Missing account_id or device_id');
    }

    if (purpose.isEmpty) {
      throw AppError.badRequest('Missing purpose');
    }

    final key = '$accountId:$deviceId';
    final random = Random.secure();
    final challengeBytes = List<int>.generate(32, (i) => random.nextInt(256));
    final issuedAt = _now();
    final expiresAt = issuedAt.add(const Duration(minutes: 5));

    // Evict expired challenges to prevent unbounded memory growth
    _challenges.removeWhere((_, c) => issuedAt.isAfter(c.expiresAt));

    // Hard ceiling on active unconsumed challenges
    if (_challenges.length >= 10000) {
      throw AppError.tooManyRequests('Too many pending login challenges');
    }

    final challenge = _LoginChallenge(
      accountId: accountId,
      deviceId: deviceId,
      nonce: _authBase64UrlEncode(challengeBytes),
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
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final accountId = body['account_id'] as String?;
    final deviceId = body['device_id'] as String?;
    final signatureBase64 = body['signature'] as String?;
    final purpose = body['purpose'] as String? ?? 'login';

    if (accountId == null || deviceId == null || signatureBase64 == null) {
      throw AppError.badRequest('Missing account_id, device_id, or signature');
    }

    final key = '$accountId:$deviceId';
    final challenge = _challenges.remove(key);
    if (challenge == null) {
      throw AppError.forbidden('Challenge not found or expired');
    }
    if (challenge.accountId != accountId ||
        challenge.deviceId != deviceId ||
        challenge.purpose != purpose ||
        challenge.purpose != 'login' ||
        !_now().isBefore(challenge.expiresAt)) {
      throw AppError.forbidden('Challenge not valid for this login');
    }

    // Fetch device public key
    final devices = db.getDevices(accountId);
    final device = devices.firstWhere(
      (d) => d['device_id'] == deviceId,
      orElse: () => <String, dynamic>{},
    );

    if (device.isEmpty) {
      throw AppError.forbidden(
        'Device not registered',
        code: RemoteErrorCode.deviceRevoked,
      );
    }
    // getDevices includes REVOKED rows. A revoked device used to be handed a
    // token here that the auth middleware then refused on first use; the app
    // re-signs in with its device key after a failed refresh, so it must learn
    // here, once, that the device is gone.
    _requireActiveDevice(accountId, deviceId);

    // Suspended accounts sign in normally and are then limited by the auth
    // middleware, so the app can show why instead of failing the login.

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
      final signature = crypto.Signature(signatureBytes, publicKey: publicKey);

      final isValid = await _ed25519.verify(
        utf8.encode(challenge.signedPayload),
        signature: signature,
      );

      if (!isValid) {
        throw AppError.forbidden('Invalid signature');
      }
    } catch (e) {
      throw AppError.forbidden('Signature verification failed');
    }

    final session = _issueDeviceSession(accountId, deviceId);

    db.logAudit(
      accountId,
      deviceId,
      'DEVICE_LOGIN',
      request.context['client_ip'] as String?,
      null,
    );

    return Response.ok(jsonEncode({...session, 'message': 'Login successful'}));
  }

  @override
  String _serverAudience(Request request) {
    // Prefer the server-side configured audience: the Host header is
    // client-controlled and must not define the audience of signed challenges.
    final configured = configuredAudience;
    if (configured != null && configured.isNotEmpty) {
      return configured;
    }
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
