import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/src/app_error.dart';

abstract interface class SmsProvider {
  bool get isConfigured;

  /// Short operator-facing name of the concrete gateway, e.g. `BulkSMSBD`.
  ///
  /// Admin surfaces render this instead of hardcoding a vendor, so a
  /// self-hoster running a different gateway is not told they are on
  /// someone else's.
  String get displayName;

  /// Sends [message] as an SMS to [phoneNumber] (E.164, e.g.
  /// `+8801XXXXXXXXX`). Throws [SmsDeliveryException] on failure.
  Future<void> send({required String phoneNumber, required String message});
}

/// Used when no SMS provider is configured. The OTP handler checks
/// [isConfigured] and returns a 503 error, so [send] should never be called.
final class NoopSmsProvider implements SmsProvider {
  const NoopSmsProvider();

  @override
  bool get isConfigured => false;

  @override
  String get displayName => 'None';

  @override
  Future<void> send({required String phoneNumber, required String message}) {
    throw UnsupportedError('No SMS provider configured.');
  }
}

/// BulkSMSBD (bulksmsbd.net) HTTP API. Requires an API key and an approved
/// sender ID (HELIX_REMOTE_SMS_API_KEY + HELIX_REMOTE_SMS_SENDER_ID).
///
/// BulkSMSBD's API takes the destination number without a leading `+`
/// (e.g. `8801XXXXXXXXX`), and always responds HTTP 200 - success/failure is
/// signalled by a `response_code` in the body (202 = submitted), not the
/// HTTP status, so a 200 alone doesn't mean the SMS actually went out.
final class BulkSmsBdProvider implements SmsProvider {
  BulkSmsBdProvider({
    required this.apiKey,
    required this.senderId,
    Uri? apiBaseUri,
  }) : apiBaseUri = apiBaseUri ?? Uri.https('bulksmsbd.net', '/api/smsapi');

  final String apiKey;
  final String senderId;

  /// The gateway endpoint, overridable so tests can point this at a local
  /// HttpServer instead of the real bulksmsbd.net - everything else about
  /// [send] (request construction, response parsing, stream handling) runs
  /// unmodified against whatever this points to.
  final Uri apiBaseUri;

  static const _submittedResponseCode = 202;

  @override
  bool get isConfigured => apiKey.isNotEmpty && senderId.isNotEmpty;

  @override
  String get displayName => 'BulkSMSBD';

  @override
  Future<void> send({
    required String phoneNumber,
    required String message,
  }) async {
    final number = phoneNumber.startsWith('+')
        ? phoneNumber.substring(1)
        : phoneNumber;
    final url = apiBaseUri.replace(
      queryParameters: {
        'api_key': apiKey,
        'type': 'text',
        'number': number,
        'senderid': senderId,
        'message': message,
      },
    );

    final http = HttpClient();
    try {
      final req = await http.getUrl(url);
      final res = await req.close();
      // HttpClientResponse is a single-subscription stream - it's already
      // fully consumed by .join() below, so draining it afterward throws
      // "Bad state: Stream has already been listened to." instead of doing
      // anything useful.
      final body = await res.transform(utf8.decoder).join();

      if (res.statusCode != 200) {
        throw SmsDeliveryException(
          res.statusCode,
          body,
          reason: SmsFailureReason.gatewayError,
        );
      }
      final responseCode = _responseCode(body);
      if (responseCode != _submittedResponseCode) {
        throw SmsDeliveryException(
          res.statusCode,
          body,
          reason: _reasonForResponseCode(responseCode),
        );
      }
    } finally {
      http.close(force: true);
    }
  }

