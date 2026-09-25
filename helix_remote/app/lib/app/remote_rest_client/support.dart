part of '../remote_rest_client.dart';

/// Error bodies are capped so a proxy's HTML error page cannot be retained.
const int _maxErrorBodyChars = 8192;

String _capErrorBody(String body) => body.length <= _maxErrorBodyChars
    ? body
    : '${body.substring(0, _maxErrorBodyChars)}… [truncated]';

bool _isSafeMethod(String method) =>
    method == 'GET' || method == 'HEAD' || method == 'OPTIONS';

enum RemoteRestFailureKind { http, serverDown, noInternet, timeout, unknown }

Map<String, dynamic>? _decodeApiErrorBody(String body) {
  try {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

/// Stable error codes returned by the Helix API. The backend may add codes
/// without a client release, so callers should treat unknown values as
/// ordinary HTTP failures rather than assuming this list is exhaustive.
abstract final class RemoteApiErrorCodes {
  static const phoneAlreadyRegistered = 'phone_already_registered';
  static const termsAcceptanceRequired = 'terms_acceptance_required';
  static const termsVersionOutdated = 'terms_version_outdated';
}

class RemoteRestException extends HttpException {
  const RemoteRestException({
    required String message,
    Uri? uri,
    this.statusCode,
    this.correlationId,
    this.retryAfter,
    this.serverCode,
    this.serverDetails,
    this.failureKind = RemoteRestFailureKind.unknown,
  }) : super(message, uri: uri);

  final int? statusCode;
  final String? correlationId;
  final Duration? retryAfter;

  /// The machine-readable `code` field from a structured API error, when the
  /// response was JSON. This is deliberately separate from [statusCode]:
  /// registration uses several different 4xx responses that call for distinct
  /// client actions.
  final String? serverCode;
  final Map<String, dynamic>? serverDetails;
  final RemoteRestFailureKind failureKind;

  bool get isTransportFailure => statusCode == null;
}
