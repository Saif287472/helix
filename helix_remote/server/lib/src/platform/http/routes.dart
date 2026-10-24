import 'dart:async';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/clock.dart';
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

/// A bearer token a route accepts besides its access class (the ops metrics
/// token). Returns the principal, or null to fall back to normal checks.
typedef ExtraBearer = Future<Principal?> Function(String bearerToken);

final class _Registration {
  _Registration({
    required this.module,
    required this.route,
    required this.handler,
    required this.rateLimit,
    required this.maxBodyBytes,
    required this.streamBody,
    required this.allowSuspended,
    required this.extraBearer,
    required this.trailingSlash,
  });

  final String module;
  final ApiRoute route;
  final RouteHandler handler;
  final RateLimitPolicy? rateLimit;
  final int maxBodyBytes;
  final bool streamBody;
  final bool allowSuspended;
  final ExtraBearer? extraBearer;
  final bool trailingSlash;
}

/// Request body bytes buffered at once on this node, across all requests
/// (S7 #1). A body that does not fit does not wait: the request gets
/// `unavailable` (503, retry soon), so parallel large uploads cannot run the
/// node out of memory.
///
/// A reservation is only worth having if it is returned, so a read is bounded
/// by [idleGap] between two chunks and by [deadline] end to end: a client that
/// declares 256 KiB and sends nothing held its slice of the node-wide budget
/// until the operating system dropped the socket, which is hours (AUD-1a-1).
final class BodyBudget {
  BodyBudget(
    this.maxBytes, {
    this.idleGap = const Duration(seconds: 10),
    this.deadline = const Duration(seconds: 30),
  });

  final int maxBytes;

  /// How long a buffered body may go without another chunk.
  final Duration idleGap;

  /// How long a buffered body may take in total, however steadily it arrives.
  final Duration deadline;

  int _inFlight = 0;

  int get inFlight => _inFlight;

  bool _reserve(int bytes) {
    if (_inFlight + bytes > maxBytes) return false;
    _inFlight += bytes;
    return true;
  }

