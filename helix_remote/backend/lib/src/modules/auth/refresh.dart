part of '../auth.dart';

mixin AuthRefreshHandlers on AuthModuleBase {
  Future<Response> _refreshHandler(Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;

    final refreshToken = body['refresh_token'] as String?;

    if (refreshToken == null) {
      throw AppError.badRequest('Missing refresh_token');
    }

    final claims = jwt.verifyToken(
      refreshToken,
      expect: ExpectedTokenType.refresh,
    );

    if (claims == null) {
      throw AppError.forbidden('Invalid or expired refresh token');
    }

    final accountId = claims['account_id'] as String;

    final deviceId = claims['device_id'] as String;

    if (!db.isDeviceActive(accountId, deviceId)) {
      db.revokeAllRefreshTokensForDevice(accountId, deviceId);

      throw AppError.forbidden('Device revoked');
    }

    if (db.isAccountSuspended(accountId)) {
      throw AppError.forbidden('Account suspended');
    }

    final tokenHash = crypto_pkg.sha256
        .convert(utf8.encode(refreshToken))
        .toString();

    final storedToken = db.getRefreshToken(tokenHash);

    if (storedToken == null) {
      throw AppError.forbidden('Refresh token not recognized');
    }

    if (storedToken['revoked'] == 1) {
      // REPLAY ATTACK! Revoke ALL refresh tokens for this device for safety

      db.revokeAllRefreshTokensForDevice(accountId, deviceId);

      throw AppError.forbidden(
        'Compromised refresh token. All sessions revoked.',
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
  }
}
