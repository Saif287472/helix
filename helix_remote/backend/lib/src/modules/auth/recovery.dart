part of '../auth.dart';

mixin AuthRecoveryHandlers on AuthModuleBase {
  Future<Response> _redeemRecoveryHandler(Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;

    final accountId = body['account_id'] as String?;
    final recoveryCode = body['recovery_code'] as String?;
    final phoneHash = body['phone_hash'] as String?;
    final deviceId = body['device_id'] as String?;
    final deviceSigningPublicKey = body['device_signing_public_key'] as String?;
    final deviceAgreementPublicKey =
        body['device_agreement_public_key'] as String?;
    final deviceName =
        (body['device_name'] as String?)?.trim() ?? 'Recovered Device';

    if (accountId == null ||
        recoveryCode == null ||
        phoneHash == null ||
        deviceId == null ||
        deviceSigningPublicKey == null ||
        deviceAgreementPublicKey == null) {
      throw AppError.badRequest('Missing required fields for account recovery');
    }

    // 1. Verify recovery code in DB
    final recovery = db.getValidRecoveryCodeForAccount(accountId);
    if (recovery == null) {
      throw AppError.unauthorized('Invalid or expired recovery code');
    }

    final salt = recovery['salt'] as String;
    final expectedHash = recovery['code_hash'] as String;
    if (!verifyAdminPassword(recoveryCode, salt, expectedHash)) {
      throw AppError.unauthorized('Invalid or expired recovery code');
    }

    // 2. Verify account exists, is active (or re-activatable), and phoneHash matches
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

    // 3. Mark recovery code redeemed
    db.markRecoveryCodeRedeemed(recovery['recovery_id'] as String);

    // 4. Revoke existing active devices for this account (lost device deactivation)
    final existingDevices = db.getDevices(accountId);
    for (final d in existingDevices) {
      final devId = d['device_id'] as String;
      if (d['status'] != 'REVOKED') {
        db.revokeDevice(accountId, devId);
      }
    }

    // 5. Register the new active device
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
    final accessToken = jwt.generateToken({
      'account_id': accountId,
      'device_id': deviceId,
    }, const Duration(hours: 1));

    final refreshToken = jwt.generateToken({
      'account_id': accountId,
      'device_id': deviceId,
      'refresh': true,
      'jti': Random.secure().nextInt(1000000000).toString(),
    }, const Duration(days: 7));

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

    return Response.ok(
      jsonEncode({
        'account_id': accountId,
        'device_id': deviceId,
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'token_type': 'Bearer',
        'expires_in': 3600,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
