import 'dart:async';
import 'dart:convert';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An in-memory v2 admin API behind an `http.Client`. The console's real
/// `HelixAdminApi` talks to it, so tests cover the whole path from a tap to
/// the wire format and back, with no network.
final class FakeAdminServer {
  FakeAdminServer({DateTime Function()? now}) : _now = now ?? DateTime.now {
    client = MockClient(_handle);
  }

  static final host = Uri.parse('https://helix.test');

  late final http.Client client;
  final DateTime Function() _now;

  // ----------------------------------------------------------------- state

  /// Null until first-run setup.
  String? adminPassword;
  final Set<String> validTokens = {};
  int _tokens = 0;
  int failedSignIns = 0;

  /// Every request answered: "METHOD /path".
  final List<String> requests = [];

  /// Bodies of the requests (to check what was sent), by "METHOD /path".
  final Map<String, List<Map<String, Object?>>> bodies = {};

  bool unreachable = false;

  /// Page size the server uses (the client may ask for more).
  int pageSize = 50;

  List<AdminAccount> accounts = [];
  final Map<String, List<AdminDevice>> devices = {};
  List<AdminInvite> invites = [];
  List<AdminReport> reports = [];
  final List<AuditEntry> audit = [];
  List<String> logLines = [];
  int deadJobs = 0;

  AdminConfig config = const AdminConfig(
    serverName: 'Test Server',
    version: '2.0.0-test',
    registration: RegistrationMode.invite,
    maintenance: false,
    federationEnabled: false,
    maxAttachmentBytes: 10 * 1024 * 1024,
    nodeId: 'node-1',
  );
  Map<String, bool> flags = {
    'crash_reporting_upload': false,
    'minimal_analytics': true,
    'group_calls': false,
  };
  ReadyResponse ready = const ReadyResponse(
    ready: true,
    checks: {'database': true, 'event_bus': true, 'storage': true},
  );
  String metrics = '''
# TYPE helix_ws_open gauge
helix_ws_open 3.0
helix_jobs_dead 0.0
helix_mailbox_backlog 12.0
helix_http_request_seconds_count{route="/v1/x",status="2xx"} 90
helix_http_request_seconds_count{route="/v1/x",status="5xx"} 10
''';

  final Map<String, _Failure> _failures = {};

  /// Makes requests matching [key] ("METHOD /path" with `{}` as a wildcard
  /// segment) fail with [code]. [times] null means every time.
  void fail(
    String key,
    ErrorCode code, {
    int? status,
    Duration? retryAfter,
    JsonMap? details,
    int? times = 1,
  }) {
    _failures[key] = _Failure(code, status, retryAfter, details, times);
  }

  void clearFailures() => _failures.clear();

  /// Ends every admin session, as an expiry or a password change would.
  void expireAllTokens() => validTokens.clear();

  /// Sessions held by the console are valid for 12 hours from [_now].
  AdminSession issue() {
    final token = 'token-${++_tokens}';
    validTokens.add(token);
    return AdminSession(
      token: token,
      expiresAt: _now().add(const Duration(hours: 12)),
    );
  }

  String? lastTokenIssued() => _tokens == 0 ? null : 'token-$_tokens';

  // ------------------------------------------------------------- the router

