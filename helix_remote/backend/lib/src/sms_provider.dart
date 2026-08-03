import 'dart:convert';
import 'dart:io';

abstract interface class SmsProvider {
  bool get isConfigured;

  /// Sends [message] as an SMS to [phoneNumber] (E.164, e.g.
  /// `+8801XXXXXXXXX`). Throws [SmsDeliveryException] on failure.
  Future<void> send({required String phoneNumber, required String message});
}

/// Used when no SMS provider is configured. Delivery always fails - callers
/// (see `AuthPhoneOtpHandlers._requestPhoneOtpHandler`) check
/// [isConfigured] first and fall back to returning the code directly in the
/// response instead of calling [send] at all.
final class NoopSmsProvider implements SmsProvider {
  const NoopSmsProvider();

  @override
  bool get isConfigured => false;

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
        throw SmsDeliveryException(res.statusCode, body);
      }
      if (_responseCode(body) != _submittedResponseCode) {
        throw SmsDeliveryException(res.statusCode, body);
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
}

/// The SMS provider rejected the request or failed to submit it - the
/// caller should surface a delivery-failed error rather than pretending
/// the code went out.
class SmsDeliveryException implements Exception {
  const SmsDeliveryException(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() => 'SmsDeliveryException($statusCode): $body';
}
