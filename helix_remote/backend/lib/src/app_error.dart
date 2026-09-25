import 'dart:convert';

import 'package:helix_remote_domain/models.dart';
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
    } on RemoteIllegalStatusTransitionException catch (e) {
      // A lifecycle validator refusing a move is a client problem, not a
      // server fault: it means the request asked for something the entity's
      // current state doesn't allow (joining an ended room, answering a
      // call that was already declined). 409 says exactly that, where the
      // catch-all below would report a misleading 500.
      return AppError.conflict(
        e.message,
      ).withDetails({'from': e.from, 'to': e.to}).toResponse();
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

  /// A signed server-to-server request to a peer failed. Distinct from
  /// [internalError]: nothing is wrong with *this* server.
  federationError('federation_error'),

  /// FCM rejected a push. [pushTokenNotFound] is split out because callers
  /// act on it differently - it means "prune this token", not "retry".
  pushDeliveryFailed('push_delivery_failed'),
  pushTokenNotFound('push_token_not_found'),

  /// The SMS gateway rejected or failed to submit a message.
  smsDeliveryFailed('sms_delivery_failed'),

  /// The supplied phone verification code is invalid, expired, or exhausted.
  invalidOtp('invalid_otp'),

  /// A phone hash already belongs to an account. This is deliberately more
  /// specific than [conflict] so a client can offer the account-recovery path
  /// without parsing the human-readable error message.
  phoneAlreadyRegistered('phone_already_registered'),

  /// Global registration cannot proceed until the current Terms of Service
  /// have been explicitly accepted.
  termsAcceptanceRequired('terms_acceptance_required'),

  /// The client displayed a different legal-document version than the server
  /// currently requires.
  termsVersionOutdated('terms_version_outdated'),

  /// The client's cached discovery salt does not match the server's, so the
  /// phone hash it computed cannot be verified. Split out from [badRequest]
  /// because the client's recovery is specific and mechanical: drop the cached
  /// salt, re-fetch it, and retry the request once. This happens legitimately
  /// when a deployment's salt is re-provisioned (fresh/rotated database).
  discoverySaltStale('discovery_salt_stale'),

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
  AppError(
    this.message, {
    required this.statusCode,
    this.code,
    this.details,
    this.headers,
  });

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

  /// Extra response headers this error must carry beyond `Content-Type`.
  /// A few HTTP errors are only correct with one - a 416 has to report
  /// `Content-Range: bytes * /<length>` so the client learns the real size -
  /// which is why those call sites can throw instead of hand-building a
  /// [Response] just to attach a header.
  final Map<String, String>? headers;

  /// A copy carrying [extra] as its [details].
  ///
  /// The named constructors above cover status and code but not details,
  /// and adding a `details` parameter to each one would repeat it six
  /// times. This keeps the common case (`AppError.tooManyRequests(msg)`)
  /// short while letting the handful of call sites that have structured
  /// context attach it: `AppError.tooManyRequests(msg).withDetails({...})`.
  AppError withDetails(Map<String, Object?> extra) => AppError(
    message,
    statusCode: statusCode,
    code: code,
    details: {...?details, ...extra},
    headers: headers,
  );

  Map<String, Object?> toJson() => {
    'error': message,
    if (code != null) 'code': code!.wire,
    if (details != null && details!.isNotEmpty) 'details': details,
  };

  Response toResponse() => Response(
    statusCode,
    body: jsonEncode(toJson()),
    headers: {'Content-Type': 'application/json', ...?headers},
  );

  @override
  String toString() => 'AppError($statusCode, ${code?.wire}, $message)';
}