  Future<http.Response> _handle(http.Request request) async {
    if (unreachable) throw http.ClientException('connection refused');
    final path = request.url.path;
    final key = '${request.method} $path';
    requests.add(key);
    if (request.body.isNotEmpty) {
      final decoded = jsonDecode(request.body);
      if (decoded is Map<String, Object?>) {
        (bodies[key] ??= []).add(decoded);
      }
    }

    final failure = _matchFailure(key);
    if (failure != null) return failure;

    final isPublic =
        path == '/v1/admin/setup' ||
        path == '/v1/admin/sessions' ||
        path.startsWith('/v1/health/');
    if (!isPublic) {
      final auth = request.headers['authorization'] ?? '';
      final token = auth.startsWith('Bearer ') ? auth.substring(7) : '';
      if (!validTokens.contains(token)) {
        return _error(ErrorCode.unauthenticated);
      }
    }

    final query = request.url.queryParameters;
    final m = request.method;
    RegExpMatch? match(String pattern) =>
        RegExp('^$pattern\$').firstMatch(path);

    if (m == 'GET' && path == '/v1/admin/setup') {
      return _json(
        AdminSetupStatus(configured: adminPassword != null).toJson(),
      );
    }
    if (m == 'POST' && path == '/v1/admin/setup') {
      if (adminPassword != null) return _error(ErrorCode.alreadyExists);
      final password = _body(request)['password'] as String;
      if (password.length < AdminPasswordRequest.minLength) {
        return _error(ErrorCode.invalidField);
      }
      adminPassword = password;
      return _json(issue().toJson(), status: 201);
    }
    if (m == 'POST' && path == '/v1/admin/sessions') {
      final password = _body(request)['password'] as String;
      if (failedSignIns >= 5) {
        return _error(
          ErrorCode.passwordLocked,
          retryAfter: const Duration(minutes: 15),
        );
      }
      if (password != adminPassword) {
        failedSignIns++;
        return _error(ErrorCode.invalidCredentials);
      }
      failedSignIns = 0;
      return _json(issue().toJson());
    }
    if (m == 'PUT' && path == '/v1/admin/password') {
      final body = _body(request);
      if (body['current_password'] != adminPassword) {
        return _error(ErrorCode.invalidCredentials);
      }
      adminPassword = body['new_password'] as String;
      validTokens.clear();
      _record('admin.password');
      return _json(issue().toJson());
    }

    if (m == 'GET' && path == '/v1/admin/accounts') {
      var list = accounts.where((a) {
        final status = query['status'];
        if (status != null && a.status.wire != status) return false;
        final q = query['q']?.toLowerCase();
        if (q == null) return true;
        return (a.helixName?.toLowerCase().startsWith(q) ?? false) ||
            a.phoneLast4 == q;
      }).toList();
      return _paged(list, query, (a) => a.toJson());
    }
    var found = match(r'/v1/admin/accounts/([^/]+)');
    if (found != null) {
      final id = found.group(1)!;
      final account = _account(id);
      if (m == 'GET') {
        if (account == null) return _error(ErrorCode.notFound);
        return _json(
          AdminAccountDetail(
            account: account,
            devices: devices[id] ?? const [],
            hasPassword: true,
            openReports: reports
                .where((r) => r.subject == id && r.status == ReportStatus.open)
                .length,
          ).toJson(),
        );
      }
      if (m == 'DELETE') {
        if (account == null) return _error(ErrorCode.notFound);
        accounts = [
          for (final a in accounts)
            if (a.accountId != id) a,
        ];
        _record('account.delete', target: id);
        return http.Response('', 204);
      }
    }
    found = match(r'/v1/admin/accounts/([^/]+)/suspension');
    if (found != null) {
      final id = found.group(1)!;
      final account = _account(id);
      if (account == null) return _error(ErrorCode.notFound);
      _setStatus(
        id,
        m == 'PUT' ? AccountStatus.suspended : AccountStatus.active,
      );
      _record(m == 'PUT' ? 'account.suspend' : 'account.unsuspend', target: id);
      return http.Response('', 204);
    }
    found = match(r'/v1/admin/accounts/([^/]+)/ban');
    if (found != null && m == 'POST') {
      final id = found.group(1)!;
      if (_account(id) == null) return _error(ErrorCode.notFound);
      accounts = [
        for (final a in accounts)
          if (a.accountId != id) a,
      ];
      _record('account.ban', target: id);
      return http.Response('', 204);
    }
    found = match(r'/v1/admin/accounts/([^/]+)/devices/([^/]+)');
    if (found != null && m == 'DELETE') {
      final id = found.group(1)!;
      final deviceId = found.group(2)!;
      final list = devices[id];
      if (list == null || !list.any((d) => d.deviceId == deviceId)) {
        return _error(ErrorCode.notFound);
      }
      devices[id] = [
        for (final d in list)
          if (d.deviceId == deviceId)
            AdminDevice(
              deviceId: d.deviceId,
              name: d.name,
              platform: d.platform,
              active: false,
              createdAt: d.createdAt,
              lastSeenOn: d.lastSeenOn,
              revokedAt: _now(),
            )
          else
            d,
      ];
      _record('device.revoke', target: deviceId);
      return http.Response('', 204);
    }
    found = match(r'/v1/admin/accounts/([^/]+)/recovery-codes');
    if (found != null && m == 'POST') {
      final id = found.group(1)!;
      if (_account(id) == null) return _error(ErrorCode.notFound);
      _record('account.recovery_code', target: id);
      return _json(
        AdminRecoveryCode(
          recoveryCode: 'HLX-REC-SECRET-CODE-$id',
          expiresAt: _now().add(const Duration(hours: 48)),
        ).toJson(),
        status: 201,
      );
    }

    if (m == 'GET' && path == '/v1/admin/invites') {
      return _paged(invites, query, (i) => i.toJson());
    }
    if (m == 'POST' && path == '/v1/admin/invites') {
      final id = 'invite-${invites.length + 1}-000000';
      invites = [
        AdminInvite(
          inviteId: id,
          issuer: 'admin',
          status: InviteStatus.open,
          createdAt: _now(),
          expiresAt: _now().add(const Duration(days: 7)),
        ),
        ...invites,
      ];
      _record('invite.create', target: id);
      return _json(
        CreatedInvite(
          inviteId: id,
          inviteCode: 'HLX-INV-SECRET-CODE',
          expiresAt: _now().add(const Duration(days: 7)),
        ).toJson(),
        status: 201,
      );
    }
    found = match(r'/v1/admin/invites/([^/]+)');
    if (found != null && m == 'DELETE') {
      final id = found.group(1)!;
      final index = invites.indexWhere((i) => i.inviteId == id);
      if (index < 0 || invites[index].status != InviteStatus.open) {
        return _error(ErrorCode.notFound);
      }
      final old = invites[index];
      invites = [
        for (final i in invites)
          if (i.inviteId == id)
            AdminInvite(
              inviteId: old.inviteId,
              issuer: old.issuer,
              status: InviteStatus.cancelled,
              createdAt: old.createdAt,
              expiresAt: old.expiresAt,
            )
          else
            i,
      ];
      _record('invite.cancel', target: id);
      return http.Response('', 204);
    }

    if (m == 'GET' && path == '/v1/admin/reports') {
      final status = query['status'];
      final list = reports
          .where((r) => status == null || r.status.wire == status)
          .toList();
      return _paged(list, query, (r) => r.toJson());
    }
    found = match(r'/v1/admin/reports/([^/]+)');
    if (found != null && m == 'PUT') {
      final id = found.group(1)!;
      final index = reports.indexWhere((r) => r.reportId == id);
      if (index < 0 || reports[index].status != ReportStatus.open) {
        return _error(ErrorCode.notFound);
      }
      final outcome = ReportStatus.values.firstWhere(
        (s) => s.wire == _body(request)['status'],
      );
      final old = reports[index];
      reports = [
        for (final r in reports)
          if (r.reportId == id)
            AdminReport(
              reportId: old.reportId,
              reporter: old.reporter,
              subject: old.subject,
              category: old.category,
              status: outcome,
              createdAt: old.createdAt,
              note: old.note,
            )
          else
            r,
      ];
      _record('report.${outcome.wire}', target: id);
      return http.Response('', 204);
    }

    if (m == 'GET' && path == '/v1/admin/audit') {
      return _paged(audit.reversed.toList(), query, (e) => e.toJson());
    }
    if (m == 'GET' && path == '/v1/admin/config') {
      return _json(config.toJson());
    }
    if (m == 'PATCH' && path == '/v1/admin/config') {
      final patch = AdminConfigPatch.fromJson(JsonReader.of(_body(request)));
      config = AdminConfig(
        serverName: patch.serverName ?? config.serverName,
        version: config.version,
        registration: config.registration,
        maintenance: patch.maintenance ?? config.maintenance,
        federationEnabled: patch.federationEnabled ?? config.federationEnabled,
        maxAttachmentBytes: config.maxAttachmentBytes,
        nodeId: config.nodeId,
        federationDomain: config.federationDomain,
      );
      _record('config.update');
      return _json(config.toJson());
    }
    if (m == 'GET' && path == '/v1/admin/feature-flags') {
      return _json(FeatureFlags(flags: flags).toJson());
    }
    found = match(r'/v1/admin/feature-flags/([^/]+)');
    if (found != null && m == 'PUT') {
      final name = found.group(1)!;
      if (!flags.containsKey(name)) return _error(ErrorCode.notFound);
      flags = {...flags, name: _body(request)['enabled'] as bool};
      _record('flag.set', target: name);
      return http.Response('', 204);
    }
    if (m == 'GET' && path == '/v1/admin/logs') {
      final limit = int.tryParse(query['limit'] ?? '') ?? 200;
      final lines = logLines.length > limit
          ? logLines.sublist(logLines.length - limit)
          : logLines;
      return _json(AdminLogLines(lines: lines).toJson());
    }
    if (m == 'POST' && path == '/v1/admin/purge') {
      final removed = {'dead_jobs': deadJobs, 'expired_codes': 0};
      deadJobs = 0;
      _record('purge');
      return _json(PurgeResult(removed: removed).toJson());
    }
    if (m == 'GET' && path == '/v1/ops/metrics') {
      return http.Response(
        metrics,
        200,
        headers: {'content-type': 'text/plain'},
      );
    }
    if (m == 'GET' && path == '/v1/health/ready') {
      return _json(ready.toJson(), status: ready.ready ? 200 : 503);
    }
    return _error(ErrorCode.notFound);
  }

