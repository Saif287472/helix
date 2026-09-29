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

    _requireActiveDevice(accountId, deviceId);

    // A suspended account deliberately refreshes normally. Suspension limits
    // what the account may *do* (see the auth middleware), it does not sign
    // the user out - refusing here used to drop them back to onboarding,
    // where they only learned they were suspended after signing in again.

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

    final session = _issueDeviceSession(accountId, deviceId);
    return Response.ok(
      jsonEncode({
        'token': session['token'],
        'refresh_token': session['refresh_token'],
        'refresh_expires_at': session['refresh_expires_at'],
      }),
    );
  }
}
