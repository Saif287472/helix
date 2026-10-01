import 'dart:async';
import 'dart:io';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/observability/log.dart';
import 'package:helix_remote_server/src/platform/observability/metrics.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:shelf/shelf.dart';

/// Outer middleware for every request: request id, client IP, a global
/// per-IP limit, maintenance mode, error mapping, security headers, access
/// log and latency metrics.
final class HttpPipeline {
  HttpPipeline({
    required this.log,
    required Metrics metrics,
    required this.rateLimiter,
    required this.trustedProxies,
    this.globalLimit = const RateLimitPolicy(
      'ip',
      capacity: 600,
      perSecond: 10,
    ),
    this.maintenance,
  }) : _latency = metrics.histogram(
         'helix_http_request_seconds',
         'Request latency by route template and status class',
       );

  final Log log;
  final RateLimiter rateLimiter;
  final Set<String> trustedProxies;
  final RateLimitPolicy globalLimit;

  /// Returns true while the server is in maintenance mode (ops module).
  final Future<bool> Function()? maintenance;
  final Histogram _latency;

  static final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

  Handler wrap(Handler inner) => (Request request) async {
    final watch = Stopwatch()..start();
    final given = request.headers[HelixHeaders.requestId];
    final requestId = given != null && _requestIdPattern.hasMatch(given)
        ? given
        : Uuid.v7();
    final clientIp = _clientIp(request);
    final contextual = request.change(
      context: {
        HttpContextKeys.requestId: requestId,
        HttpContextKeys.clientIp: clientIp,
      },
    );

    Response response;
    String routeTemplate = 'unmatched';
    try {
      final decision = await rateLimiter.hit(globalLimit, clientIp);
      if (!decision.allowed) {
        throw ApiError(ErrorCode.rateLimited, retryAfter: decision.retryAfter);
      }
      if (maintenance != null &&
          !_alwaysAvailable(request.url.path) &&
          await maintenance!()) {
        throw const ApiError(
          ErrorCode.maintenance,
          message: 'The server is in maintenance mode.',
          retryAfter: Duration(minutes: 5),
        );
      }
      response = await inner(contextual);
      routeTemplate =
          response.context[HttpContextKeys.route] as String? ?? routeTemplate;
    } on HijackException {
      // A WebSocket upgrade took over the connection.
      rethrow;
    } on ApiError catch (e) {
      response = errorResponse(e);
    } on ProtocolFormatException catch (e) {
      response = errorResponse(
        ApiError(
          ErrorCode.invalidField,
          message: e.path.isEmpty ? null : 'invalid ${e.path}',
        ),
      );
    } on DbConstraintViolation catch (e) {
      log.warn('constraint_violation', {
        'request_id': requestId,
        'kind': e.kind.name,
      });
      response = errorResponse(const ApiError(ErrorCode.conflict));
    } on Object catch (e, stack) {
      log.error('unhandled_error', {
        'request_id': requestId,
        'error': e.runtimeType.toString(),
        'at': _firstFrame(stack),
      });
      response = errorResponse(const ApiError(ErrorCode.internal));
    }

    watch.stop();
    final status = response.statusCode;
    _latency.observe(watch.elapsedMicroseconds / 1e6, {
      'route': routeTemplate,
      'status': '${status ~/ 100}xx',
    });
    log.info('http', {
      'request_id': requestId,
      'method': request.method,
      'route': routeTemplate,
      'status': status,
      'ms': watch.elapsedMilliseconds,
    });
    return response.change(
      headers: {
        HelixHeaders.requestId: requestId,
        'x-content-type-options': 'nosniff',
        'cache-control': 'no-store',
        'referrer-policy': 'no-referrer',
      },
    );
  };

  bool _alwaysAvailable(String path) =>
      path.startsWith('v1/health') ||
      path.startsWith('v1/admin') ||
      path.startsWith('v1/ops');

  /// The peer address, or the forwarded client address when the peer is a
  /// trusted proxy (Caddy on the same host).
  String _clientIp(Request request) {
    final info = request.context['shelf.io.connection_info'];
    final peer = info is HttpConnectionInfo
        ? info.remoteAddress.address
        : 'unknown';
    if (!trustedProxies.contains(peer)) return peer;
    final realIp = request.headers['x-real-ip'];
    if (realIp != null && realIp.isNotEmpty) return realIp.trim();
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.isNotEmpty) {
      final hops = forwarded
          .split(',')
          .map((h) => h.trim())
          .where((h) => h.isNotEmpty)
          .toList();
      for (final hop in hops.reversed) {
        if (!trustedProxies.contains(hop)) return hop;
      }
    }
    return peer;
  }
}

String _firstFrame(StackTrace stack) {
  final line = stack
      .toString()
      .split('\n')
      .firstWhere(
        (l) => l.contains('package:helix_remote_server'),
        orElse: () => '',
      );
  return line.trim();
}