  /// BulkSMSBD's response is usually `{"response_code": 202, ...}`, but
  /// some error paths return a bare numeric code with no JSON wrapper -
  /// this handles both.
  int? _responseCode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final value = decoded['response_code'];
        if (value is int) return value;
        if (value is String) return int.tryParse(value);
      }
    } catch (_) {
      return int.tryParse(body.trim());
    }
    return null;
  }

  /// Maps BulkSMSBD's numeric response codes onto the categories that actually
  /// change what an operator should do.
  ///
  /// This distinction matters because BulkSMSBD always answers HTTP 200, so
  /// the response code is the *only* signal available. Without it an invalid
  /// API key is indistinguishable from a transient gateway blip, and the
  /// operator burns time retrying a credential that can never work.
  SmsFailureReason _reasonForResponseCode(int? code) {
    switch (code) {
      // 1011 = "user id not found in this key"; 1009/1010 are the other
      // invalid-key variants BulkSMSBD returns.
      case 1009:
      case 1010:
      case 1011:
        return SmsFailureReason.invalidCredentials;
      // Sender ID missing, not approved, or not linked to this account.
      case 1030:
      case 1031:
      case 1032:
        return SmsFailureReason.invalidSenderId;
      // Destination number malformed or not routable.
      case 1002:
      case 1006:
        return SmsFailureReason.invalidDestination;
      default:
        return SmsFailureReason.rejected;
    }
  }
}

/// Why an SMS send failed, in terms of what an operator should do about it.
enum SmsFailureReason {
  /// The API key is not valid for any BulkSMSBD account. Retrying cannot
  /// help; the deployment's credential must be replaced.
  invalidCredentials,

  /// The sender ID is unknown, unapproved, or not linked to this account.
  invalidSenderId,

  /// The destination number was rejected by the gateway.
  invalidDestination,

  /// The gateway itself failed or returned something unparseable.
  gatewayError,

  /// The gateway understood the request and declined it for a reason with no
  /// specific operator action.
  rejected,
}

/// The SMS provider rejected the request or failed to submit it - the
/// caller should surface a delivery-failed error rather than pretending
/// the code went out.
class SmsDeliveryException extends AppError {
  SmsDeliveryException(
    this.upstreamStatusCode,
    this.body, {
    this.reason = SmsFailureReason.rejected,
  }) : super(
         'Failed to send verification SMS',
         statusCode: 502,
         code: RemoteErrorCode.smsDeliveryFailed,
       );

  /// The gateway's status, not ours - see [statusCode] for what a client
  /// would see if this ever escaped unhandled.
  final int upstreamStatusCode;

  /// The raw gateway response. Server-side only: it can echo the configured
  /// API key back inside its own text, so it must never reach a client.
  final String body;

  /// What an operator should do about it. Drives both the server log and the
  /// deliberately vague client-facing message.
  final SmsFailureReason reason;

  /// The provider's own response code, when it sent a parseable one.
  int? get providerResponseCode {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final value = decoded['response_code'];
        if (value is int) return value;
        if (value is String) return int.tryParse(value);
      }
    } catch (_) {
      return int.tryParse(body.trim());
    }
    return null;
  }

  /// A message safe for a server log. Names the concrete fix without
  /// reproducing the raw body.
  String get operatorMessage => switch (reason) {
    SmsFailureReason.invalidCredentials =>
      'SMS gateway rejected the API key (response code '
          '${providerResponseCode ?? 'unknown'}). The key is not valid for any '
          'BulkSMSBD account - replace HELIX_REMOTE_SMS_API_KEY.',
    SmsFailureReason.invalidSenderId =>
      'SMS gateway rejected the sender ID (response code '
          '${providerResponseCode ?? 'unknown'}). Confirm '
          'HELIX_REMOTE_SMS_SENDER_ID is BulkSMSBD-approved and belongs to the '
          'same account as the API key.',
    SmsFailureReason.invalidDestination =>
      'SMS gateway rejected the destination number (response code '
          '${providerResponseCode ?? 'unknown'}).',
    SmsFailureReason.gatewayError =>
      'SMS gateway returned HTTP $upstreamStatusCode.',
    SmsFailureReason.rejected =>
      'SMS gateway declined the request (response code '
          '${providerResponseCode ?? 'unparseable'}).',
  };

  /// Never includes [body]: the gateway's text can contain the API key.
  @override
  String toString() =>
      'SmsDeliveryException($upstreamStatusCode, $reason): $operatorMessage';
}
