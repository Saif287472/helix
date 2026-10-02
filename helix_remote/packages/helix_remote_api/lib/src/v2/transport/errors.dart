import 'dart:convert';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Everything a v2 client call can throw besides programming errors.
///
/// A `switch` over this sealed type is exhaustive, which is how the engine
/// decides between "show it", "retry later" and "sign out". No subclass's
/// `toString()` contains a token, a request or response body, or a header
/// value: these exceptions are safe to log.
sealed class HelixApiException implements Exception {
  const HelixApiException();
}

/// The server answered with an error (`{"error": {...}}`, REST_V2.md).
///
/// [code] is the protocol [ErrorCode]; clients branch on it, never on
/// [message]. A body that is not a v2 error (a proxy's 502 page, say) is
/// mapped by HTTP status class, as REST_V2.md tells old clients to do with
/// codes they do not know.
final class ApiException extends HelixApiException {
  const ApiException({
    required this.status,
    required this.code,
    this.message,
    this.details,
    this.retryAfter,
    this.requestId,
  });

  /// The HTTP status actually received (for [ErrorCode.unknown] it may differ
  /// from `code.status`).
  final int status;
  final ErrorCode code;

  /// Server wording, safe for logs (the server never puts secrets or request
  /// values in it).
  final String? message;

  /// Machine-readable extras, documented per code.
  final JsonMap? details;

  /// From the `Retry-After` header, else the body's `retry_after_s`.
  final Duration? retryAfter;

  /// The server's `x-request-id`, for support.
  final String? requestId;

  /// Builds the exception from a non-2xx response.
  factory ApiException.fromResponse({
    required int status,
    required List<int> body,
    String? retryAfterHeader,
    String? requestId,
  }) {
    final headerRetry = _parseRetryAfter(retryAfterHeader);
    try {
      final error = ApiError.fromJson(JsonReader.decode(utf8.decode(body)));
      return ApiException(
        status: status,
        code: error.code,
        message: error.message,
        details: error.details,
        retryAfter: headerRetry ?? error.retryAfter,
        requestId: requestId,
      );
    } on FormatException {
      // Not a v2 error body (empty, HTML from a proxy, truncated).
      return ApiException(
        status: status,
        code: codeForStatus(status),
        retryAfter: headerRetry,
        requestId: requestId,
      );
    }
  }

  /// The [ErrorCode] for an error response that carries no (known) code.
  static ErrorCode codeForStatus(int status) => switch (status) {
    400 => ErrorCode.badRequest,
    401 => ErrorCode.unauthenticated,
    403 => ErrorCode.forbidden,
    404 => ErrorCode.notFound,
    409 => ErrorCode.conflict,
    410 => ErrorCode.expired,
    413 => ErrorCode.payloadTooLarge,
    422 => ErrorCode.quotaExceeded,
    429 => ErrorCode.rateLimited,
    502 || 503 || 504 => ErrorCode.unavailable,
    _ when status >= 500 => ErrorCode.internal,
    _ => ErrorCode.unknown,
  };

  static Duration? _parseRetryAfter(String? header) {
    if (header == null) return null;
    final seconds = int.tryParse(header.trim());
    if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
    return null; // HTTP-date form: the v2 server never sends it.
  }

  /// The session is not (or no longer) valid: refresh, then sign in again.
  bool get isUnauthenticated => status == 401;

  /// Worth retrying later, with [retryAfter] when given.
  bool get isRetryable => code.isRetryable;

  /// The device lists of `device_list_stale` (null for other codes, or when
  /// the details are malformed). Fix the lists (fetch keys for `missing`,
  /// drop `extra`) and retry once.
  StaleDevices? get staleDevices {
    final d = details;
    if (code != ErrorCode.deviceListStale || d == null) return null;
    try {
      return StaleDevices.fromJson(JsonReader(d, path: 'error.details'));
    } on FormatException {
      return null;
    }
  }

  /// `details.locked_until` of `password_locked`.
  DateTime? get lockedUntil {
    final d = details;
    if (code != ErrorCode.passwordLocked || d == null) return null;
    try {
      return JsonReader(d).optTime('locked_until');
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() => [
    'ApiException($status ${code.wire}',
    if (message != null) ': $message',
    if (requestId != null) ', request $requestId',
    ')',
  ].join();
}

enum SignedOutReason {
  /// No session is stored (never signed in, or signed out).
  noSession,

  /// The refresh token was refused (expired, reused, device revoked, account
  /// deleted). The stored session has been cleared.
  refreshRejected,

  /// An admin token expired or was refused; admin tokens cannot be
  /// refreshed, the operator signs in again.
  sessionEnded,
}

/// The client has no usable session any more. The app shows sign-in.
final class SignedOutException extends HelixApiException {
  const SignedOutException(this.reason, {this.code});

  final SignedOutReason reason;

  /// The server's code when it refused the refresh (e.g.
  /// [ErrorCode.deviceRevoked]).
  final ErrorCode? code;

  @override
  String toString() =>
      'SignedOutException(${reason.name}${code == null ? '' : ', ${code!.wire}'})';
}

/// The request did not get an HTTP response: connection refused or reset,
/// DNS, TLS, or [timedOut].
final class NetworkException extends HelixApiException {
  const NetworkException({this.timedOut = false, this.cause});

  final bool timedOut;

  /// The underlying error's type, for diagnostics. The error itself is not
  /// kept: its message can carry a URL.
  final Type? cause;

  @override
  String toString() =>
      'NetworkException(${timedOut ? 'timed out' : 'no response'}'
      '${cause == null ? '' : ', $cause'})';
}

/// The caller cancelled the request through its `CancellationToken`.
final class RequestCancelledException extends HelixApiException {
  const RequestCancelledException();

  @override
  String toString() => 'RequestCancelledException()';
}

/// A 2xx response whose body does not match the contract. [path] names the
/// field (never its value).
final class MalformedResponseException extends HelixApiException {
  const MalformedResponseException({required this.path, this.requestId});

  final String path;
  final String? requestId;

  @override
  String toString() =>
      'MalformedResponseException(${path.isEmpty ? 'body' : path}'
      '${requestId == null ? '' : ', request $requestId'})';
}
