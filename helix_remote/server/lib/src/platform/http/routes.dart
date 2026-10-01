import 'dart:async';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/http/idempotency.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

typedef RouteHandler = FutureOr<Response> Function(HelixRequest request);

/// Resolves credentials to principals. The identity module implements the
/// device and admin parts; federation implements [server].
abstract interface class Authenticator {
  /// A valid, unexpired access token of an active device, or null.
  Future<DevicePrincipal?> device(String bearerToken);

  Future<AdminPrincipal?> admin(String bearerToken);

  /// Verifies an S2S signature over [body].
  Future<ServerPrincipal?> server(Request request, Uint8List body);
}

/// Refuses every credential (until the identity module provides one).
final class DenyAllAuthenticator implements Authenticator {
  const DenyAllAuthenticator();

  @override
  Future<DevicePrincipal?> device(String bearerToken) async => null;

  @override
  Future<AdminPrincipal?> admin(String bearerToken) async => null;

  @override
  Future<ServerPrincipal?> server(Request request, Uint8List body) async =>
      null;
}

final class _Registration {
  _Registration({
    required this.module,
    required this.route,
    required this.handler,
    required this.rateLimit,
    required this.maxBodyBytes,
    required this.streamBody,
    required this.allowSuspended,
  });

  final String module;
  final ApiRoute route;
  final RouteHandler handler;
  final RateLimitPolicy? rateLimit;
  final int maxBodyBytes;
  final bool streamBody;
  final bool allowSuspended;
}

/// Where modules declare their routes (ADR-026). Only catalog routes
/// (`Routes.all`) may be registered, by the module that owns them; a public
/// route must name a rate-limit policy.
final class RouteRegistry {
  RouteRegistry({List<ApiRoute>? catalog}) : _catalog = catalog ?? Routes.all;

  final List<ApiRoute> _catalog;
  final Map<String, _Registration> _registrations = {};

  static const defaultMaxBody = 1024 * 1024;

  void add(
    String module,
    ApiRoute route,
    RouteHandler handler, {
    RateLimitPolicy? rateLimit,
    int maxBodyBytes = defaultMaxBody,
    bool streamBody = false,
    bool allowSuspended = false,
  }) {
    final key = route.toString();
    if (!_catalog.any((r) => r.toString() == key)) {
      throw ArgumentError('$route is not in the protocol route catalog');
    }
    if (route.module != module) {
      throw ArgumentError('$route belongs to ${route.module}, not $module');
    }
    if (route.access == RouteAccess.public && rateLimit == null) {
      throw ArgumentError('public route $route needs a rate limit');
    }
    if (_registrations.containsKey(key)) {
      throw ArgumentError('$route registered twice');
    }
    _registrations[key] = _Registration(
      module: module,
      route: route,
      handler: handler,
      rateLimit: rateLimit,
      maxBodyBytes: maxBodyBytes,
      streamBody: streamBody,
      allowSuspended: allowSuspended,
    );
  }

  List<ApiRoute> get registered => [
    for (final r in _registrations.values) r.route,
  ];

  /// Catalog routes owned by [modules] that nobody registered.
  List<ApiRoute> missingFor(Set<String> modules) => [
    for (final route in _catalog)
      if (modules.contains(route.module) &&
          !_registrations.containsKey(route.toString()))
        route,
  ];

  /// Builds the router. Routes with more literal segments are added first so
  /// `/v1/keys/status` wins over `/v1/keys/{account}`.
  Handler build({
    required Authenticator authenticator,
    required RateLimiter rateLimiter,
    required IdempotencyStore idempotency,
  }) {
    final router = Router(
      notFoundHandler: (_) => errorResponse(
        const ApiError(ErrorCode.notFound, message: 'no such route'),
      ),
    );
    final ordered = _registrations.values.toList()
      ..sort((a, b) {
        final bySpecificity = _specificity(
          b.route,
        ).compareTo(_specificity(a.route));
        if (bySpecificity != 0) return bySpecificity;
        // HEAD before GET: shelf_router lets GET routes answer HEAD.
        return (a.route.method == HttpMethod.head ? 0 : 1).compareTo(
          b.route.method == HttpMethod.head ? 0 : 1,
        );
      });
    for (final registration in ordered) {
      router.add(
        registration.route.method.name.toUpperCase(),
        registration.route.path.replaceAllMapped(
          RegExp(r'\{([a-z_]+)\}'),
          (m) => '<${m.group(1)}>',
        ),
        _wrap(registration, authenticator, rateLimiter, idempotency),
      );
    }
    return router.call;
  }

  static int _specificity(ApiRoute route) {
    final segments = route.path.split('/').where((s) => s.isNotEmpty).toList();
    final literal = segments.where((s) => !s.startsWith('{')).length;
    return literal * 100 - segments.length;
  }