  void _release(int bytes) => _inFlight -= bytes;
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
    ExtraBearer? extraBearer,
    bool trailingSlash = false,
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
    if (extraBearer != null &&
        route.access != RouteAccess.device &&
        route.access != RouteAccess.admin) {
      throw ArgumentError('$route: only bearer routes take an extra token');
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
      extraBearer: extraBearer,
      trailingSlash: trailingSlash,
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
  /// `/v1/keys/status` wins over `/v1/keys/{account}`, ties are settled per
  /// segment from the left, and two templates that could only ever answer the
  /// same requests stop the node rather than decide by chance.
  Handler build({
    required Authenticator authenticator,
    required RateLimiter rateLimiter,
    required IdempotencyStore idempotency,
    BodyBudget? bodyBudget,
    Clock clock = const SystemClock(),
  }) {
    final router = Router(
      notFoundHandler: (_) => errorResponse(
        const ApiError(ErrorCode.notFound, message: 'no such route'),
      ),
    );
    final budget = bodyBudget ?? BodyBudget(256 * 1024 * 1024);
    final ambiguous = ambiguousPairs(_registrations.values.map((r) => r.route));
    if (ambiguous.isNotEmpty) {
      throw StateError(
        'these route pairs match the same requests and only the order they '
        'were added in decides which one answers: $ambiguous',
      );
    }
    final ordered = _registrations.values.toList()
      ..sort((a, b) {
        final bySpecificity = _specificity(
          b.route,
        ).compareTo(_specificity(a.route));
        if (bySpecificity != 0) return bySpecificity;
        // Ties are settled per segment, left to right, then by the path and
        // the method name: no two orders of the same catalog may answer the
        // same request differently.
        final byTemplate = _compareTemplates(a.route.path, b.route.path);
        if (byTemplate != 0) return byTemplate;
        // HEAD before GET: shelf_router lets GET routes answer HEAD.
        return (a.route.method == HttpMethod.head ? 0 : 1).compareTo(
          b.route.method == HttpMethod.head ? 0 : 1,
        );
      });
    for (final registration in ordered) {
      final path = registration.route.path.replaceAllMapped(
        RegExp(r'\{([a-z_]+)\}'),
        (m) => '<${m.group(1)}>',
      );
      final handler = _wrap(
        registration,
        authenticator,
        rateLimiter,
        idempotency,
        budget,
        clock,
      );
      final method = registration.route.method.name.toUpperCase();
      router.add(method, path, handler);
      // Exactly `path` and `path/`, never anything below it.
      if (registration.trailingSlash) router.add(method, '$path/', handler);
    }
    return router.call;
  }

  static int _specificity(ApiRoute route) {
    final segments = _segments(route.path);
    final literal = segments.where((s) => !s.startsWith('{')).length;
    return literal * 100 - segments.length;
  }

  static List<String> _segments(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList();

  /// Order between two templates [_specificity] cannot separate: the one that
  /// is literal sooner, then the one whose literal is earlier in the alphabet.
  /// A total order, so the router's answer never depends on the order the
  /// modules registered in.
  static int _compareTemplates(String left, String right) {
    final a = _segments(left);
    final b = _segments(right);
    for (var i = 0; i < a.length && i < b.length; i++) {
      final aParameter = a[i].startsWith('{');
      final bParameter = b[i].startsWith('{');
      if (aParameter != bParameter) return aParameter ? 1 : -1;
      if (!aParameter) {
        final byLiteral = a[i].compareTo(b[i]);
        if (byLiteral != 0) return byLiteral;
      }
    }
    return b.length.compareTo(a.length);
  }

  /// Templates of one method that can answer exactly the same requests, which
  /// means they differ only in what their parameters are called. Whichever is
  /// added second is unreachable, so this is a bug in the catalog, not a
  /// question of order: [_compareTemplates] ranks them equal by design.
  static List<String> ambiguousPairs(Iterable<ApiRoute> routes) {
    final byShape = <String, List<ApiRoute>>{};
    for (final route in routes) {
      final shape =
          '${route.method.name} '
          '${_segments(route.path).map((s) => s.startsWith('{') ? '{}' : s).join('/')}';
      byShape.putIfAbsent(shape, () => []).add(route);
    }
    return [
      for (final group in byShape.values)
        if (group.length > 1)
          for (var i = 0; i < group.length; i++)
            for (var j = i + 1; j < group.length; j++)
              '${group[i]} and ${group[j]}',
    ];
  }

  /// Order (S7): credentials, then the route's rate limit, and only then the
  /// body, so an unauthenticated caller never makes the node buffer a large
  /// upload. S2S signatures cover the body, so S2S routes check the
  /// signature headers' shape and clock skew before reading and verify the
  /// signature after.
  Handler _wrap(
    _Registration registration,
    Authenticator authenticator,
    RateLimiter rateLimiter,
    IdempotencyStore idempotency,
    BodyBudget budget,
    Clock clock,
  ) {
    final route = registration.route;
    final hasBody =
        !registration.streamBody &&
        route.method != HttpMethod.get &&
        route.method != HttpMethod.head;
    return (Request request) async {
      final clientIp = request.context[HttpContextKeys.clientIp]! as String;
      final requestId = request.context[HttpContextKeys.requestId]! as String;

      Future<void> limit(Principal principal) async {
        final policy = registration.rateLimit;
        if (policy == null) return;
        final decision = await rateLimiter.hit(policy, principal.key);
        if (!decision.allowed) {
          throw ApiError(
            ErrorCode.rateLimited,
            retryAfter: decision.retryAfter,
          );
        }
      }

      final params = <String, String>{};
      for (final name in route.parameters) {
        try {
          // shelf_router matches `request.url.path`, which Dart hands over
          // still percent-encoded, so this is the one decode a path parameter
          // gets: `%252F` arrives as `%2F`, never as a `/` that would smuggle a
          // segment past a handler's own one-segment check, and a name holding
          // a literal `%` (sent as `%25`) stays addressable.
          params[name] = Uri.decodeComponent(request.params[name] ?? '');
        } on Object {
          // Malformed escapes (ArgumentError) or bytes that are not UTF-8
          // (FormatException).
          throw ApiError(
            ErrorCode.badRequest,
            message: 'malformed $name in the path',
          );
        }
      }

      var reserved = 0;
      try {
        Uint8List? body;
        final Principal principal;
        if (route.access == RouteAccess.s2s) {
          _checkS2SHeaders(request, clock);
          if (hasBody) {
            (body, reserved) = await _readBody(
              request,
              registration.maxBodyBytes,
              budget,
            );
          }
          principal =
              await authenticator.server(request, body ?? Uint8List(0)) ??
              (throw const ApiError(ErrorCode.unauthenticated));
          await limit(principal);
        } else {
          principal = await _authenticate(
            route,
            request,
            clientIp,
            authenticator,
            registration.extraBearer,
          );
          if (principal is DevicePrincipal &&
              principal.suspended &&
              !registration.allowSuspended) {
            throw const ApiError(ErrorCode.accountSuspended);
          }
          await limit(principal);
          if (hasBody) {
            (body, reserved) = await _readBody(
              request,
              registration.maxBodyBytes,
              budget,
            );
          }
        }

        final helixRequest = HelixRequest(
          raw: request,
          route: route,
          principal: principal,
          requestId: requestId,
          clientIp: clientIp,
          params: params,
          body: body,
        );

        final idempotencyKey = request.headers[HelixHeaders.idempotencyKey];
        Response response;
        if (hasBody &&
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
      } finally {
        budget._release(reserved);
      }
    };
  }
}

/// Keys of values the pipeline stores in shelf request/response contexts.
abstract final class HttpContextKeys {
  static const clientIp = 'helix.client_ip';
  static const requestId = 'helix.request_id';
  static const route = 'helix.route';
}

/// Reads the body within the route's [max] and the node's [budget]; returns
/// it with the bytes reserved, which the caller releases when the request
/// ends.
Future<(Uint8List, int)> _readBody(
  Request request,
  int max,
  BodyBudget budget,
) async {
  final declared = request.contentLength;
  if (declared != null && declared > max) {
    throw const ApiError(ErrorCode.payloadTooLarge);
  }
  const busy = ApiError(
    ErrorCode.unavailable,
    message: 'the server is busy, retry shortly',
    retryAfter: Duration(seconds: 2),
  );
  const stalled = ApiError(
    ErrorCode.requestTimeout,
    message: 'the request body stopped arriving',
  );
  var reserved = 0;
  if (declared != null) {
    if (!budget._reserve(declared)) throw busy;
    reserved = declared;
  }
  try {
    final builder = BytesBuilder(copy: false);
    final started = Stopwatch()..start();
    await for (final chunk in request.read().timeout(budget.idleGap)) {
      if (started.elapsed > budget.deadline) throw stalled;
      builder.add(chunk);
      if (builder.length > max) {
        throw const ApiError(ErrorCode.payloadTooLarge);
      }
      if (builder.length > reserved) {
        final more = builder.length - reserved;
        if (!budget._reserve(more)) throw busy;
        reserved += more;
      }
    }
    return (builder.toBytes(), reserved);
  } on Object catch (failure) {
    budget._release(reserved);
    throw failure is TimeoutException ? stalled : failure;
  }
}

/// The S2S checks that need no body: all three headers present and well
/// formed, a valid domain, and a timestamp within [s2sMaxSkew]. The
/// signature itself (over the body hash) is verified after reading.
void _checkS2SHeaders(Request request, Clock clock) {
  const refused = ApiError(ErrorCode.unauthenticated);
  final server = request.headers[HelixHeaders.s2sServer]?.toLowerCase();
  final ts = int.tryParse(request.headers[HelixHeaders.s2sTimestamp] ?? '');
  final signature = request.headers[HelixHeaders.s2sSignature];
  if (server == null ||
      ts == null ||
      signature == null ||
      !AccountAddress.isValidDomain(server) ||
      // 64 bytes, unpadded base64url.
      signature.length != 86) {
    throw refused;
  }
  final skew = clock.now().millisecondsSinceEpoch - ts;
  if (skew.abs() > s2sMaxSkew.inMilliseconds) throw refused;
}

Future<Principal> _authenticate(
  ApiRoute route,
  Request request,
  String clientIp,
  Authenticator authenticator,
  ExtraBearer? extraBearer,
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
    case RouteAccess.admin:
      final token = bearer();
      if (token == null) throw const ApiError(ErrorCode.unauthenticated);
      final extra = extraBearer == null ? null : await extraBearer(token);
      if (extra != null) return extra;
      final principal = route.access == RouteAccess.device
          ? await authenticator.device(token)
          : await authenticator.admin(token);
      if (principal == null) throw const ApiError(ErrorCode.unauthenticated);
      return principal;
    case RouteAccess.s2s:
      throw StateError('S2S routes authenticate after reading the body');
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
  final claim = await store.claim(principal, key, requestHash);
  if (claim case ClaimStored(:final response)) return _replay(response);
  if (claim case ClaimConflict()) {
    throw const ApiError(ErrorCode.idempotencyConflict);
  }
  if (claim case ClaimInProgress()) {
    // The first request is still running, and its answer is the one this
    // client wants: say "busy, retry shortly" rather than act twice. The
    // transport waits out a `Retry-After` this short by itself.
    throw const ApiError(
      ErrorCode.unavailable,
      message: 'another request with this idempotency key is still running',
      retryAfter: Duration(seconds: 2),
    );
  }
  // ClaimTaken: the handler runs here and nowhere else for this key.
  final Response response;
  try {
    response = await run();
  } on Object {
    // A thrown error means the handler committed nothing (its transaction
    // rolls back), so the claim is worth nothing: give it up, or a client
    // that retries after a `conflict` would wait out the lease for the same
    // answer.
    await store.release(principal, key, requestHash);
    rethrow;
  }
  if (response.statusCode >= 500) {
    // A 5xx means the handler committed nothing, so the claim is worth
    // nothing: drop it and let the retry run, as before the record existed.
    await store.release(principal, key, requestHash);
    return response;
  }
  final body = await response.readAsString();
  await store.record(
    principal,
    key,
    StoredResponse(
      requestHash: requestHash,
      status: response.statusCode,
      body: body,
      headers: {
        for (final e in response.headers.entries) e.key.toLowerCase(): e.value,
      },
    ),
  );
  return Response(response.statusCode, body: body, headers: response.headers);
}

/// The stored answer as the client saw it first time, plus the one header
/// saying this request never reached the handler.
Response _replay(StoredResponse stored) {
  final headers = {...stored.headers, 'idempotent-replay': 'true'};
  if (stored.body.isNotEmpty && !headers.containsKey('content-type')) {
    // A row stored before headers were kept: the body is still JSON.
    headers['content-type'] = 'application/json; charset=utf-8';
  }
  return Response(stored.status, body: stored.body, headers: headers);
}
