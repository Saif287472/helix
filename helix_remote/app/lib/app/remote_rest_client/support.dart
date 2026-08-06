part of '../remote_rest_client.dart';

/// Error bodies are capped so a proxy's HTML error page cannot be retained.
const int _maxErrorBodyChars = 8192;

String _capErrorBody(String body) => body.length <= _maxErrorBodyChars
    ? body
    : '${body.substring(0, _maxErrorBodyChars)}… [truncated]';

bool _isSafeMethod(String method) =>
    method == 'GET' || method == 'HEAD' || method == 'OPTIONS';

enum RemoteRestFailureKind { http, serverDown, noInternet, timeout, unknown }

class RemoteRestException extends HttpException {
  const RemoteRestException({
    required String message,
    Uri? uri,
    this.statusCode,
    this.correlationId,
    this.retryAfter,
    this.failureKind = RemoteRestFailureKind.unknown,
  }) : super(message, uri: uri);

  final int? statusCode;
  final String? correlationId;
  final Duration? retryAfter;
  final RemoteRestFailureKind failureKind;

  bool get isTransportFailure => statusCode == null;
}
