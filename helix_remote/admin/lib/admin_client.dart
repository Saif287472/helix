import 'dart:convert';
import 'package:http/http.dart' as http;

/// Outcome of checking whether a token is still good against a server.
/// Kept distinct from a plain bool so callers can tell "the server said no"
/// (the token is actually dead - safe to discard) apart from "couldn't tell"
/// (offline, DNS hiccup, server briefly down - the token might still be
/// fine, so it must not be discarded on this alone).
enum AdminLoginStatus { ok, unauthorized, unreachable }

class AdminClient {
  AdminClient({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  Future<AdminLoginStatus> verifyLoginDetailed() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/ops/config'),
        headers: _headers,
      );
      if (response.statusCode == 200) return AdminLoginStatus.ok;
      if (response.statusCode == 401 || response.statusCode == 403) {
        return AdminLoginStatus.unauthorized;
      }
      return AdminLoginStatus.unreachable;
    } catch (_) {
      return AdminLoginStatus.unreachable;
    }
  }

  Future<bool> verifyLogin() async =>
      (await verifyLoginDetailed()) == AdminLoginStatus.ok;

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

/// Exchanges a short-lived pairing code (see the backend's
/// AdminPairingModule) for a freshly-rotated admin token. Unlike [AdminClient]
/// this needs no token itself - the code is the credential, and the server
/// only accepts each one once.
Future<String> redeemPairingCode({
  required String baseUrl,
  required String code,
}) async {
  final response = await http.post(
    Uri.parse('$baseUrl/api/v1/admin-pairing/redeem'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'code': code}),
  );
  if (response.statusCode != 200) {
    throw Exception('Invalid or expired code.');
  }
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  return body['admin_token'] as String;
}
