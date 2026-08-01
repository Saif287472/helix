import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/pairing_codes.dart';
import 'package:helix_remote_backend/src/rate_limiter.dart';
import 'package:helix_remote_backend/src/server_identity.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Lets an operator with terminal access to the server mint a fresh admin
/// token while the server keeps running, instead of stopping it to run
/// bin/reset_admin_token.dart.
///
/// `/generate` is gated on the raw TCP peer being loopback - unspoofable,
/// unlike the X-Forwarded-For handling BackendServer._resolveClientIp does
/// for trusted reverse proxies, which is deliberately NOT reused here since
/// that header can be set by anyone. `/redeem` is reachable over the
/// network (the admin app calls it directly, not from the server itself),
/// but only accepts a single-use code that expires after [codeValidity]
/// and is rate-limited per caller, which is what makes its short 16-digit
/// space safe despite being far smaller than the admin token itself.
class AdminPairingModule {
  AdminPairingModule({
    required this.db,
    DateTime Function()? now,
    Duration? codeValidity,
    RateLimiter? redeemRateLimiter,
  }) : _now = now ?? DateTime.now,
       _codeValidity = codeValidity ?? const Duration(minutes: 10),
       _redeemRateLimiter =
           redeemRateLimiter ??
           RateLimiter(maxTokens: 10, refillRatePerSecond: 10 / 600);

  final BackendDatabase db;
  final DateTime Function() _now;
  final Duration _codeValidity;
  final RateLimiter _redeemRateLimiter;

  static final _codePattern = RegExp(r'^[0-9]{16}$');

  Router get router {
    final router = Router();
    router.post('/generate', _generate);
    router.post('/redeem', _redeem);
    return router;
  }

  Response _generate(Request request) {
    final connInfo = request.context['shelf.io.connection_info'];
    final isLoopback =
        connInfo is HttpConnectionInfo && connInfo.remoteAddress.isLoopback;
    if (!isLoopback) {
      return _json({
        'error':
            'This endpoint only accepts connections from the server itself.',
      }, status: 403);
    }

    final code = generatePairingCode();
    final now = _now().millisecondsSinceEpoch;
    db.createAdminPairingCode(
      codeHash: hashPairingCode(code),
      createdAt: now,
      expiresAt: now + _codeValidity.inMilliseconds,
    );

    return Response.ok('$code\n', headers: {'Content-Type': 'text/plain'});
  }

  Future<Response> _redeem(Request request) async {
    final clientIp = request.context['client_ip'] as String? ?? 'unknown';
    if (!_redeemRateLimiter.isAllowed('pairing_redeem:$clientIp')) {
      return _json({
        'error': 'Too many attempts. Please try again later.',
      }, status: 429);
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return _json({'error': 'Malformed request body'}, status: 400);
    }

    final code = body['code'] as String?;
    if (code == null || !_codePattern.hasMatch(code)) {
      return _json({'error': 'Invalid or expired code'}, status: 401);
    }

    final now = _now().millisecondsSinceEpoch;
    final redeemed = db.redeemAdminPairingCode(
      codeHash: hashPairingCode(code),
      now: now,
    );
    if (!redeemed) {
      return _json({'error': 'Invalid or expired code'}, status: 401);
    }

    final identity = await rotateAdminToken(db);
    return _json({'admin_token': identity.adminToken});
  }

  Response _json(Map<String, dynamic> body, {int status = 200}) {
    return Response(
      status,
      body: jsonEncode(body),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
