/// Where the FCM push provider gets its OAuth2 bearer token.
///
/// FCM HTTP v1 authenticates with a short-lived Google OAuth2 access token,
/// not with an API key. Google issues those for one hour. The backend used
/// to read one straight out of `HELIX_REMOTE_FCM_ACCESS_TOKEN` and note in a
/// comment that "callers are responsible for refreshing the access token
/// before it expires" - which, for a server process, meant an operator
/// pasting a fresh token into the environment and restarting every hour.
/// Push therefore worked for at most an hour after each deploy and then
/// failed silently until someone noticed.
///
/// This file makes the server do the refreshing: sign a JWT with the service
/// account's private key, exchange it for an access token, and keep using
/// that until shortly before it expires.
library;

import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart' as gauth;
import 'package:http/http.dart' as http;

/// The scope FCM send requests are authorised against.
const String fcmMessagingScope =
    'https://www.googleapis.com/auth/firebase.messaging';

/// A bearer token and the moment it stops being accepted.
class FcmAccessToken {
  const FcmAccessToken({required this.value, required this.expiresAt});

  final String value;

  /// UTC. Google returns an absolute expiry rather than a lifetime, so this
  /// is stored as given instead of being derived from the time of receipt -
  /// clock skew between here and Google would otherwise be added to, rather
  /// than subtracted from, the usable life of the token.
  final DateTime expiresAt;
}

abstract interface class FcmAccessTokenSource {
  /// A token that is valid *now*, refreshing first if necessary.
  Future<String> bearerToken();
}

/// A token supplied verbatim, as `HELIX_REMOTE_FCM_ACCESS_TOKEN` does.
///
/// Kept because it is the only form that works without a service-account
/// key, which makes it useful for a one-off manual test. It is not suitable
/// for a running deployment: the token it holds expires within the hour and
/// this class has no way to obtain another.
final class StaticFcmAccessToken implements FcmAccessTokenSource {
  const StaticFcmAccessToken(this.token);

  final String token;

  @override
  Future<String> bearerToken() async => token;
}

/// Obtains a fresh access token from Google for a service-account key.
typedef FcmTokenExchange =
    Future<FcmAccessToken> Function(Map<String, dynamic> serviceAccountJson);

DateTime _utcNow() => DateTime.now().toUtc();

/// The real exchange: JWT-bearer grant against Google's token endpoint.
///
/// Isolated behind [FcmTokenExchange] so the caching, refresh and
/// error-recovery behaviour around it can be tested without a network or a
/// real Google credential - none of which a CI run has.
Future<FcmAccessToken> exchangeServiceAccountForFcmToken(
  Map<String, dynamic> serviceAccountJson,
) async {
  final credentials = gauth.ServiceAccountCredentials.fromJson(
    serviceAccountJson,
  );
  final client = http.Client();
  try {
    final obtained = await gauth.obtainAccessCredentialsViaServiceAccount(
      credentials,
      const [fcmMessagingScope],
      client,
    );
    return FcmAccessToken(
      value: obtained.accessToken.data,
      expiresAt: obtained.accessToken.expiry,
    );
  } finally {
    client.close();
  }
}

/// Exchanges a service-account key for access tokens, and keeps the current
/// one until it is nearly expired.
final class ServiceAccountFcmAccessToken implements FcmAccessTokenSource {
  ServiceAccountFcmAccessToken({
    required Map<String, dynamic> serviceAccountJson,
    FcmTokenExchange exchange = exchangeServiceAccountForFcmToken,
    DateTime Function() clock = _utcNow,
    this.refreshMargin = const Duration(minutes: 5),
  }) : _serviceAccountJson = serviceAccountJson,
       _exchange = exchange,
       _clock = clock;

  final Map<String, dynamic> _serviceAccountJson;
  final FcmTokenExchange _exchange;
  final DateTime Function() _clock;

  /// How long before the stated expiry a token is treated as spent.
  ///
  /// A token that is valid for another two seconds is no use: the request it
  /// would authorise has to reach Google before it lapses. Refreshing early
  /// also absorbs clock skew, which is the difference between "occasionally
  /// a push fails" and "pushes fail whenever this server's clock runs fast".
  final Duration refreshMargin;

  FcmAccessToken? _cached;
  Future<String>? _inFlight;

  @override
  Future<String> bearerToken() {
    final cached = _cached;
    if (cached != null &&
        _clock().isBefore(cached.expiresAt.subtract(refreshMargin))) {
      return Future.value(cached.value);
    }
    return _refresh();
  }

  /// One refresh at a time.
  ///
  /// A burst of pushes - which is exactly what an incoming call to several
  /// devices produces - would otherwise each start their own token exchange
  /// on a cold cache, spending several round trips and rate-limit budget to
  /// obtain several interchangeable tokens.
  Future<String> _refresh() {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final future = _exchange(_serviceAccountJson)
        .then((token) {
          _cached = token;
          return token.value;
        })
        .whenComplete(() {
          _inFlight = null;
        });
    _inFlight = future;
    return future;
  }
}

/// Reads the service-account key named by [value].
///
/// Accepts the key either inline (a JSON object) or as a path to the file
/// Google hands you. Inline suits a secrets manager that injects
/// environment variables; a path suits a mounted Docker secret. Guessing
/// between them by the leading brace costs nothing and spares an operator
/// discovering which one this build wanted from a stack trace.
///
/// Returns null when [value] is empty. Throws [FormatException] when it is
/// set but unusable, because a deployment that meant to configure push and
/// got the path wrong should be told at startup rather than at the first
/// missed call.
Map<String, dynamic>? readFcmServiceAccount(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;

  final raw = trimmed.startsWith('{')
      ? trimmed
      : _readServiceAccountFile(trimmed);

  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (e) {
    throw FormatException(
      'FCM service account is not valid JSON: ${e.message}',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException(
      'FCM service account must be a JSON object.',
    );
  }
  // Checked here rather than left to the first token exchange: these are the
  // two fields the JWT cannot be built without, and a key file that is
  // valid JSON but the wrong kind of credential (an OAuth client, say) is an
  // easy mistake to make and an obscure one to diagnose later.
  for (final field in const ['client_email', 'private_key']) {
    if (decoded[field] is! String || (decoded[field] as String).isEmpty) {
      throw FormatException(
        'FCM service account is missing "$field" — is this a service '
        'account key file?',
      );
    }
  }
  return decoded;
}

String _readServiceAccountFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw FormatException('FCM service account file not found: $path');
  }
  return file.readAsStringSync();
}
