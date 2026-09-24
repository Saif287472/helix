import 'dart:convert';

import 'package:helix_remote/app/remote_rest_client.dart';

class RemoteUserErrorCopy {
  const RemoteUserErrorCopy._();

  /// Pulls the `error` field out of a JSON error body, when there is one -
  /// the server includes specific, actionable detail here (e.g. why an SMS
  /// delivery attempt failed) that a generic "HTTP 502" message would hide.
  static String? _serverErrorMessage(RemoteRestException error) {
    try {
      final decoded = jsonDecode(error.message);
      if (decoded is Map<String, dynamic>) {
        final value = decoded['error'];
        if (value is String && value.isNotEmpty) return scrubDomain(value);
      }
    } catch (_) {
      // Not JSON (e.g. a proxy error page) - fall through to generic copy.
    }
    return null;
  }

  /// Scrubs explicit URLs and domain references so server hostnames/domains
  /// are never shown to the user in Helix Remote.
  static String scrubDomain(String text) {
    return text
        .replaceAll(RegExp(r'https?://[a-zA-Z0-9.\-_:]+'), 'the server')
        .replaceAll(
          RegExp(r'\b[a-zA-Z0-9.-]+\.agiletechbd\.com\b', caseSensitive: false),
          'the server',
        );
  }

  static String refreshFailure(RemoteRestException error, Uri backend) {
    switch (error.failureKind) {
      case RemoteRestFailureKind.serverDown:
        return serverUnavailable(backend);
      case RemoteRestFailureKind.noInternet:
        return networkUnavailable();
      case RemoteRestFailureKind.timeout:
        return timeout(backend);
      case RemoteRestFailureKind.http:
      case RemoteRestFailureKind.unknown:
        break;
    }
    switch (error.statusCode) {
      case 400:
        return 'The saved session request was invalid. Sign in again or '
            'try again later if this keeps happening.';
      case 409:
        return 'Your session state changed on another device. Tap Retry to '
            'sync the latest account state.';
      case 429:
        return 'Too many session refresh attempts. Wait a moment, then tap '
            'Retry.';
      case 500:
      case 502:
      case 503:
      case 504:
        return 'The Helix Remote server is having trouble. Tap Retry after '
            'the server is healthy.';
      default:
        return unknownStartup();
    }
  }

  static String registrationFailure(RemoteRestException error, Uri backend) {
    switch (error.failureKind) {
      case RemoteRestFailureKind.serverDown:
        return 'Could not reach the Helix Remote backend. '
            '${serverHint(backend)}';
      case RemoteRestFailureKind.noInternet:
        return networkUnavailable().replaceFirst('tap Retry', 'try again');
      case RemoteRestFailureKind.timeout:
        return 'Helix Remote backend did not respond in time. '
            'Check the connection and try again.';
      case RemoteRestFailureKind.http:
        switch (error.statusCode) {
          case 400:
            return 'Account details were not accepted by this server. '
                'Check the phone number and try again.';
          case 409:
            return 'That phone number or device is already registered. Use '
                'a different number, or sign in with an existing device.';
          case 429:
            return 'Too many registration attempts. Wait a moment, then try '
                'again.';
          case 502:
            return _serverErrorMessage(error) ??
                'Failed to send the verification code. Try again in a '
                    'moment.';
          default:
            return _serverErrorMessage(error) ??
                'Registration failed because the server returned HTTP '
                    '${error.statusCode ?? 'unknown'}. Try again later.';
        }
      case RemoteRestFailureKind.unknown:
        return unknownRegistration();
    }
  }

  static String serverUnavailable(Uri backend) {
    return 'Helix Remote server is unreachable. '
        '${serverHint(backend)}';
  }

  static String serverHint(Uri backend) {
    final host = backend.host;
    if (host == '10.0.2.2') {
      return 'Start the Helix Remote backend on your PC, then tap Retry.';
    }
    if (host == 'localhost' || host == '127.0.0.1') {
      return 'On a physical Android device, localhost points to the phone. '
          'Make sure the backend is running.';
    }
    return 'Check your network connection and tap Retry.';
  }

  static String networkUnavailable() =>
      'Network unavailable. Reconnect to Wi-Fi or mobile data, then tap Retry.';

  static String timeout(Uri backend) =>
      'Helix Remote server did not respond in time. Check the '
      'connection and tap Retry.';

  static String authExpired() =>
      'Your session expired or this device was revoked. Sign in again to '
      'continue.';

  static String unknownStartup() =>
      'Helix Remote could not finish startup because of an unexpected error. '
      'Tap Retry, or try again later if it keeps happening.';

  static String unknownRegistration() =>
      'Registration failed because of an unexpected error. Try again later.';

  static String profileUpdateFailure(RemoteRestException error) {
    switch (error.failureKind) {
      case RemoteRestFailureKind.serverDown:
        return 'Could not reach the server. Check your connection and try '
            'again.';
      case RemoteRestFailureKind.noInternet:
        return networkUnavailable().replaceFirst('tap Retry', 'try again');
      case RemoteRestFailureKind.timeout:
        return 'The server did not respond in time. Check your connection '
            'and try again.';
      case RemoteRestFailureKind.http:
        switch (error.statusCode) {
          case 429:
            // The server's own message already states exactly when the
            // next change is allowed - nothing generic would say it better.
            return _serverErrorMessage(error) ??
                'You can only change your display name once every 30 days.';
          case 400:
            return _serverErrorMessage(error) ??
                'That display name was not accepted.';
          default:
            return _serverErrorMessage(error) ??
                'Could not save. Check your connection and try again.';
        }
      case RemoteRestFailureKind.unknown:
        return 'Could not save because of an unexpected error. Try again.';
    }
  }
}
