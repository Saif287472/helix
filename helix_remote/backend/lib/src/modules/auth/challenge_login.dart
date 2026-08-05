part of '../auth.dart';

mixin AuthChallengeLoginHandlers on AuthModuleBase {
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

      if (db.isAccountSuspended(accountId)) {
        return Response.forbidden(jsonEncode({'error': 'Account suspended'}));
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
