import 'dart:typed_data';

import 'package:helix_remote_server/src/kernel/jwt.dart';

/// Claims of a device access token.
final class AccessClaims {
  const AccessClaims({
    required this.accountId,
    required this.deviceId,
    required this.issuedAt,
    required this.expiresAt,
  });

  final String accountId;
  final String deviceId;
  final DateTime issuedAt;
  final DateTime expiresAt;
}

/// Device access tokens: [HmacJwt] with audience `helix.device`, type
/// `access`, `sub` = account and `dev` = device.
final class JwtCodec {
  JwtCodec({required Map<String, Uint8List> keys, required String activeKid})
    : _jwt = HmacJwt(keys: keys, activeKid: activeKid);

  final HmacJwt _jwt;

  static const audience = 'helix.device';
  static const type = 'access';

  String sign(AccessClaims claims) => _jwt.sign(
    audience: audience,
    type: type,
    issuedAt: claims.issuedAt,
    expiresAt: claims.expiresAt,
    claims: {'sub': claims.accountId, 'dev': claims.deviceId},
  );

  AccessClaims? verify(String token, DateTime now) {
    final payload = _jwt.verify(
      token,
      audience: audience,
      type: type,
      now: now,
    );
    if (payload == null) return null;
    final sub = payload['sub'];
    final dev = payload['dev'];
    if (sub is! String || dev is! String) return null;
    return AccessClaims(
      accountId: sub,
      deviceId: dev,
      issuedAt: HmacJwt.issuedAtOf(payload),
      expiresAt: HmacJwt.expiresAtOf(payload),
    );
  }
}
