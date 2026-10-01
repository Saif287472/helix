import 'dart:convert';

import 'package:http/http.dart' as http;

/// Sends verification texts. Implementations never log the number, the
/// message (it contains the code) or the gateway URL (it contains the key).
abstract interface class SmsProvider {
  bool get isConfigured;

  /// Sends [message] to [phoneNumber] (E.164). Throws [SmsFailed].
  Future<void> send({required String phoneNumber, required String message});
}

final class SmsFailed implements Exception {
  const SmsFailed(this.reason);

  /// A short code for logs (`gateway_error`, `invalid_destination`, ...).
  final String reason;

  @override
  String toString() => 'SmsFailed($reason)';
}

final class NoSmsProvider implements SmsProvider {
  const NoSmsProvider();

  @override
  bool get isConfigured => false;

  @override
  Future<void> send({required String phoneNumber, required String message}) =>
      throw const SmsFailed('not_configured');
}

/// BulkSMSBD (`https://bulksmsbd.net/api/smsapi`), ported from v1.
final class BulkSmsBdProvider implements SmsProvider {
  BulkSmsBdProvider({
    required this.apiKey,
    required this.senderId,
    http.Client? client,
    Uri? endpoint,
  }) : _client = client ?? http.Client(),
       _endpoint = endpoint ?? Uri.https('bulksmsbd.net', '/api/smsapi');

  final String apiKey;
  final String senderId;
  final http.Client _client;
  final Uri _endpoint;

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
    final http.Response response;
    try {
      response = await _client
          .post(
            _endpoint,
            body: {
              'api_key': apiKey,
              'type': 'text',
              'number': number,
              'senderid': senderId,
              'message': message,
            },
          )
          .timeout(const Duration(seconds: 15));
    } on Object {
      throw const SmsFailed('unreachable');
    }
    if (response.statusCode != 200) throw const SmsFailed('gateway_error');
    final code = _responseCode(response.body);
    if (code != 202) {
      throw SmsFailed(switch (code) {
        1009 || 1010 || 1011 => 'invalid_credentials',
        1030 || 1031 || 1032 => 'invalid_sender',
        1002 || 1006 => 'invalid_destination',
        _ => 'rejected',
      });
    }
  }

  int? _responseCode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final value = decoded['response_code'];
        if (value is int) return value;
        if (value is String) return int.tryParse(value);
      }
    } on FormatException {
      return int.tryParse(body.trim());
    }
    return null;
  }
}

/// Keeps sent messages in memory (tests and local development only; the
/// server refuses to start with it outside dev mode).
final class RecordingSmsProvider implements SmsProvider {
  final List<({String phoneNumber, String message})> sent = [];

  @override
  bool get isConfigured => true;

  @override
  Future<void> send({
    required String phoneNumber,
    required String message,
  }) async {
    sent.add((phoneNumber: phoneNumber, message: message));
  }

  /// The six-digit code in the last message to [phoneNumber].
  String lastCodeFor(String phoneNumber) {
    final message = sent.lastWhere((m) => m.phoneNumber == phoneNumber).message;
    return RegExp(r'\d{6}').firstMatch(message)!.group(0)!;
  }
}
