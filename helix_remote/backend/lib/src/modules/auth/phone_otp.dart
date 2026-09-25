part of '../auth.dart';

mixin AuthPhoneOtpHandlers on AuthModuleBase {
  static const _otpTtl = Duration(minutes: 10);
  static const _otpRequestHourlyLimit = 5;
  static const _otpMaxVerifyAttempts = 5;

  final Map<String, List<int>> _otpRequestAttempts = {};

  /// Issues a short-lived one-time code for a phone number, identified in
  /// the OTP challenge only by its salted hash (see `phone_hash.dart`) — the
  /// server never *stores* a raw phone number. The raw `phone_number` the
  /// client sends is used transiently to deliver the code by real SMS
  /// (BulkSMSBD) and is never persisted; the response omits the code.
  ///
  /// Requires [smsProvider] to be configured. Returns 503 if SMS delivery
  /// is not available — the server never returns the OTP code in the
  /// response body.
  Future<Response> _requestPhoneOtpHandler(Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final phoneHash = body['phone_hash'] as String?;
    if (phoneHash == null || phoneHash.isEmpty) {
      throw AppError.badRequest('Missing phone_hash');
    }

    String? phoneNumber;
    if (smsProvider.isConfigured) {
      phoneNumber = body['phone_number'] as String?;
      if (phoneNumber == null || phoneNumber.isEmpty) {
        // ignore: avoid_print
        print('OTP request rejected: missing phone_number in body');
        throw AppError.badRequest('Missing phone_number');
      }
      final salt = db.getServerConfig(phone_hash.discoverySaltConfigKey);
      final computedHash = salt == null
          ? null
          : phone_hash.phoneHash(salt, phoneNumber);
      if (salt == null || computedHash != phoneHash) {
        // ignore: avoid_print
        print(
          'OTP request rejected: salt_present=${salt != null} '
          'client_hash_prefix=${phoneHash.substring(0, phoneHash.length.clamp(0, 8))} '
          'server_hash_prefix=${computedHash == null ? 'n/a' : computedHash.substring(0, computedHash.length.clamp(0, 8))}',
        );
        // Deliberately distinguishable from a generic bad request: the client's
        // fix is to discard its cached discovery salt, re-fetch it and retry
        // once. Reporting this as a plain 400 leaves the user staring at
        // "check the phone number" for a problem that has nothing to do with
        // the number they typed. This is expected whenever a deployment's salt
        // is re-provisioned (fresh or rotated database).
        throw AppError(
          'The discovery salt on this server has changed. Re-fetch it and retry.',
          statusCode: 400,
          code: RemoteErrorCode.discoverySaltStale,
        );
      }
    }

    if (db.isPhoneHashBlocked(phoneHash)) {
      throw AppError.forbidden('This phone number is blocked');
    }

    if (!_allowOtpRequest(phoneHash)) {
      throw AppError.tooManyRequests('Too many verification code requests');
    }

    final code = _generateOtpCode();
    final now = _now().millisecondsSinceEpoch;
    final challengeId = _generateOtpChallengeId();
    db.createOtpChallenge(
      challengeId: challengeId,
      phoneHash: phoneHash,
      codeHash: _hashOtpCode(code),
      purpose: 'REGISTRATION',
      createdAt: now,
      expiresAt: now + _otpTtl.inMilliseconds,
    );

    if (phoneNumber != null) {
      try {
        await smsProvider.send(
          phoneNumber: phoneNumber,
          message:
              'Your Helix verification code is $code. It expires in '
              '${_otpTtl.inMinutes} minutes.',
        );
      } on Object catch (e) {
        // ignore: avoid_print
        print('OTP SMS delivery failed: $e');
        throw AppError(
          'Failed to send verification SMS: $e',
          statusCode: 502,
          code: RemoteErrorCode.smsDeliveryFailed,
        );
      }
      return Response.ok(
        jsonEncode({
          'challenge_id': challengeId,
          'expires_at': now + _otpTtl.inMilliseconds,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // No SMS provider configured — refuse to issue OTP codes. A deployment
    // must configure BulkSMSBD (or another provider) before phone
    // verification can work. Returning the code in the response was an
    // intentional dev placeholder that must never ship to production.
    throw AppError(
      'SMS delivery is not configured on this server',
      statusCode: 503,
      code: RemoteErrorCode.smsDeliveryFailed,
    );
  }

  /// Verifies an OTP without consuming it. The registration transaction still
  /// performs the authoritative check and consumes the challenge atomically.
  /// This endpoint lets the client reject a bad code before asking the user
  /// to enter a display name, while preserving the one-time challenge model.
  Future<Response> _verifyPhoneOtpHandler(Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final phoneHash = body['phone_hash'] as String?;
    final code = body['otp_code'] as String?;
    final challengeId = body['challenge_id'] as String?;
    if (phoneHash == null ||
        phoneHash.isEmpty ||
        code == null ||
        code.isEmpty) {
      throw AppError.badRequest('Missing phone_hash or otp_code');
    }

    final result = _verifyPhoneOtp(
      phoneHash: phoneHash,
      code: code,
      challengeId: challengeId,
    );
    if (result.error != null) {
      throw AppError.badRequest(
        result.error!,
        code: RemoteErrorCode.invalidOtp,
      );
    }

    return Response.ok(
      jsonEncode({'valid': true, 'challenge_id': result.challengeId}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  String _generateOtpCode() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10).toString()).join();
  }

  String _hashOtpCode(String code) {
    return crypto_pkg.sha256.convert(utf8.encode(code)).toString();
  }

  String _generateOtpChallengeId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return 'otp_${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  bool _allowOtpRequest(String phoneHash) {
    final now = _now().millisecondsSinceEpoch;
    final cutoff = now - const Duration(hours: 1).inMilliseconds;
    final attempts = _otpRequestAttempts.putIfAbsent(phoneHash, () => <int>[]);
    attempts.removeWhere((timestamp) => timestamp < cutoff);
    if (attempts.length >= _otpRequestHourlyLimit) return false;
    attempts.add(now);
    return true;
  }

  /// Verifies (without consuming) that `code` matches the latest,
  /// unexpired, unconsumed OTP challenge for `phoneHash`. Returns the
  /// challenge id on success so the caller can mark it consumed atomically
  /// alongside the rest of registration, or an error message on failure.
  @override
  ({String? challengeId, String? error}) _verifyPhoneOtp({
    required String phoneHash,
    required String code,
    String? challengeId,
  }) {
    final challenge = challengeId == null || challengeId.isEmpty
        ? db.getLatestOtpChallenge(phoneHash)
        : db.getOtpChallenge(challengeId: challengeId, phoneHash: phoneHash);
    if (challenge == null) {
      return (challengeId: null, error: 'No verification code was requested');
    }
    if (challenge['consumed_at'] != null) {
      return (challengeId: null, error: 'Verification code already used');
    }
    final now = _now().millisecondsSinceEpoch;
    if ((challenge['expires_at'] as int) < now) {
      return (challengeId: null, error: 'Verification code expired');
    }
    if ((challenge['attempts'] as int) >= _otpMaxVerifyAttempts) {
      return (challengeId: null, error: 'Too many incorrect attempts');
    }
    if (challenge['code_hash'] != _hashOtpCode(code)) {
      db.incrementOtpAttempts(challenge['challenge_id'] as String);
      return (challengeId: null, error: 'Incorrect verification code');
    }
    return (challengeId: challenge['challenge_id'] as String, error: null);
  }
}