  // ---------------------------------------------------------------- helpers

  AdminAccount? _account(String id) {
    for (final a in accounts) {
      if (a.accountId == id) return a;
    }
    return null;
  }

  void _setStatus(String id, AccountStatus status) {
    accounts = [
      for (final a in accounts)
        if (a.accountId == id)
          AdminAccount(
            accountId: a.accountId,
            status: status,
            createdAt: a.createdAt,
            activeDevices: a.activeDevices,
            helixName: a.helixName,
            phoneLast4: a.phoneLast4,
            lastSeenOn: a.lastSeenOn,
          )
        else
          a,
    ];
  }

  void _record(String action, {String? target}) => audit.add(
    AuditEntry(
      id: 'audit-${audit.length + 1}',
      action: action,
      at: _now(),
      target: target,
    ),
  );

  Map<String, Object?> _body(http.Request request) =>
      jsonDecode(request.body) as Map<String, Object?>;

  http.Response _paged<T>(
    List<T> all,
    Map<String, String> query,
    Map<String, Object?> Function(T item) encode,
  ) {
    final start = int.tryParse(query['cursor'] ?? '') ?? 0;
    final limit = int.tryParse(query['limit'] ?? '') ?? pageSize;
    final size = limit < pageSize ? limit : pageSize;
    final end = (start + size) > all.length ? all.length : start + size;
    return _json(
      Page<T>(
        items: all.sublist(start, end),
        nextCursor: end < all.length ? '$end' : null,
      ).toJson(encode),
    );
  }

