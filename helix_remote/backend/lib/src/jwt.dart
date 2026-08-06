import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:helix_remote_backend/src/constant_time.dart';

/// Which kind of token a caller is willing to accept.
///
/// This is a required argument on [JwtHelper.verifyToken] rather than an
/// optional one on purpose. `verifyToken` used to check the signature, issuer,
/// audience and expiry but *not* the token type, and neither the REST auth
/// middleware nor the WebSocket upgrade checked it either — so a refresh token
/// was accepted anywhere an access token was, turning a 1-hour credential into
/// a 7-day one and letting a stolen refresh token reach every endpoint without
/// ever calling `/accounts/refresh`, which is the only place that would have
/// detected and revoked it. Making the expectation explicit means a new call
/// site cannot inherit that behaviour by omission.
enum ExpectedTokenType {
  access,
  refresh,
  admin;

  String get wireName => switch (this) {
    ExpectedTokenType.access => 'access',
    ExpectedTokenType.refresh => 'refresh',
    ExpectedTokenType.admin => 'admin',
  };
}

class JwtHelper {
  final Map<String, List<int>> _keys;
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
  }) : _keys = {keyId: utf8.encode(secret)},
       _now = now ?? DateTime.now;

  /// Creates a verifier which signs with [keyId] but accepts every key in
  /// [keys]. Keeping retired keys here for the maximum issued-token lifetime
  /// lets an operator rotate credentials without disconnecting every session.
  JwtHelper.keyRing(
    Map<String, String> keys, {
    required this.keyId,
    this.issuer = 'helix.remote.backend',
    this.audience = 'helix.remote.clients',
    DateTime Function()? now,
  }) : assert(keys.isNotEmpty),
       assert(keys.containsKey(keyId)),
       _keys = {
         for (final entry in keys.entries) entry.key: utf8.encode(entry.value),
       },
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

    final signature = _sign('$header.$payload', _keys[keyId]!);
    return '$header.$payload.$signature';
  }

  Map<String, dynamic>? verifyToken(
    String token, {
    required ExpectedTokenType expect,
  }) {
    final parts = token.split('.');
    if (parts.length != 3) return null;

    final header = parts[0];
    final payload = parts[1];
    final signature = parts[2];

    try {
      final headerJson = utf8.decode(
        base64Url.decode(base64Url.normalize(header)),
      );
      final headerMap = jsonDecode(headerJson) as Map<String, dynamic>;
      if (headerMap['alg'] != 'HS256') {
        return null;
      }
      final tokenKeyId = headerMap['kid'];
      if (tokenKeyId is! String) return null;
      final verificationKey = _keys[tokenKeyId];
      if (verificationKey == null) return null;

      final expectedSignature = _sign('$header.$payload', verificationKey);
      // Constant-time: `!=` on String stops at the first differing character,
      // which times how much of a forged signature was correct.
      if (!constantTimeStringEqual(signature, expectedSignature)) return null;

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

      // `exp` is mandatory. It used to be optional, which meant a token
      // without one never expired. `generateToken` always sets it, so no
      // token this server issues is affected - but "absent means eternal" is
      // the wrong way for a validator to fail, and making it explicit costs
      // nothing.
      final exp = payloadMap['exp'] as int?;
      if (exp == null || now > exp) return null;

      // Token type must match what the caller asked for. Both the explicit
      // `token_type` claim and the older boolean `refresh` claim are checked,
      // and they must agree: a token asserting `refresh: true` alongside
      // `token_type: 'access'` is malformed, and the safe reading of a
      // contradiction is to reject it.
      final isRefresh = payloadMap['refresh'] == true;
      final declaredType = payloadMap['token_type'] as String?;
      // Absent `token_type` is treated as a mismatch rather than derived from
      // `refresh`: fail closed, so a token minted before the claim existed
      // cannot slip through unclassified.
      if (declaredType != expect.wireName) return null;
      if (expect == ExpectedTokenType.admin) {
        if (isRefresh || payloadMap['is_admin'] != true) return null;
      } else if (isRefresh != (expect == ExpectedTokenType.refresh)) {
        return null;
      }

      return payloadMap;
    } catch (_) {
      return null;
    }
  }

  String _sign(String input, List<int> secretBytes) {
    final hmac = Hmac(sha256, secretBytes);
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
