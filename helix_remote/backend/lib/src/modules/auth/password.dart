part of '../auth.dart';

/// Password sign-in for a phone-number account.
///
/// The server never sees the password. The app stretches it with Argon2id
/// (salt and cost stored here) into two independent keys:
///
/// - an **auth key**, sent to prove the password, and stored only as a salted
///   SHA-256 - the Argon2id cost has already been paid, so a stolen table
///   still costs an attacker one Argon2id run per guess;
/// - a **wrap key**, never sent, which encrypts the account identity private
///   key. That ciphertext is stored here so a new device that knows the
///   password can unlock the same identity and join alongside the account's
///   other devices instead of replacing them.
mixin AuthPasswordHandlers on AuthModuleBase {
  static const _lockoutThreshold = 5;
  static const _baseLockout = Duration(minutes: 15);
  static const _maxLockout = Duration(hours: 24);

  /// Argon2id cost the app is told to use for a new password. The floor is
  /// OWASP's minimum for Argon2id; set-password refuses anything cheaper.
  static const defaultKdfParams = {
    'alg': 'argon2id',
    'memory_kib': 19456,
    'iterations': 2,
    'parallelism': 1,
    'length': 64,
  };

  Map<String, dynamic>? _authOf(Request request) =>
      request.context['auth'] as Map<String, dynamic>?;

  /// Public: what the app needs before asking for a password - whether the
  /// number has an account, whether it has a password yet, and the salt and
  /// cost to stretch it with. Phone-number discovery already answers "is
  /// this number on Helix", so `account_exists` reveals nothing new; it is
  /// still rate limited per IP.
  Future<Response> _passwordParamsHandler(Request request) async {
    final clientIp = request.context['client_ip'] as String? ?? 'unknown';
    if (!lookupRateLimiter.isAllowed('password_params:$clientIp')) {
      throw AppError.tooManyRequests('Too many attempts');
    }
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final phoneHash = body['phone_hash'] as String?;
    if (phoneHash == null || phoneHash.isEmpty) {
      throw AppError.badRequest('Missing phone_hash');
    }
    if (db.isPhoneHashBlocked(phoneHash)) {
      throw AppError.forbidden(
        'This phone number is blocked',
        code: RemoteErrorCode.phoneBlocked,
      );
    }
    final account = db.getAccountByPhoneHash(phoneHash);
    final accountId = account?['account_id'] as String?;
    final password = accountId == null
        ? null
        : db.getAccountPassword(accountId);
    return _json({
      'account_exists': account != null,
      'has_password': password != null,
      if (password != null) ...{
        'kdf_params': jsonDecode(password['kdf_params'] as String),
        'kdf_salt': password['kdf_salt'],
      },
    });
  }

  /// Public: checks a password without signing anything in, so first-launch
  /// setup can tell the user "wrong password" before it builds a session.
  /// Counts toward the same lockout as a real sign-in.
  Future<Response> _passwordVerifyHandler(Request request) async {
    final clientIp = request.context['client_ip'] as String? ?? 'unknown';
    if (!lookupRateLimiter.isAllowed('password_login:$clientIp')) {
      throw AppError.tooManyRequests('Too many sign-in attempts');
    }
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final phoneHash = body['phone_hash'] as String?;
    final authKey = body['auth_key'] as String?;
    if (phoneHash == null || phoneHash.isEmpty || authKey == null) {
      throw AppError.badRequest('Missing phone_hash or auth_key');
    }
    final accountId = db.getAccountByPhoneHash(phoneHash)?['account_id'];
    final password = accountId is String
        ? db.getAccountPassword(accountId)
        : null;
    if (accountId is! String || password == null) {
      throw AppError.forbidden(
        'Wrong phone number or password',
        code: RemoteErrorCode.passwordIncorrect,
      );
    }
    _checkPasswordAttempt(accountId, password, authKey);
    return _json({'valid': true});
  }

  /// Public: signs a brand-new device in with phone number + password. The
  /// device is registered next to the account's existing devices - nobody
  /// else is signed out - and gets back the wrapped identity key it needs to
  /// publish prekeys as this account.
  Future<Response> _passwordLoginHandler(Request request) async {
    final clientIp = request.context['client_ip'] as String? ?? 'unknown';
    if (!lookupRateLimiter.isAllowed('password_login:$clientIp')) {
      throw AppError.tooManyRequests('Too many sign-in attempts');
    }
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final phoneHash = body['phone_hash'] as String?;
    final authKey = body['auth_key'] as String?;
    final deviceId = body['device_id'] as String?;
    final deviceName = (body['device_name'] as String?)?.trim();
    final signingKey = body['device_signing_public_key'] as String?;
    final agreementKey = body['device_agreement_public_key'] as String?;
    final deviceSignature = body['device_signature'] as String?;
    if (phoneHash == null ||
        phoneHash.isEmpty ||
        authKey == null ||
        deviceId == null ||
        deviceId.isEmpty ||
        deviceId.length > 128 ||
        deviceName == null ||
        deviceName.isEmpty ||
        deviceName.length > 80 ||
        signingKey == null ||
        agreementKey == null ||
        deviceSignature == null) {
      throw AppError.badRequest('Missing password sign-in fields');
    }
    if (!_isValidPublicKey(signingKey, crypto.KeyPairType.ed25519) ||
        !_isValidPublicKey(agreementKey, crypto.KeyPairType.x25519) ||
        signingKey == agreementKey) {
      throw AppError.badRequest('Invalid device public keys');
    }
    if (db.isPhoneHashBlocked(phoneHash)) {
      throw AppError.forbidden(
        'This phone number is blocked',
        code: RemoteErrorCode.phoneBlocked,
      );
    }

    final account = db.getAccountByPhoneHash(phoneHash);
    final accountId = account?['account_id'] as String?;
    final password = accountId == null
        ? null
        : db.getAccountPassword(accountId);
    if (accountId == null || password == null) {
      // Same answer whether the number is unknown or simply has no password,
      // so this endpoint is no better an oracle than the params one.
      throw AppError.forbidden(
        'Wrong phone number or password',
        code: RemoteErrorCode.passwordIncorrect,
      );
    }
    if (account!['status'] == 'BLOCKED' || db.isAccountBlocked(accountId)) {
      throw AppError.forbidden(
        'This account has been blocked',
        code: RemoteErrorCode.accountBlocked,
      );
    }

    _checkPasswordAttempt(accountId, password, authKey);

    final transcript = passwordLoginTranscript(
      phoneHash: phoneHash,
      deviceId: deviceId,
      deviceSigningPublicKey: signingKey,
      deviceAgreementPublicKey: agreementKey,
      deviceName: deviceName,
    );
    if (!await _verifyPasswordLoginSignature(
      transcript,
      deviceSignature,
      signingKey,
    )) {
      throw AppError.forbidden('Device signature verification failed');
    }
    if (db.getDevicesOfDevice(deviceId).isNotEmpty) {
      throw AppError.conflict('Device id is already registered');
    }

    db.registerDevice(
      deviceId,
      accountId,
      signingKey,
      agreementKey,
      deviceName,
    );
    db.logAudit(accountId, deviceId, 'PASSWORD_LOGIN', clientIp, null);
    _announceNewSignIn(
      accountId: accountId,
      newDeviceId: deviceId,
      deviceName: deviceName,
      method: 'password',
    );

    final session = _issueDeviceSession(accountId, deviceId);
    final profile = db.getAccountProfile(accountId);
    return _json({
      'account_id': accountId,
      'device_id': deviceId,
      'account_identity_public_key': password['identity_public_key'],
      'wrapped_identity_key': password['wrapped_identity_key'],
      if (profile != null) 'display_name': profile['display_name'],
      ...session,
    });
  }

  /// Authenticated: whether this account has a password yet. The app keeps
  /// the user on the "create a password" screen until it does.
  Future<Response> _passwordStatusHandler(Request request) async {
    final auth = _authOf(request);
    if (auth == null) {
      throw AppError.unauthorized('Unauthorized');
    }
    final password = db.getAccountPassword(auth['account_id'] as String);
    return _json({
      'has_password': password != null,
      if (password != null) 'updated_at': password['updated_at'],
      'default_kdf_params': defaultKdfParams,
    });
  }

  /// Authenticated: sets the first password, or changes it. Changing needs
  /// proof beyond "this device is signed in": the current password, or - for
  /// someone who forgot it - a fresh SMS code for the account's number. The
  /// identity key stays the same either way, so no device is signed out.
  Future<Response> _setPasswordHandler(Request request) async {
    final auth = _authOf(request);
    if (auth == null) {
      throw AppError.unauthorized('Unauthorized');
    }
    final accountId = auth['account_id'] as String;
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final kdfParams = body['kdf_params'];
    final kdfSalt = body['kdf_salt'] as String?;
    final authKey = body['auth_key'] as String?;
    final wrappedIdentityKey = body['wrapped_identity_key'] as String?;
    if (kdfParams is! Map<String, dynamic> ||
        !_isAcceptableKdf(kdfParams) ||
        kdfSalt == null ||
        !_isBase64UrlOfLength(kdfSalt, min: 16, max: 64) ||
        authKey == null ||
        !_isBase64UrlOfLength(authKey, min: 32, max: 32) ||
        wrappedIdentityKey == null ||
        wrappedIdentityKey.isEmpty ||
        wrappedIdentityKey.length > 2048) {
      throw AppError.badRequest('Invalid password fields');
    }

    final account = db.getAccount(accountId);
    final identityPublicKey = account?['identity_public_key'] as String?;
    if (account == null || identityPublicKey == null) {
      throw AppError.notFound('Account not found');
    }

    final existing = db.getAccountPassword(accountId);
    if (existing != null) {
      final currentAuthKey = body['current_auth_key'] as String?;
      final otpCode = body['otp_code'] as String?;
      if (currentAuthKey != null) {
        _checkPasswordAttempt(accountId, existing, currentAuthKey);
      } else if (otpCode != null) {
        final phoneHash = account['phone_hash'] as String?;
        if (phoneHash == null) {
          throw AppError.forbidden('This account has no phone number');
        }
        final otp = _verifyPhoneOtp(
          phoneHash: phoneHash,
          code: otpCode,
          challengeId: body['otp_challenge_id'] as String?,
        );
        if (otp.error != null) {
          throw AppError.forbidden(
            otp.error!,
            code: RemoteErrorCode.invalidOtp,
          );
        }
        if (otp.challengeId != null) {
          db.markOtpConsumed(otp.challengeId!, _now().millisecondsSinceEpoch);
        }
      } else {
        throw AppError.forbidden(
          'Enter your current password to change it',
          code: RemoteErrorCode.passwordIncorrect,
        );
      }
    }

    final hashSalt = _authBase64UrlEncode(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    db.setAccountPassword(
      accountId: accountId,
      kdfParams: jsonEncode(kdfParams),
      kdfSalt: kdfSalt,
      authHash: _hashAuthKey(authKey, hashSalt),
      authHashSalt: hashSalt,
      wrappedIdentityKey: wrappedIdentityKey,
      identityPublicKey: identityPublicKey,
      now: _now().millisecondsSinceEpoch,
    );
    db.logAudit(
      accountId,
      auth['device_id'] as String?,
      existing == null ? 'PASSWORD_SET' : 'PASSWORD_CHANGED',
      request.context['client_ip'] as String?,
      null,
    );
    return _json({'has_password': true});
  }

  /// Verifies [authKey] against the stored hash, enforcing the lockout.
  /// Throws on a lockout or a wrong key; returns normally on success.
  void _checkPasswordAttempt(
    String accountId,
    Map<String, dynamic> password,
    String authKey,
  ) {
    final now = _now().millisecondsSinceEpoch;
    final lockedUntil = password['locked_until'] as int? ?? 0;
    if (lockedUntil > now) {
      throw AppError(
        'Too many wrong passwords. Try again later.',
        statusCode: 429,
        code: RemoteErrorCode.passwordLocked,
        details: {'locked_until': lockedUntil},
      );
    }
    final expected = password['auth_hash'] as String;
    final actual = _hashAuthKey(authKey, password['auth_hash_salt'] as String);
    if (constantTimeStringEqual(expected, actual)) {
      if ((password['failed_attempts'] as int? ?? 0) > 0) {
        db.clearPasswordFailures(accountId);
      }
      return;
    }
    final failures = (password['failed_attempts'] as int? ?? 0) + 1;
    var nextLock = 0;
    if (failures >= _lockoutThreshold) {
      final doublings = (failures - _lockoutThreshold).clamp(0, 10);
      final lockout = _baseLockout * (1 << doublings);
      nextLock =
          now + (lockout > _maxLockout ? _maxLockout : lockout).inMilliseconds;
    }
    db.recordPasswordFailure(
      accountId,
      failedAttempts: failures,
      lockedUntil: nextLock,
    );
    throw AppError.forbidden(
      'Wrong phone number or password',
      code: RemoteErrorCode.passwordIncorrect,
      details: {
        'attempts_before_lockout': (_lockoutThreshold - failures).clamp(
          0,
          _lockoutThreshold,
        ),
      },
    );
  }

  String _hashAuthKey(String authKey, String salt) => crypto_pkg.sha256
      .convert(utf8.encode('helix.remote.password-auth.v1\n$salt\n$authKey'))
      .toString();

  bool _isAcceptableKdf(Map<String, dynamic> params) {
    final memory = params['memory_kib'];
    final iterations = params['iterations'];
    final parallelism = params['parallelism'];
    final length = params['length'];
    return params['alg'] == 'argon2id' &&
        memory is int &&
        memory >= (defaultKdfParams['memory_kib'] as int) &&
        memory <= 262144 &&
        iterations is int &&
        iterations >= 1 &&
        iterations <= 10 &&
        parallelism is int &&
        parallelism >= 1 &&
        parallelism <= 4 &&
        length == 64;
  }

  bool _isBase64UrlOfLength(
    String value, {
    required int min,
    required int max,
  }) {
    try {
      final bytes = base64Url.decode(base64Url.normalize(value));
      return bytes.length >= min && bytes.length <= max;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _verifyPasswordLoginSignature(
    String message,
    String signatureBase64,
    String publicKeyBase64,
  ) async {
    try {
      final publicKey = crypto.SimplePublicKey(
        base64Url.decode(base64Url.normalize(publicKeyBase64)),
        type: crypto.KeyPairType.ed25519,
      );
      return _ed25519.verify(
        utf8.encode(message),
        signature: crypto.Signature(
          base64Url.decode(base64Url.normalize(signatureBase64)),
          publicKey: publicKey,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Response _json(Map<String, dynamic> body) => Response.ok(
    jsonEncode(body),
    headers: {'Content-Type': 'application/json'},
  );
}

/// What a device signs when it signs in with a password: binds the new
/// device's keys to this phone number so a captured request cannot be
/// replayed with someone else's keys.
String passwordLoginTranscript({
  required String phoneHash,
  required String deviceId,
  required String deviceSigningPublicKey,
  required String deviceAgreementPublicKey,
  required String deviceName,
}) {
  return [
    'helix.remote.password-login.v1',
    phoneHash,
    deviceId,
    deviceSigningPublicKey,
    deviceAgreementPublicKey,
    deviceName,
  ].join('\n');
}
