import 'dart:convert';
import 'dart:io';

class CliRestClient {
  CliRestClient({
    required this.baseUrl,
    this.accessToken,
  });

  final String baseUrl;
  String? accessToken;

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('$baseUrl$path'));
      request.headers.set('Content-Type', 'application/json');
      if (accessToken != null) {
        request.headers.set('Authorization', 'Bearer $accessToken');
      }
      request.write(jsonEncode(body));
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 400) {
        throw HttpException('HTTP ${response.statusCode}: $responseBody');
      }
      return responseBody.isNotEmpty ? (jsonDecode(responseBody) as Map<String, dynamic>) : {};
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> _get(String path, Map<String, String> query) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
      final request = await client.getUrl(uri);
      if (accessToken != null) {
        request.headers.set('Authorization', 'Bearer $accessToken');
      }
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 400) {
        throw HttpException('HTTP ${response.statusCode}: $responseBody');
      }
      return responseBody.isNotEmpty ? (jsonDecode(responseBody) as Map<String, dynamic>) : {};
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> registerAccount({
    required String accountId,
    required String username,
    required String displayName,
    required String accountIdentityPublicKey,
    required String deviceId,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
    required String accountRegistrationSignature,
    required String deviceRegistrationSignature,
    required String deviceName,
  }) async {
    return _post('/api/v1/accounts/register', {
      'account_id': accountId,
      'username': username,
      'display_name': displayName,
      'account_identity_public_key': accountIdentityPublicKey,
      'device_id': deviceId,
      'device_signing_public_key': deviceSigningPublicKey,
      'device_agreement_public_key': deviceAgreementPublicKey,
      'account_registration_signature': accountRegistrationSignature,
      'device_registration_signature': deviceRegistrationSignature,
      'device_name': deviceName,
      'registration_version': 2,
    });
  }

  Future<Map<String, dynamic>> getChallenge({
    required String accountId,
    required String deviceId,
  }) async {
    return _get('/api/v1/accounts/challenge', {
      'account_id': accountId,
      'device_id': deviceId,
    });
  }

  Future<Map<String, dynamic>> loginDevice({
    required String accountId,
    required String deviceId,
    required String signature,
  }) async {
    final res = await _post('/api/v1/accounts/login', {
      'account_id': accountId,
      'device_id': deviceId,
      'signature': signature,
    });
    accessToken = res['token'] as String?;
    return res;
  }

  Future<Map<String, dynamic>> uploadPreKeys({
    required int signedPrekeyId,
    required String signedPrekey,
    required String signedPrekeySignature,
    required List<Map<String, dynamic>> oneTimePrekeys,
  }) async {
    return _post('/api/v1/prekeys/publish', {
      'signed_prekey_id': signedPrekeyId,
      'signed_prekey': signedPrekey,
      'signature': signedPrekeySignature,
      'one_time_prekeys': oneTimePrekeys,
    });
  }

  Future<Map<String, dynamic>> getPreKeyBundle({required String accountId}) async {
    return _get('/api/v1/prekeys/bundle', {
      'account_id': accountId,
    });
  }

  Future<Map<String, dynamic>> createConversation({
    required String conversationId,
    required String type,
    required String title,
    required List<String> members,
  }) async {
    return _post('/api/v1/messages/conversations/create', {
      'conversation_id': conversationId,
      'type': type,
      'title': title,
      'members': members,
    });
  }

  Future<Map<String, dynamic>> sendMessage({
    required String messageId,
    required String conversationId,
    required List<Map<String, dynamic>> envelopes,
  }) async {
    return _post('/api/v1/messages/send', {
      'message_id': messageId,
      'conversation_id': conversationId,
      'envelopes': envelopes,
    });
  }
}
