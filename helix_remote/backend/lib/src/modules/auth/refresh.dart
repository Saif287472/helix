part of '../auth.dart';

mixin AuthRefreshHandlers on AuthModuleBase {
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
}