  Handler _wrap(
    _Registration registration,
    Authenticator authenticator,
    RateLimiter rateLimiter,
    IdempotencyStore idempotency,
  ) {
    final route = registration.route;
    return (Request request) async {
      final clientIp = request.context[HttpContextKeys.clientIp]! as String;
      final requestId = request.context[HttpContextKeys.requestId]! as String;

      Uint8List? body;
      if (!registration.streamBody &&
          route.method != HttpMethod.get &&
          route.method != HttpMethod.head) {
        body = await _readBody(request, registration.maxBodyBytes);
      }

      final principal = await _authenticate(
        route,
        request,
        body,
        clientIp,
        authenticator,
      );
      if (principal is DevicePrincipal &&
          principal.suspended &&
          !registration.allowSuspended) {
        throw const ApiError(ErrorCode.accountSuspended);
      }

      final policy = registration.rateLimit;
      if (policy != null) {
        final decision = await rateLimiter.hit(policy, principal.key);
        if (!decision.allowed) {
          throw ApiError(
            ErrorCode.rateLimited,
            retryAfter: decision.retryAfter,
          );
        }
      }

      final helixRequest = HelixRequest(
        raw: request,
        route: route,
        principal: principal,
        requestId: requestId,
        clientIp: clientIp,
        params: {
          for (final name in route.parameters)
            name: Uri.decodeComponent(request.params[name] ?? ''),
        },
        body: body,
      );

      final idempotencyKey = request.headers[HelixHeaders.idempotencyKey];
      final mutating =
          route.method != HttpMethod.get && route.method != HttpMethod.head;
      Response response;
      if (mutating &&
          idempotencyKey != null &&
          principal is DevicePrincipal &&
          body != null) {
        response = await _idempotent(
          idempotency,
          principal.key,
          idempotencyKey,
          hashRequest(route.method.name, request.url.path, body),
          () async => registration.handler(helixRequest),
        );
      } else {
        response = await registration.handler(helixRequest);
      }
      return response.change(context: {HttpContextKeys.route: route.path});
    };
  }
}

/// Keys of values the pipeline stores in shelf request/response contexts.
abstract final class HttpContextKeys {
  static const clientIp = 'helix.client_ip';
  static const requestId = 'helix.request_id';
  static const route = 'helix.route';
}

Future<Uint8List> _readBody(Request request, int max) async {
  final declared = request.contentLength;
  if (declared != null && declared > max) {
    throw const ApiError(ErrorCode.payloadTooLarge);
  }
  final builder = BytesBuilder(copy: false);
  await for (final chunk in request.read()) {
    builder.add(chunk);
    if (builder.length > max) throw const ApiError(ErrorCode.payloadTooLarge);
  }
  return builder.toBytes();
}

Future<Principal> _authenticate(
  ApiRoute route,
  Request request,
  Uint8List? body,
  String clientIp,
  Authenticator authenticator,
) async {
  String? bearer() {
    final header = request.headers[HelixHeaders.authorization];
    if (header == null || !header.toLowerCase().startsWith('bearer ')) {
      return null;
    }
    final token = header.substring(7).trim();
    return token.isEmpty ? null : token;
  }

  switch (route.access) {
    case RouteAccess.public:
      return AnonymousPrincipal(clientIp);
    case RouteAccess.device:
      final token = bearer();
      final principal = token == null
          ? null
          : await authenticator.device(token);
      if (principal == null) throw const ApiError(ErrorCode.unauthenticated);
      return principal;
    case RouteAccess.admin:
      final token = bearer();
      final principal = token == null ? null : await authenticator.admin(token);
      if (principal == null) throw const ApiError(ErrorCode.unauthenticated);
      return principal;
    case RouteAccess.s2s:
      final principal = await authenticator.server(
        request,
        body ?? Uint8List(0),
      );
      if (principal == null) throw const ApiError(ErrorCode.unauthenticated);
      return principal;
  }
}

Future<Response> _idempotent(
  IdempotencyStore store,
  String principal,
  String key,
  String requestHash,
  Future<Response> Function() run,
) async {
  if (key.length > 128) {
    throw const ApiError(
      ErrorCode.invalidField,
      message: 'idempotency key too long',
    );
  }
  final stored = await store.find(principal, key);
  if (stored != null) {
    if (stored.requestHash != requestHash) {
      throw const ApiError(ErrorCode.idempotencyConflict);
    }
    return Response(
      stored.status,
      body: stored.body,
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'idempotent-replay': 'true',
      },
    );
  }
  final response = await run();
  if (response.statusCode < 500) {
    final body = await response.readAsString();
    await store.save(
      principal,
      key,
      StoredResponse(
        requestHash: requestHash,
        status: response.statusCode,
        body: body,
      ),
    );
    return Response(response.statusCode, body: body, headers: response.headers);
  }
  return response;
}
