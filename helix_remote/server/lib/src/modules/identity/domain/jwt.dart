import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/identity/domain/secrets.dart';

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

/// HS256 JWTs with a key ring (`HELIX_JWT_KEYS`): signs with the active
/// key, verifies with any key in the ring, so keys rotate without signing
/// anyone out. Verification fails closed: wrong algorithm, unknown key id,
/// bad signature, wrong audience or type, missing or past expiry.
final class JwtCodec {
  JwtCodec({required this._keys, required this.activeKid}) {
    if (!_keys.containsKey(activeKid)) {
      throw ArgumentError('active kid not in ring');
    }
  }

  final Map<String, Uint8List> _keys;
  final String activeKid;

  static const issuer = 'helix';
  static const audience = 'helix.device';
  static const type = 'access';

  String _b64(List<int> bytes) => encodeBytes(bytes);

  String sign(AccessClaims claims) {
    final header = _b64(
      utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT', 'kid': activeKid})),
    );
    final payload = _b64(
      utf8.encode(
        jsonEncode({
          'iss': issuer,
          'aud': audience,
          'typ': type,
          'sub': claims.accountId,
          'dev': claims.deviceId,
          'iat': claims.issuedAt.millisecondsSinceEpoch ~/ 1000,
          // Millisecond issue time, compared with a device's session cut-off
          // (sign-out then sign-in within one second must still work).
          'ims': claims.issuedAt.millisecondsSinceEpoch,
          'exp': claims.expiresAt.millisecondsSinceEpoch ~/ 1000,
        }),
      ),
    );
    final signature = hmacSha256(
      _keys[activeKid]!,
      utf8.encode('$header.$payload'),
    );
    return '$header.$payload.${_b64(signature)}';
  }

  /// The claims of a valid token at [now], or null.
  AccessClaims? verify(String token, DateTime now) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final header =
          jsonDecode(utf8.decode(decodeBytes(parts[0])))
              as Map<String, Object?>;
      if (header['alg'] != 'HS256' || header['typ'] != 'JWT') return null;
      final key = _keys[header['kid']];
      if (key == null) return null;
      final expected = hmacSha256(key, utf8.encode('${parts[0]}.${parts[1]}'));
      if (!constantTimeEquals(expected, decodeBytes(parts[2]))) return null;
      final payload =
          jsonDecode(utf8.decode(decodeBytes(parts[1])))
              as Map<String, Object?>;
      if (payload['iss'] != issuer ||
          payload['aud'] != audience ||
          payload['typ'] != type) {
        return null;
      }
      final exp = payload['exp'];
      final iat = payload['ims'];
      final sub = payload['sub'];
      final dev = payload['dev'];
      if (exp is! int || iat is! int || sub is! String || dev is! String) {
        return null;
      }
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        exp * 1000,
        isUtc: true,
      );
      if (!expiresAt.isAfter(now)) return null;
      return AccessClaims(
        accountId: sub,
        deviceId: dev,
        issuedAt: DateTime.fromMillisecondsSinceEpoch(iat, isUtc: true),
        expiresAt: expiresAt,
      );
    } on Object {
      return null;
    }
  }
}
