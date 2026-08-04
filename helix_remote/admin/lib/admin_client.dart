import 'dart:convert';
import 'package:http/http.dart' as http;

/// Outcome of checking whether a token is still good against a server.
/// Kept distinct from a plain bool so callers can tell "the server said no"
/// (the token is actually dead - safe to discard) apart from "couldn't tell"
/// (offline, DNS hiccup, server briefly down - the token might still be
/// fine, so it must not be discarded on this alone).
enum AdminLoginStatus { ok, unauthorized, unreachable }

/// A page of server console output, plus the server's own explanation for
/// why it might be empty.
///
/// The explanation matters: an empty list on its own is ambiguous between
/// "nothing has happened yet" and "this server cannot write its log file",
/// and the Logs screen used to render both as a bare "No logs available."
class ServerLogs {
  const ServerLogs({
    required this.lines,
    required this.source,
    this.message,
    this.filePath,
  });

  const ServerLogs.empty()
    : lines = const [],
      source = 'unknown',
      message = null,
      filePath = null;

  final List<String> lines;

  /// Where the server read these from: `file`, `memory`, or `none`.
  final String source;

  /// Set when the server has something to say - always set when [lines] is
  /// empty, and also when logs are being served despite a file problem.
  final String? message;

  /// Path being tailed, when [source] is `file`.
  final String? filePath;

  bool get isEmpty => lines.isEmpty;
}

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

  /// Temporary revoke: the user is rejected on their next login/refresh
  /// and every authenticated request in between, but can be restored with
  /// [unsuspendUser] - no re-registration needed.
  Future<void> suspendUser(String accountId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/ops/users/$accountId/suspend'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to suspend user: ${response.body}');
    }
  }

  Future<void> unsuspendUser(String accountId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/ops/users/$accountId/unsuspend'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to unsuspend user: ${response.body}');
    }
  }

  /// Permanent revoke: irreversibly deletes the account and all of its
  /// data (messages, devices, contacts referencing it, etc.). The phone
  /// number itself is left free - a new account can register it again.
  /// Use [blockUser] instead to also refuse that.
  Future<void> deleteUser(String accountId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/ops/users/$accountId/delete'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete user: ${response.body}');
    }
  }

  /// Deletes the account like [deleteUser], and additionally bans its
  /// phone number from ever registering again on this server.
  Future<void> blockUser(String accountId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/ops/users/$accountId/block'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to block user: ${response.body}');
    }
  }

  /// Cancels an invite that hasn't been redeemed yet. Fails (409) if it's
  /// already been used or cancelled.
  Future<void> cancelInvite(String inviteId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/ops/invites/$inviteId/cancel'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to cancel invite: ${response.body}');
    }
  }

  Future<ServerLogs> getLogs({int limit = 200}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/ops/logs?limit=$limit'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load logs: ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final logs = body['logs'] as List?;
    return ServerLogs(
      lines: logs?.map((l) => l as String).toList() ?? const [],
      message: body['message'] as String?,
      source: body['source'] as String? ?? 'unknown',
      filePath: body['file_path'] as String?,
    );
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
