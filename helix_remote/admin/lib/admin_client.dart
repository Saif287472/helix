import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:retry/retry.dart';

Future<T> _retry<T>(Future<T> Function() fn) async {
  return retry<T>(fn, maxAttempts: 5, delayFactor: const Duration(seconds: 1));
}

/// Outcome of checking whether a token is still good against a server.
/// Kept distinct from a plain bool so callers can tell "the server said no"
/// (the token is actually dead - safe to discard) apart from "couldn't tell"
/// (offline, DNS hiccup, server briefly down - the token might still be
/// fine, so it must not be discarded on this alone).
enum AdminLoginStatus { ok, unauthorized, unreachable }

/// A request the server rejected with an explanation worth showing the
/// operator verbatim, rather than a transport failure.
class AdminRequestException implements Exception {
  const AdminRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

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

class SetupStatus {
  final bool needsSetup;
  final String serverId;
  const SetupStatus({required this.needsSetup, required this.serverId});
}

class AdminClient {
  AdminClient({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  /// Checks if the backend server requires first-time admin password setup.
  static Future<SetupStatus> checkSetupStatus(
    String baseUrl, {
    http.Client? httpClient,
  }) async {
    final client = httpClient ?? http.Client();
    final shouldClose = httpClient == null;
    try {
      final sanitized = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final response = await client.get(
        Uri.parse('$sanitized/api/v1/ops/setup-status'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return SetupStatus(
          needsSetup: data['needs_setup'] == true,
          serverId: data['server_id'] as String? ?? '',
        );
      }
      return const SetupStatus(needsSetup: false, serverId: '');
    } catch (_) {
      return const SetupStatus(needsSetup: false, serverId: '');
    } finally {
      if (shouldClose) client.close();
    }
  }

  /// Sets the initial master admin password on a fresh, uninitialized server.
  static Future<void> setupAdminPassword(
    String baseUrl,
    String password, {
    http.Client? httpClient,
  }) async {
    final client = httpClient ?? http.Client();
    final shouldClose = httpClient == null;
    try {
      final sanitized = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final response = await client.post(
        Uri.parse('$sanitized/api/v1/ops/setup-admin-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'password': password}),
      );
      if (response.statusCode != 200) {
        Map<String, dynamic> errorBody = {};
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            errorBody = decoded;
          }
        } catch (_) {}
        throw AdminRequestException(
          errorBody['error'] as String? ??
              'Failed to configure password (${response.statusCode})',
        );
      }
    } finally {
      if (shouldClose) client.close();
    }
  }

  /// Authenticates using master admin password against /api/v1/admin/auth/login,
  /// falling back to verification against /api/v1/ops/config.
  static Future<Map<String, dynamic>> loginWithPassword(
    String baseUrl,
    String password, {
    http.Client? httpClient,
  }) async {
    final client = httpClient ?? http.Client();
    final shouldClose = httpClient == null;
    try {
      final sanitized = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;

      try {
        final res = await client.post(
          Uri.parse('$sanitized/api/v1/admin/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'password': password}),
        );
        if (res.statusCode == 200) {
          return jsonDecode(res.body) as Map<String, dynamic>;
        }
      } catch (_) {}

      final fallbackRes = await client.get(
        Uri.parse('$sanitized/api/v1/ops/config'),
        headers: {
          'Authorization': 'Bearer $password',
          'Content-Type': 'application/json',
        },
      );
      if (fallbackRes.statusCode == 200) {
        final data = jsonDecode(fallbackRes.body) as Map<String, dynamic>;
        return {
          'token': password,
          'server_name': data['server_name'] as String? ?? '',
        };
      }
      throw const AdminRequestException('Invalid master admin password');
    } finally {
      if (shouldClose) client.close();
    }
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  Future<AdminLoginStatus> verifyLoginDetailed() async {
    try {
      final response = await _retry(() => http.get(
        Uri.parse('$baseUrl/api/v1/ops/config'),
        headers: _headers,
      ));
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
    final response = await _retry(() => http.get(
      Uri.parse('$baseUrl/api/v1/ops/metrics'),
      headers: _headers,
    ));
    if (response.statusCode != 200) {
      throw Exception('Failed to load metrics: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getConfig() async {
    final response = await _retry(() => http.get(
      Uri.parse('$baseUrl/api/v1/ops/config'),
      headers: _headers,
    ));
    if (response.statusCode != 200) {
      throw Exception('Failed to load config: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Sets the server's display name, or clears it when [name] is empty.
  /// Returns the normalized name the server stored, which may differ from
  /// what was sent (surrounding whitespace trimmed, internal runs
  /// collapsed).
  ///
  /// Throws [AdminRequestException] carrying the server's own message on a
  /// validation failure, so the field can show why rather than a generic
  /// error.
  Future<String> setServerName(String name) async {
    final response = await _retry(() => http.post(
      Uri.parse('$baseUrl/api/v1/ops/config/server-name'),
      headers: _headers,
      body: jsonEncode({'server_name': name}),
    ));
    final body = _decodeOrNull(response.body);
    if (response.statusCode != 200) {
      throw AdminRequestException(
        body?['error'] as String? ?? 'Failed to save the server name.',
      );
    }
    return body?['server_name'] as String? ?? '';
  }

  Map<String, dynamic>? _decodeOrNull(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> setWorldwideMode({
    required bool enabled,
    required String domain,
    required String address,
    required String directoryUrl,
  }) async {
    final response = await _retry(() => http.post(
      Uri.parse('$baseUrl/api/v1/ops/federation/worldwide'),
      headers: _headers,
      body: jsonEncode({
        'enabled': enabled,
        'domain': domain,
        'address': address,
        'directory_url': directoryUrl,
      }),
    ));
    if (response.statusCode != 200) {
      throw Exception('Failed to update federation: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> triggerBackup() async {
    final response = await _retry(() => http.post(
      Uri.parse('$baseUrl/api/v1/ops/backup'),
      headers: _headers,
    ));
    if (response.statusCode != 200) {
      throw Exception('Backup failed: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getUsers({
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _retry(() => http.get(
      Uri.parse('$baseUrl/api/v1/ops/users?limit=$limit&offset=$offset'),
      headers: _headers,
    ));
    if (response.statusCode != 200) {
      throw Exception('Failed to load users: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Temporary revoke: the user is rejected on their next login/refresh
  /// and every authenticated request in between, but can be restored with
  /// [unsuspendUser] - no re-registration needed.
  Future<void> suspendUser(String accountId) async {
    final response = await _retry(() => http.post(
      Uri.parse('$baseUrl/api/v1/ops/users/$accountId/suspend'),
      headers: _headers,
    ));
    if (response.statusCode != 200) {
      throw Exception('Failed to suspend user: ${response.body}');
    }
  }

  Future<void> unsuspendUser(String accountId) async {
    final response = await _retry(() => http.post(
      Uri.parse('$baseUrl/api/v1/ops/users/$accountId/unsuspend'),
      headers: _headers,
    ));
    if (response.statusCode != 200) {
      throw Exception('Failed to unsuspend user: ${response.body}');
    }
  }

  /// Generates a single-use 48-hour account recovery code (HLX-REC-...)
  /// for a user to restore access on a new device.
  Future<Map<String, dynamic>> generateRecoveryCode(String accountId) async {
    final response = await _retry(() => http.post(
      Uri.parse('$baseUrl/api/v1/ops/users/$accountId/recovery-code'),
      headers: _headers,
    ));
    final body = _decodeOrNull(response.body);
    if (response.statusCode != 200) {
      throw AdminRequestException(
        body?['error'] as String? ?? 'Failed to generate recovery code.',
      );
    }
    return body ?? {};
  }

  /// Permanent revoke: irreversibly deletes the account and all of its
  /// data (messages, devices, contacts referencing it, etc.). The phone
  /// number itself is left free - a new account can register it again.
  /// Use [blockUser] instead to also refuse that.
  Future<void> deleteUser(String accountId) async {
    final response = await _retry(() => http.post(
      Uri.parse('$baseUrl/api/v1/ops/users/$accountId/delete'),
      headers: _headers,
    ));
    if (response.statusCode != 200) {
      throw Exception('Failed to delete user: ${response.body}');
    }
  }

  /// Deletes the account like [deleteUser], and additionally bans its
  /// phone number from ever registering again on this server.
  Future<void> blockUser(String accountId) async {
    final response = await _retry(() => http.post(
      Uri.parse('$baseUrl/api/v1/ops/users/$accountId/block'),
      headers: _headers,
    ));
    if (response.statusCode != 200) {
      throw Exception('Failed to block user: ${response.body}');
    }
  }

  /// Cancels an invite that hasn't been redeemed yet. Fails (409) if it's
  /// already been used or cancelled.
  Future<void> cancelInvite(String inviteId) async {
    final response = await _retry(() => http.post(
      Uri.parse('$baseUrl/api/v1/ops/invites/$inviteId/cancel'),
      headers: _headers,
    ));
    if (response.statusCode != 200) {
      throw Exception('Failed to cancel invite: ${response.body}');
    }
  }

  Future<ServerLogs> getLogs({int limit = 200}) async {
    final response = await _retry(() => http.get(
      Uri.parse('$baseUrl/api/v1/ops/logs?limit=$limit'),
      headers: _headers,
    ));
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
    final response = await _retry(() => http.post(
      Uri.parse('$baseUrl/api/v1/ops/invites'),
      headers: _headers,
    ));
    if (response.statusCode != 200) {
      throw Exception('Failed to create invite: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> listInvites({
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _retry(() => http.get(
      Uri.parse('$baseUrl/api/v1/ops/invites?limit=$limit&offset=$offset'),
      headers: _headers,
    ));
    if (response.statusCode != 200) {
      throw Exception('Failed to load invites: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Revokes an individual device access token.
  Future<void> revokeDevice(String accountId, String deviceId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/admin/users/$accountId/devices/$deviceId/revoke'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      final fallbackRes = await http.post(
        Uri.parse('$baseUrl/api/v1/ops/users/$accountId/devices/$deviceId/revoke'),
        headers: _headers,
      );
      if (fallbackRes.statusCode != 200) {
        throw Exception('Failed to revoke device: ${response.body}');
      }
    }
  }

  /// Fetches user reports for moderation, one page at a time.
  ///
  /// A transport failure throws rather than returning an empty list, so the
  /// caller can tell "no reports" from "could not reach the server".
  Future<List<Map<String, dynamic>>> getReports({
    int? limit,
    int? offset,
  }) async {
    final params = <String>[];
    if (limit != null) params.add('limit=$limit');
    if (offset != null) params.add('offset=$offset');
    final query = params.isNotEmpty ? '?${params.join('&')}' : '';
    final response = await _retry(() => http.get(
      Uri.parse('$baseUrl/api/v1/admin/reports$query'),
      headers: _headers,
    ));
    if (response.statusCode != 200) {
      throw AdminRequestException(
        _decodeOrNull(response.body)?['error'] as String? ??
            'Failed to load reports (${response.statusCode}).',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final list = body['reports'] as List? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  /// Resolves a user safety or abuse report.
  ///
  /// Throws [AdminRequestException] carrying the server's message on a
  /// non-200, so a failed resolution is never rendered as a success.
  Future<void> resolveReport(String reportId) async {
    final response = await _retry(() => http.post(
      Uri.parse('$baseUrl/api/v1/admin/reports/$reportId/resolve'),
      headers: _headers,
    ));
    if (response.statusCode != 200) {
      throw AdminRequestException(
        _decodeOrNull(response.body)?['error'] as String? ??
            'Failed to resolve report (${response.statusCode}).',
      );
    }
  }

  /// Dismisses a user report.
  Future<void> dismissReport(String reportId) async {
    final response = await _retry(() => http.post(
      Uri.parse('$baseUrl/api/v1/admin/reports/$reportId/dismiss'),
      headers: _headers,
    ));
    if (response.statusCode != 200) {
      throw AdminRequestException(
        _decodeOrNull(response.body)?['error'] as String? ??
            'Failed to dismiss report (${response.statusCode}).',
      );
    }
  }

  /// Fetches administrative audit stream logs.
  Future<List<Map<String, dynamic>>> getAuditLogs({String? accountId}) async {
    final q = accountId != null ? '?account_id=$accountId' : '';
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/admin/audit$q'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final list = body['logs'] as List? ?? [];
        return list.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  /// Turns maintenance mode on or off.
  ///
  /// While it is on the server answers every client route with 503, so this
  /// call and anything under `/ops` are the only things that still respond.
  Future<void> setMaintenanceMode(bool enabled) async {
    final response = await _retry(
      () => http.post(
        Uri.parse('$baseUrl/api/v1/ops/maintenance'),
        headers: _headers,
        body: jsonEncode({'enabled': enabled}),
      ),
    );
    if (response.statusCode != 200) {
      throw AdminRequestException(
        _decodeOrNull(response.body)?['error'] as String? ??
            'Failed to change maintenance mode (${response.statusCode}).',
      );
    }
  }

  /// Replaces the master admin password.
  ///
  /// The server requires [currentPassword] and regenerates the salt, so this
  /// cannot be used to take over a console someone else left open.
  Future<void> changeAdminPin({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _retry(
      () => http.post(
        Uri.parse('$baseUrl/api/v1/ops/admin-pin'),
        headers: _headers,
        body: jsonEncode({
          'current_password': currentPassword,
          'new_password': newPassword,
        }),
      ),
    );
    if (response.statusCode != 200) {
      throw AdminRequestException(
        _decodeOrNull(response.body)?['error'] as String? ??
            'Failed to change the password (${response.statusCode}).',
      );
    }
  }

  /// Deletes expired attachment references, dead-letter and failed outbox
  /// rows, and stale refresh tokens. Returns the per-table counts so the
  /// console can report what actually happened.
  Future<Map<String, int>> purgeData() async {
    final response = await _retry(
      () => http.post(
        Uri.parse('$baseUrl/api/v1/ops/purge'),
        headers: _headers,
      ),
    );
    if (response.statusCode != 200) {
      throw AdminRequestException(
        _decodeOrNull(response.body)?['error'] as String? ??
            'Failed to purge data (${response.statusCode}).',
      );
    }
    final body = _decodeOrNull(response.body);
    final removed = (body?['removed'] as Map?) ?? const {};
    return removed.map((key, value) => MapEntry(key, value is int ? value : 0));
  }

  /// The redacted support bundle an operator attaches to a bug report.
  Future<Map<String, dynamic>> getSupportDiagnostic() async {
    final response = await _retry(
      () => http.get(
        Uri.parse('$baseUrl/api/v1/ops/support-diagnostic'),
        headers: _headers,
      ),
    );
    if (response.statusCode != 200) {
      throw AdminRequestException(
        _decodeOrNull(response.body)?['error'] as String? ??
            'Failed to build the support bundle (${response.statusCode}).',
      );
    }
    return _decodeOrNull(response.body) ?? const {};
  }

  /// Current state of every server-owned feature flag.
  ///
  /// The server allow-lists the flag names, so an unknown name is a 404
  /// rather than an arbitrary remotely-switchable capability.
  Future<Map<String, bool>> getFeatureFlags() async {
    final response = await _retry(
      () => http.get(Uri.parse('$baseUrl/api/v1/ops/feature-flags'), headers: _headers),
    );
    if (response.statusCode != 200) {
      throw AdminRequestException(
        _decodeOrNull(response.body)?['error'] as String? ??
            'Failed to load feature flags (${response.statusCode}).',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final flags = (body['flags'] as Map?) ?? const {};
    return flags.map((key, value) => MapEntry(key as String, value == true));
  }

  /// Turns a single server-owned feature flag on or off.
  Future<void> setFeatureFlag(String name, bool enabled) async {
    final response = await _retry(
      () => http.post(
        Uri.parse('$baseUrl/api/v1/ops/feature-flags/$name'),
        headers: _headers,
        body: jsonEncode({'enabled': enabled}),
      ),
    );
    if (response.statusCode != 200) {
      throw AdminRequestException(
        _decodeOrNull(response.body)?['error'] as String? ??
            'Failed to update "$name" (${response.statusCode}).',
      );
    }
  }

  /// Opens a live WebSocket stream of server logs.
  ///
  /// The returned handle carries the decoded lines plus a [close] callback.
  /// Cancelling the `StreamSubscription` alone is not enough - it leaves the
  /// underlying socket open - so callers must invoke [LogStreamHandle.close]
  /// when they pause or tear the stream down.
  LogStreamHandle streamLogs() {
    final wsProto = baseUrl.startsWith('https') ? 'wss' : 'ws';
    final host = baseUrl.replaceFirst(RegExp(r'^https?://'), '');
    final uri = Uri.parse('$wsProto://$host/api/v1/admin/logs/stream?token=$token');
    final channel = WebSocketChannel.connect(uri);
    final lines = channel.stream.map((event) {
      try {
        final data = jsonDecode(event as String);
        if (data is Map && data.containsKey('line')) {
          return data['line'] as String;
        }
      } catch (_) {
        // Not a JSON frame - fall through and surface it verbatim.
      }
      return event.toString();
    });
    return LogStreamHandle(
      lines: lines,
      close: () async {
        try {
          await channel.sink.close();
        } catch (_) {
          // Already closed or never opened; nothing to do.
        }
      },
    );
  }
}

/// A live log stream plus the means to actually shut it down.
///
/// See [AdminClient.streamLogs].
class LogStreamHandle {
  const LogStreamHandle({required this.lines, required this.close});

  final Stream<String> lines;

  /// Closes the underlying WebSocket. Safe to call more than once.
  final Future<void> Function() close;
}
