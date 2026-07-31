import 'dart:convert';
import 'package:http/http.dart' as http;

class AdminClient {
  AdminClient({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  Future<bool> verifyLogin() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/ops/config'),
        headers: _headers,
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getMetrics() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/ops/metrics'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load metrics: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getConfig() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/ops/config'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load config: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setWorldwideMode({
    required bool enabled,
    required String domain,
    required String address,
    required String directoryUrl,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/ops/federation/worldwide'),
      headers: _headers,
      body: jsonEncode({
        'enabled': enabled,
        'domain': domain,
        'address': address,
        'directory_url': directoryUrl,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update federation: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> triggerBackup() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/ops/backup'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Backup failed: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getUsers({
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/ops/users?limit=$limit&offset=$offset'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load users: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<String>> getLogs() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/ops/logs'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load logs: ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final logs = body['logs'] as List?;
    return logs?.map((l) => l as String).toList() ?? [];
  }

  /// Issues a new 7-day, single-use invite. The raw code (embedded in
  /// `shareable_url`) is returned exactly once here and never persisted
  /// server-side - only its hash is kept.
  Future<Map<String, dynamic>> createInvite() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/ops/invites'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to create invite: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> listInvites({
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/ops/invites?limit=$limit&offset=$offset'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load invites: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
