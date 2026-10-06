import 'package:helix_remote_protocol/src/json.dart';

/// Every error the v2 server returns. Clients branch on [wire], never on the
/// message text. A code's meaning never changes; new codes are additive and
/// old clients treat unknown codes by HTTP status class.
enum ErrorCode implements WireEnum {
  // 400
  badRequest('bad_request', 400),
  invalidField('invalid_field', 400),
  unsupportedVersion('unsupported_version', 400),

  // 401 - the client should refresh its session (or sign in again).
  unauthenticated('unauthenticated', 401),
  tokenExpired('token_expired', 401),

  // 403
  forbidden('forbidden', 403),
  notAMember('not_a_member', 403),
  deviceRevoked('device_revoked', 403),
  accountSuspended('account_suspended', 403),
  accountBanned('account_banned', 403),
  phoneBanned('phone_banned', 403),
  blocked('blocked', 403),
  termsNotAccepted('terms_not_accepted', 403),

  // 404 / 409 / 410
  notFound('not_found', 404),
  conflict('conflict', 409),
  alreadyExists('already_exists', 409),
  accountExists('account_exists', 409),
  nameTaken('name_taken', 409),
  deviceListStale('device_list_stale', 409),
  idempotencyConflict('idempotency_conflict', 409),
  versionConflict('version_conflict', 409),
  groupFull('group_full', 409),
  expired('expired', 410),

  // 413 / 422 / 429
  payloadTooLarge('payload_too_large', 413),
  quotaExceeded('quota_exceeded', 422),
  rateLimited('rate_limited', 429),

  // Credentials (sign-in, OTP, codes). Deliberately vague about which part
  // was wrong.
  invalidCode('invalid_code', 400),
  invalidCredentials('invalid_credentials', 401),
  passwordLocked('password_locked', 429),

  // 5xx
  internal('internal', 500),
  smsUnavailable('sms_unavailable', 503),
  federationUnavailable('federation_unavailable', 502),
  maintenance('maintenance', 503),
  unavailable('unavailable', 503),

  /// A code this client does not know.
  unknown('unknown', 500);

  const ErrorCode(this.wire, this.status);

  @override
  final String wire;

  /// The HTTP status the server sends with this code.
  final int status;

  static ErrorCode fromWire(String wire) {
    for (final code in values) {
      if (code.wire == wire) return code;
    }
    return unknown;
  }

  /// Whether retrying the same request later can succeed.
  bool get isRetryable => switch (this) {
    rateLimited ||
    passwordLocked ||
    internal ||
    smsUnavailable ||
    federationUnavailable ||
    maintenance ||
    unavailable => true,
    _ => false,
  };
}

/// The body of every error response: `{"error": {...}}`.
final class ApiError implements Exception {
  const ApiError(this.code, {this.message, this.details, this.retryAfter});

  final ErrorCode code;

  /// Safe for logs and, for 4xx, for showing to the user. Never contains
  /// secrets or request values.
  final String? message;

  /// Machine-readable extras, documented per code (e.g. `device_list_stale`
  /// carries the device lists; `password_locked` carries `locked_until`).
  final JsonMap? details;

  final Duration? retryAfter;

  int get status => code.status;

  JsonMap toJson() => {
    'error': compact({
      'code': code.wire,
      'message': message,
      'details': details,
      'retry_after_s': retryAfter?.inSeconds,
    }),
  };

  factory ApiError.fromJson(JsonReader json) {
    final error = json.object('error');
    final retry = error.optInt('retry_after_s');
    final rawDetails = error.raw('details');
    return ApiError(
      ErrorCode.fromWire(error.string('code')),
      message: error.optString('message'),
      details: rawDetails == null
          ? null
          : JsonReader.of(rawDetails, path: 'error.details').json,
      retryAfter: retry == null ? null : Duration(seconds: retry),
    );
  }

  @override
  String toString() =>
      'ApiError(${code.wire}${message == null ? '' : ': $message'})';
}

/// `details` of [ErrorCode.deviceListStale]: the sender's view of an
/// account's devices was wrong. The client fixes its lists (fetching keys for
/// [missing]) and retries once.
final class StaleDevices {
  const StaleDevices({required this.accounts});

  final List<StaleAccountDevices> accounts;

  JsonMap toJson() => {
    'accounts': [for (final a in accounts) a.toJson()],
  };

  factory StaleDevices.fromJson(JsonReader json) => StaleDevices(
    accounts: json.objects('accounts', StaleAccountDevices.fromJson),
  );
}

final class StaleAccountDevices {
  const StaleAccountDevices({
    required this.account,
    this.missing = const [],
    this.extra = const [],
  });

  final String account;

  /// Active devices the request did not address.
  final List<String> missing;

  /// Addressed devices that are not (or no longer) active.
  final List<String> extra;

  JsonMap toJson() => {'account': account, 'missing': missing, 'extra': extra};

  factory StaleAccountDevices.fromJson(JsonReader json) => StaleAccountDevices(
    account: json.nonEmpty('account'),
    missing: json.optStrings('missing'),
    extra: json.optStrings('extra'),
  );
}
