import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/kernel/crypto.dart';

/// HS256 JWTs over a key ring (`HELIX_JWT_KEYS`): signs with the active
/// key, verifies with any key in the ring, so keys rotate without signing
/// anyone out. Verification fails closed: wrong algorithm, unknown key id,
/// bad signature, wrong issuer, audience or type, missing or past expiry.
final class HmacJwt {
  HmacJwt({required this._keys, required this.activeKid}) {
    if (!_keys.containsKey(activeKid)) {
      throw ArgumentError('active kid not in ring');
    }
  }

  final Map<String, Uint8List> _keys;
  final String activeKid;

  static const issuer = 'helix';

  String sign({
    required String audience,
    required String type,
    required DateTime issuedAt,
    required DateTime expiresAt,
    required Map<String, Object?> claims,
  }) {
    final header = encodeBytes(
      utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT', 'kid': activeKid})),
    );
    final payload = encodeBytes(
      utf8.encode(
        jsonEncode({
          'iss': issuer,
          'aud': audience,
          'typ': type,
          'iat': issuedAt.millisecondsSinceEpoch ~/ 1000,
          // Millisecond issue time, compared with session cut-offs (a
          // sign-out then sign-in within one second must still work).
          'ims': issuedAt.millisecondsSinceEpoch,
          'exp': expiresAt.millisecondsSinceEpoch ~/ 1000,
          ...claims,
        }),
      ),
    );
    final signature = hmacSha256(
      _keys[activeKid]!,
      utf8.encode('$header.$payload'),
    );
    return '$header.$payload.${encodeBytes(signature)}';
  }

  /// The payload of a valid token for [audience] and [type] at [now], or
  /// null.
  Map<String, Object?>? verify(
    String token, {
    required String audience,
    required String type,
    required DateTime now,
  }) {
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
      if (exp is! int || payload['ims'] is! int) return null;
      if (!DateTime.fromMillisecondsSinceEpoch(
        exp * 1000,
        isUtc: true,
      ).isAfter(now)) {
        return null;
      }
      return payload;
    } on Object {
      return null;
    }
  }

  static DateTime issuedAtOf(Map<String, Object?> payload) =>
      DateTime.fromMillisecondsSinceEpoch(payload['ims']! as int, isUtc: true);

  static DateTime expiresAtOf(Map<String, Object?> payload) =>
      DateTime.fromMillisecondsSinceEpoch(
        (payload['exp']! as int) * 1000,
        isUtc: true,
      );
}
