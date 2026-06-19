import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class JwtHelper {
  final List<int> _secretBytes;
  final String issuer;
  final String audience;
  final String keyId;
  final DateTime Function() _now;

  JwtHelper(
    String secret, {
    this.issuer = 'helix.remote.backend',
    this.audience = 'helix.remote.clients',
    this.keyId = 'default',
    DateTime Function()? now,
  }) : _secretBytes = utf8.encode(secret),
       _now = now ?? DateTime.now;

  String generateToken(Map<String, dynamic> claims, Duration expiry) {
    final header = base64UrlEncode(
      utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT', 'kid': keyId})),
    );
    final payloadMap = Map<String, dynamic>.from(claims);
    final nowSeconds = (_now().millisecondsSinceEpoch / 1000).round();
    payloadMap['iss'] = issuer;
    payloadMap['aud'] = audience;
    payloadMap['sub'] = payloadMap['sub'] ?? payloadMap['account_id'];
    payloadMap['jti'] = payloadMap['jti'] ?? _randomJti();
    payloadMap['iat'] = nowSeconds;
    payloadMap['nbf'] = nowSeconds;
    payloadMap['exp'] = nowSeconds + expiry.inSeconds;
    payloadMap['token_type'] =
        payloadMap['token_type'] ??
        (payloadMap['refresh'] == true ? 'refresh' : 'access');
    final payload = base64UrlEncode(utf8.encode(jsonEncode(payloadMap)));

    final signature = _sign('$header.$payload');
    return '$header.$payload.$signature';
  }

  Map<String, dynamic>? verifyToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;

    final header = parts[0];
    final payload = parts[1];
    final signature = parts[2];

    final expectedSignature = _sign('$header.$payload');
    if (signature != expectedSignature) return null;

    try {
      final headerJson = utf8.decode(
        base64Url.decode(base64Url.normalize(header)),
      );
      final headerMap = jsonDecode(headerJson) as Map<String, dynamic>;
      if (headerMap['alg'] != 'HS256' || headerMap['kid'] != keyId) {
        return null;
      }

      final payloadJson = utf8.decode(
        base64Url.decode(base64Url.normalize(payload)),
      );
      final payloadMap = jsonDecode(payloadJson) as Map<String, dynamic>;
      if (payloadMap['iss'] != issuer || payloadMap['aud'] != audience) {
        return null;
      }

      final now = (_now().millisecondsSinceEpoch / 1000).round();

      final nbf = payloadMap['nbf'] as int?;
      if (nbf != null && now < nbf) return null;

      final exp = payloadMap['exp'] as int?;
      if (exp != null) {
        if (now > exp) {
          return null; // Expired
        }
      }
      return payloadMap;
    } catch (_) {
      return null;
    }
  }

  String _sign(String input) {
    final hmac = Hmac(sha256, _secretBytes);
    final digest = hmac.convert(utf8.encode(input));
    return base64UrlEncode(digest.bytes);
  }

  String _randomJti() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String base64UrlEncode(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
