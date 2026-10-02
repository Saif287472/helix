import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Operator-facing wording for anything an admin API call can throw.
///
/// Branches on the error code, never on the server's message, and never
/// includes a request or response body: the text is safe to show and to log.
String describeAdminError(Object error, {DateTime Function()? now}) {
  return switch (error) {
    ApiException e => _describeApi(e, now ?? DateTime.now),
    SignedOutException _ => 'Your admin session has ended. Sign in again.',
    NetworkException e =>
      e.timedOut
          ? 'The server took too long to answer. Try again.'
          : 'Could not reach the server. Check the address and your '
                'connection, then try again.',
    RequestCancelledException _ => 'The request was cancelled.',
    MalformedResponseException _ =>
      'The server answered in a way this console does not understand. Is it '
          'a Helix v2 server?',
    UnsupportedError _ => 'This platform cannot open that connection.',
    _ => 'Something went wrong.',
  };
}

String _describeApi(ApiException e, DateTime Function() now) {
  final text = switch (e.code) {
    ErrorCode.passwordLocked => _locked(e, now),
    ErrorCode.invalidCredentials => 'Wrong password.',
    ErrorCode.rateLimited => _rateLimited(e),
    ErrorCode.unauthenticated ||
    ErrorCode.tokenExpired => 'Your admin session has ended. Sign in again.',
    ErrorCode.alreadyExists =>
      'This server already has an admin password. Sign in instead.',
    ErrorCode.notFound => 'That item no longer exists.',
    ErrorCode.conflict => 'That is no longer possible: the item has changed.',
    ErrorCode.invalidField ||
    ErrorCode.badRequest => 'The server did not accept that value.',
    ErrorCode.forbidden => 'The server refused this action.',
    ErrorCode.maintenance ||
    ErrorCode.unavailable => 'The server is unavailable right now.',
    ErrorCode.expired => 'That has expired.',
    _ when e.status >= 500 => 'The server had a problem. Try again later.',
    _ => 'The server refused the request.',
  };
  final id = e.requestId;
  // The request id lets the operator find the request in the server log.
  return id == null || e.status < 500 ? text : '$text (request $id)';
}

String _locked(ApiException e, DateTime Function() now) {
  final until = e.lockedUntil;
  final wait = e.retryAfter ?? until?.difference(now());
  final tail = wait == null ? 'later' : 'in ${describeWait(wait)}';
  return 'Sign-in is locked after too many wrong passwords. Try again $tail.';
}

String _rateLimited(ApiException e) {
  final wait = e.retryAfter;
  return wait == null
      ? 'Too many requests. Wait a moment and try again.'
      : 'Too many requests. Try again in ${describeWait(wait)}.';
}

/// "45 seconds", "14 minutes", "3 hours": rounded up, never "0".
String describeWait(Duration wait) {
  if (wait.inSeconds < 60) {
    final s = wait.inSeconds < 1 ? 1 : wait.inSeconds;
    return s == 1 ? '1 second' : '$s seconds';
  }
  if (wait.inMinutes < 60) {
    final m = (wait.inSeconds / 60).ceil();
    return m == 1 ? '1 minute' : '$m minutes';
  }
  final h = (wait.inMinutes / 60).ceil();
  return h == 1 ? '1 hour' : '$h hours';
}

/// Whether [error] means the admin token is no longer accepted, so the
/// console must go back to sign-in.
bool endsAdminSession(Object error) =>
    error is SignedOutException ||
    // `invalid_credentials` is a wrong password (changing the admin
    // password), not a rejected token.
    (error is ApiException &&
        error.status == 401 &&
        error.code != ErrorCode.invalidCredentials);
