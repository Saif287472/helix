part of '../auth.dart';

/// Recovery codes (`HLX-REC-…`, issued by an administrator) get a user back
/// into an account on a new device.
///
/// The code only says which server and account to use; the phone number must
/// match that account. From there the app signs in normally with the account
/// password when there is one — nothing is reset. Redeeming the code is the
/// fallback for an account without a password (or a forgotten one): it
/// resets the account onto this device and signs every other device out, so
/// it also needs the SMS code whenever this server can send one.
mixin AuthRecoveryHandlers on AuthModuleBase {
  /// Checks a recovery code without using it up, so the app can say "this
  /// code is not valid" on the code page and "this number does not belong to
  /// that account" on the phone page.
  Future<Response> _lookupRecoveryHandler(Request request) async {
    final clientIp = request.context['client_ip'] as String? ?? 'unknown';
    if (!lookupRateLimiter.isAllowed('recovery_lookup:$clientIp')) {
      throw AppError.tooManyRequests('Too many recovery code lookups');
    }
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final accountId = body['account_id'] as String?;
    final recoveryCode = body['recovery_code'] as String?;
    final phoneHash = body['phone_hash'] as String?;
    if (accountId == null ||
        accountId.isEmpty ||
        recoveryCode == null ||
        recoveryCode.isEmpty) {
      throw AppError.badRequest('Missing account_id or recovery_code');
    }

    Response reply(Map<String, dynamic> json) => Response.ok(
      jsonEncode(json),
      headers: {'Content-Type': 'application/json'},
    );

    final recovery = _validRecovery(accountId, recoveryCode);
    final account = recovery == null ? null : db.getAccount(accountId);
    if (recovery == null || account == null) {
      return reply({'valid': false, 'reason': 'invalid'});
    }
    if (account['status'] == 'BLOCKED') {
      return reply({'valid': false, 'reason': 'blocked'});
    }
    return reply({
      'valid': true,
      'server_name': _recoveryServerName(),
      'sms_required': smsProvider.isConfigured,
      if (phoneHash != null && phoneHash.isNotEmpty)
        'phone_matches': account['phone_hash'] == phoneHash,
    });
  }

  Future<Response> _redeemRecoveryHandler(Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;

    final accountId = body['account_id'] as String?;
    final recoveryCode = body['recovery_code'] as String?;
    final phoneHash = body['phone_hash'] as String?;
    final otpCode = body['otp_code'] as String?;
    final otpChallengeId = body['otp_challenge_id'] as String?;
    final deviceId = body['device_id'] as String?;
    final deviceSigningPublicKey = body['device_signing_public_key'] as String?;
    final deviceAgreementPublicKey =
        body['device_agreement_public_key'] as String?;
    final deviceName =
        (body['device_name'] as String?)?.trim() ?? 'Recovered Device';

    if (accountId == null ||
        recoveryCode == null ||
        phoneHash == null ||
        phoneHash.isEmpty ||
        deviceId == null ||
        deviceSigningPublicKey == null ||
        deviceAgreementPublicKey == null) {
      throw AppError.badRequest('Missing required fields for account recovery');
    }

    // 1. The code, then the account it belongs to, then the phone number.
    final recovery = _validRecovery(accountId, recoveryCode);
    if (recovery == null) {
      throw AppError.unauthorized('Invalid or expired recovery code');
    }
    final account = db.getAccount(accountId);
    if (account == null) {
      throw AppError.notFound('Account not found');
    }
    if (account['status'] == 'BLOCKED') {
      throw AppError.forbidden('Account is blocked');
    }
    if (account['phone_hash'] != phoneHash) {
      throw AppError.forbidden('Phone number does not match account');
    }

    // 2. Owning the number. A server that cannot send SMS has only the
    // administrator's code to go on, which is how recovery always worked
    // there.
    String? otpChallengeToConsume;
    if (smsProvider.isConfigured) {
      if (otpCode == null || otpCode.isEmpty) {
        throw AppError.forbidden(
          'Enter the verification code sent to your phone',
          code: RemoteErrorCode.invalidOtp,
        );
      }
      final otp = _verifyPhoneOtp(
        phoneHash: phoneHash,
        code: otpCode,
        challengeId: otpChallengeId,
      );
      if (otp.error != null) {
        throw AppError.forbidden(otp.error!, code: RemoteErrorCode.invalidOtp);
      }
      otpChallengeToConsume = otp.challengeId;
    }

    // 3. Use the code (and the SMS code) up.
    final now = _now().millisecondsSinceEpoch;
    db.markRecoveryCodeRedeemed(recovery['recovery_id'] as String);
    if (otpChallengeToConsume != null) {
      db.markOtpConsumed(otpChallengeToConsume, now);
    }

    // 4. Reset the account onto this device: every other device is signed
    // out, because the account key is about to change under them.
    for (final d in db.getDevices(accountId)) {
      final devId = d['device_id'] as String;
      if (d['status'] != 'REVOKED') {
        db.revokeDevice(accountId, devId);
        db.revokeAllRefreshTokensForDevice(accountId, devId);
      }
    }

    // 5. Register the new active device
    final accountIdentityPublicKey =
        body['account_identity_public_key'] as String?;
    if (accountIdentityPublicKey != null &&
        accountIdentityPublicKey.isNotEmpty) {
      db.updateAccountIdentityKey(accountId, accountIdentityPublicKey);
    }

    db.registerDevice(
      deviceId,
      accountId,
      deviceSigningPublicKey,
      deviceAgreementPublicKey,
      deviceName,
    );

    // If account was suspended, re-activate it
    if (account['status'] == 'SUSPENDED') {
      db.setAccountStatus(accountId, 'ACTIVE');
    }

    // 6. Audit log
    db.logAudit(
      accountId,
      deviceId,
      'USER_ACCOUNT_RECOVERED',
      request.context['client_ip'] as String?,
      request.headers['user-agent'],
    );

    // 7. Issue fresh tokens
    final session = _issueDeviceSession(accountId, deviceId);
    return Response.ok(
      jsonEncode({
        'account_id': accountId,
        'device_id': deviceId,
        'access_token': session['token'],
        'refresh_token': session['refresh_token'],
        'token_type': 'Bearer',
        'expires_in': AuthModuleBase.accessTokenLifetime.inSeconds,
        'display_name': account['username'] ?? '',
        'identity_public_key':
            accountIdentityPublicKey ??
            (account['identity_public_key'] as String? ?? ''),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// The account's current unused recovery code, when [recoveryCode] is it.
  Map<String, dynamic>? _validRecovery(String accountId, String recoveryCode) {
    final recovery = db.getValidRecoveryCodeForAccount(accountId);
    if (recovery == null) return null;
    final ok = verifyAdminPassword(
      recoveryCode,
      recovery['salt'] as String,
      recovery['code_hash'] as String,
    );
    return ok ? recovery : null;
  }

  String _recoveryServerName() {
    final configured = db.getServerConfig(serverNameConfigKey);
    if (configured != null && configured.trim().isNotEmpty) {
      return configured.trim();
    }
    return defaultServerName(db.getServerConfig('server_id') ?? '');
  }
}
