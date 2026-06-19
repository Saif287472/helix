import 'dart:convert';
import 'package:crypto/crypto.dart';

class JwtHelper {
  final List<int> _secretBytes;

  JwtHelper(String secret) : _secretBytes = utf8.encode(secret);

  String generateToken(Map<String, dynamic> claims, Duration expiry) {
    final header = base64UrlEncode(
      utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})),
    );
    final payloadMap = Map<String, dynamic>.from(claims);
    payloadMap['exp'] =
        (DateTime.now().add(expiry).millisecondsSinceEpoch / 1000).round();
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
      final payloadJson = utf8.decode(
        base64Url.decode(base64Url.normalize(payload)),
      );
      final payloadMap = jsonDecode(payloadJson) as Map<String, dynamic>;

      final exp = payloadMap['exp'] as int?;
      if (exp != null) {
        final now = (DateTime.now().millisecondsSinceEpoch / 1000).round();
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

  static String base64UrlEncode(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
