part of '../auth.dart';

mixin AuthPhoneOtpHandlers on AuthModuleBase {
  static const _otpTtl = Duration(minutes: 10);
  static const _otpRequestHourlyLimit = 5;
  static const _otpMaxVerifyAttempts = 5;

  final Map<String, List<int>> _otpRequestAttempts = {};

  /// Issues a short-lived one-time code for a phone number, identified only
  /// by its salted hash (see `phone_hash.dart`) — the server never sees a
  /// raw phone number. There is no real SMS/push delivery yet, so the code
  /// is returned directly in the response; the client is expected to
  /// self-fire a local notification with it. This is an explicit,
  /// documented placeholder, not a secure out-of-band channel.
  Future<Response> _requestPhoneOtpHandler(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final phoneHash = body['phone_hash'] as String?;
      if (phoneHash == null || phoneHash.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing phone_hash'}),
        );
      }

      if (!_allowOtpRequest(phoneHash)) {
        return Response(
          429,
          body: jsonEncode({'error': 'Too many verification code requests'}),
        );
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

      return Response.ok(
        jsonEncode({
          'challenge_id': challengeId,
          'code': code,
          'expires_at': now + _otpTtl.inMilliseconds,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (_) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
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
  }) {
    final challenge = db.getLatestOtpChallenge(phoneHash);
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
