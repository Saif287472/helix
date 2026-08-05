import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Wraps [inner] so a thrown [AppError] (or any other exception) becomes a
/// normalized JSON response instead of propagating.
///
/// `server_impl.dart` applies this once, server-wide, via its middleware
/// pipeline - but several modules' own unit tests call `module.router.call`
/// directly, skipping that pipeline entirely. A module that throws
/// [AppError] must apply this to its own router (see `messaging.dart` and
/// `contacts.dart`) so it behaves the same standalone as it does mounted in
/// the full server, rather than only working by accident of which tests
/// happen not to exercise an error path.
Handler withAppErrorHandling(Handler inner) {
  return (Request request) async {
    try {
      return await inner(request);
    } on AppError catch (e) {
      return e.toResponse();
    } on HijackException {
      // A WebSocket upgrade handler signals "I took over the socket" by
      // throwing this, not by returning a Response - it must propagate
      // untouched, or shelf_io reports "Got a response for hijacked
      // request" and the upgrade breaks.
      rethrow;
    } catch (_) {
      return AppError.internal().toResponse();
    }
  };
}

/// Machine-readable error codes a Remote API client can branch on without
/// parsing [AppError.message] strings. Extend this enum as modules migrate
/// to [AppError] and need a code no existing value covers - keep it a flat,
/// reusable set rather than one code per call site.
enum RemoteErrorCode {
  unauthorized('unauthorized'),
  forbidden('forbidden'),
  notAMember('not_a_member'),
  notFound('not_found'),
  badRequest('bad_request'),
  conflict('conflict'),
  quotaExceeded('quota_exceeded'),
  serviceUnavailable('service_unavailable'),
  internalError('internal_error');

  const RemoteErrorCode(this.wire);

  /// The value sent to clients, e.g. `"not_a_member"`.
  final String wire;
}

/// One error shape for the whole Remote backend, thrown from a route handler
/// instead of hand-building a `Response(...)` with its own `jsonEncode`. The
/// error-handling middleware in `server_impl.dart` catches it once and
/// converts it to `{error, code, details?}` JSON - every handler that throws
/// this gets the same body shape for free instead of inventing one per call
/// site.
class AppError implements Exception {
  AppError(this.message, {required this.statusCode, this.code, this.details});

  factory AppError.unauthorized(
    String message, {
    RemoteErrorCode code = RemoteErrorCode.unauthorized,
    Map<String, Object?>? details,
  }) => AppError(message, statusCode: 401, code: code, details: details);

  factory AppError.forbidden(
    String message, {
    RemoteErrorCode code = RemoteErrorCode.forbidden,
    Map<String, Object?>? details,
  }) => AppError(message, statusCode: 403, code: code, details: details);

  factory AppError.notFound(
    String message, {
    RemoteErrorCode code = RemoteErrorCode.notFound,
  }) => AppError(message, statusCode: 404, code: code);

  factory AppError.badRequest(
    String message, {
    RemoteErrorCode code = RemoteErrorCode.badRequest,
    Map<String, Object?>? details,
  }) => AppError(message, statusCode: 400, code: code, details: details);

  factory AppError.conflict(
    String message, {
    RemoteErrorCode code = RemoteErrorCode.conflict,
  }) => AppError(message, statusCode: 409, code: code);

  factory AppError.tooManyRequests(
    String message, {
    RemoteErrorCode code = RemoteErrorCode.quotaExceeded,
  }) => AppError(message, statusCode: 429, code: code);

  factory AppError.serviceUnavailable(
    String message, {
    RemoteErrorCode code = RemoteErrorCode.serviceUnavailable,
  }) => AppError(message, statusCode: 503, code: code);

  /// For the error-handling middleware's own catch-all: an exception that
  /// wasn't thrown as an [AppError] shouldn't leak its message to the
  /// client, so this always carries the same generic text.
  factory AppError.internal() => AppError(
    'Internal server error',
    statusCode: 500,
    code: RemoteErrorCode.internalError,
  );

  final String message;
  final int statusCode;
  final RemoteErrorCode? code;
  final Map<String, Object?>? details;

  Map<String, Object?> toJson() => {
    'error': message,
    if (code != null) 'code': code!.wire,
    if (details != null && details!.isNotEmpty) 'details': details,
  };

  Response toResponse() => Response(
    statusCode,
    body: jsonEncode(toJson()),
    headers: {'Content-Type': 'application/json'},
  );

  @override
  String toString() => 'AppError($statusCode, ${code?.wire}, $message)';
}