  http.Response _json(Object? body, {int status = 200}) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  http.Response _error(
    ErrorCode code, {
    Duration? retryAfter,
    JsonMap? details,
    int? status,
  }) => http.Response(
    jsonEncode(
      ApiError(
        code,
        message: 'test',
        details: details,
        retryAfter: retryAfter,
      ).toJson(),
    ),
    status ?? code.status,
    headers: {
      'content-type': 'application/json',
      if (retryAfter != null) 'retry-after': '${retryAfter.inSeconds}',
    },
  );

  http.Response? _matchFailure(String key) {
    for (final entry in _failures.entries.toList()) {
      final pattern = RegExp(
        '^${RegExp.escape(entry.key).replaceAll(r'\{\}', '[^/]+')}\$',
      );
      if (!pattern.hasMatch(key)) continue;
      final f = entry.value;
      if (f.times != null) {
        f.times = f.times! - 1;
        if (f.times! <= 0) _failures.remove(entry.key);
      }
      return _error(
        f.code,
        status: f.status,
        retryAfter: f.retryAfter,
        details: f.details,
      );
    }
    return null;
  }

  // ------------------------------------------------------------- fixtures

  static AdminAccount account(
    String id, {
    String? name,
    String? last4,
    AccountStatus status = AccountStatus.active,
    int devices = 1,
  }) => AdminAccount(
    accountId: id,
    status: status,
    createdAt: DateTime.utc(2026, 9, 1, 10),
    activeDevices: devices,
    helixName: name,
    phoneLast4: last4,
    lastSeenOn: DateTime.utc(2026, 10, 1),
  );

  static AdminDevice device(
    String id, {
    String name = 'Pixel',
    DevicePlatform platform = DevicePlatform.android,
    bool active = true,
  }) => AdminDevice(
    deviceId: id,
    name: name,
    platform: platform,
    active: active,
    createdAt: DateTime.utc(2026, 9, 1),
    lastSeenOn: DateTime.utc(2026, 10, 1),
  );

  static AdminReport report(
    String id, {
    String subject = 'acct-1',
    ReportStatus status = ReportStatus.open,
    ReportCategory category = ReportCategory.spam,
    String? note,
  }) => AdminReport(
    reportId: id,
    reporter: 'reporter-0000000',
    subject: subject,
    category: category,
    status: status,
    createdAt: DateTime.utc(2026, 10, 1, 8),
    note: note,
  );
}

final class _Failure {
  _Failure(this.code, this.status, this.retryAfter, this.details, this.times);

  final ErrorCode code;
  final int? status;
  final Duration? retryAfter;
  final JsonMap? details;
  int? times;
}
