import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/kernel/jwt.dart';
import 'package:helix_remote_server/src/modules/admin/data/admin_store.dart';
import 'package:helix_remote_server/src/modules/admin/domain/password_hash.dart';
import 'package:helix_remote_server/src/modules/calls/api.dart';
import 'package:helix_remote_server/src/modules/identity/api.dart';
import 'package:helix_remote_server/src/modules/ops/api.dart';
import 'package:helix_remote_server/src/modules/people/api.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/jobs/jobs.dart';
import 'package:helix_remote_server/src/platform/module.dart';
import 'package:helix_remote_server/src/platform/observability/log.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:helix_remote_server/src/version.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The operator console's API: first-run setup, admin sign-in, accounts,
/// invites, reports, audit log, configuration, feature flags, logs and
/// purge. Every mutating action writes an audit row in its transaction.
/// Schema `admin`.
final class AdminModule extends ModuleBase implements ProvidesAuthentication {
  AdminModule(
    super.context, {
    required this.identity,
    required this.people,
    required this.ops,
    required this.calls,
  }) {
    _store = AdminStore(schema);
    _jwt = HmacJwt(
      keys: context.config.jwtKeys,
      activeKid: context.config.activeJwtKid,
    );
    _kdf = _kdfFrom(context.config.env, devMode: context.config.devMode);
    authenticator = _AdminAuthenticator(this);
  }

  final IdentityApi identity;
  final PeopleApi people;
  final OpsApi ops;
  final CallsApi calls;
  late final AdminStore _store;
  late final HmacJwt _jwt;
  late final Argon2Params _kdf;

  @override
  late final Authenticator authenticator;

  final Set<WebSocketChannel> _logSockets = {};

  static const sessionLifetime = Duration(hours: 12);
  static const audience = 'helix.admin';
  static const tokenType = 'admin';

  /// Per client address: 5 failures lock it for 15 minutes, doubling per
  /// further failure up to 24 hours.
  static const lockAfter = 5;
  static const firstLock = Duration(minutes: 15);
  static const maxLock = Duration(hours: 24);

  /// Global safety cap, whatever the addresses: 100 failures since the last
  /// success lock sign-in for 15 minutes (then the count restarts).
  static const globalLockAfter = 100;
  static const globalLock = Duration(minutes: 15);

  static final _setupLimit = RateLimitPolicy.per(
    'admin.setup',
    5,
    const Duration(hours: 1),
  );
  static final _statusLimit = RateLimitPolicy.per(
    'admin.status',
    60,
    const Duration(minutes: 1),
  );
  static final _signInLimit = RateLimitPolicy.per(
    'admin.sign_in',
    10,
    const Duration(minutes: 1),
  );

  /// `HELIX_ADMIN_KDF_MEMORY_KIB` may lower the Argon2id memory cost only in
  /// dev mode (tests); production never goes below the recommendation.
  static Argon2Params _kdfFrom(
    Map<String, String> env, {
    required bool devMode,
  }) {
    final configured = int.tryParse(env['HELIX_ADMIN_KDF_MEMORY_KIB'] ?? '');
    final rec = Argon2Params.recommended;
    if (configured == null) return rec;
    final memory = devMode
        ? math.max(configured, 64)
        : math.max(configured, rec.memoryKib);
    return Argon2Params(memoryKib: memory, iterations: rec.iterations);
  }

  @override
  String get name => 'admin';

  @override
  List<Migration> get migrations => adminMigrations;

  @override
  List<PeriodicJob> get periodic => [
    PeriodicJob(
      'admin.purge_sign_in_failures',
      const Duration(hours: 6),
      () => _store.purgeSignInFailures(context.db),
    ),
  ];

  @override
  void routes(RouteRegistry r) {
    r
      ..add(
        name,
        Routes.adminSetupStatus,
        _setupStatus,
        rateLimit: _statusLimit,
      )
      ..add(name, Routes.adminSetup, _setup, rateLimit: _setupLimit)
      ..add(name, Routes.adminSignIn, _signIn, rateLimit: _signInLimit)
      ..add(name, Routes.adminPassword, _changePassword)
      ..add(name, Routes.adminAccounts, _accounts)
      ..add(name, Routes.adminAccount, _account)
      ..add(name, Routes.adminSuspend, _suspend)
      ..add(name, Routes.adminUnsuspend, _unsuspend)
      ..add(name, Routes.adminBan, _ban)
      ..add(name, Routes.adminDeleteAccount, _deleteAccount)
      ..add(name, Routes.adminRevokeDevice, _revokeDevice)
      ..add(name, Routes.adminRecoveryCode, _recoveryCode)
      ..add(name, Routes.adminInvites, _invites)
      ..add(name, Routes.adminCreateInvite, _createInvite)
      ..add(name, Routes.adminCancelInvite, _cancelInvite)
      ..add(name, Routes.adminReports, _reports)
      ..add(name, Routes.adminResolveReport, _resolveReport)
      ..add(name, Routes.adminAudit, _auditLog)
      ..add(name, Routes.adminConfig, _config)
      ..add(name, Routes.adminSetConfig, _setConfig)
      ..add(name, Routes.adminFeatureFlags, _flags)
      ..add(name, Routes.adminSetFeatureFlag, _setFlag)
      ..add(name, Routes.adminLogs, _logs)
      ..add(name, Routes.adminLogStream, _logStream)
      ..add(name, Routes.adminPurge, _purge);
  }

  /// `HELIX_ADMIN_PASSWORD` creates the first admin on a fresh server, so a
  /// public server is never waiting for whoever calls setup first. It never
  /// replaces an existing password.
  @override
  Future<void> start() async {
    final seed = context.config.env['HELIX_ADMIN_PASSWORD'];
    if (seed == null || seed.isEmpty) return;
    if (await _store.configured(context.db)) return;
    if (seed.length < AdminPasswordRequest.minLength) {
      log.warn('admin_seed_ignored', {'why': 'too short'});
      return;
    }
    final hash = await PasswordHash.create(seed, _kdf);
    final created = await context.db.tx((tx) async {
      final id = Uuid.v7();
      if (!await _store.createFirst(tx, id, hash, context.clock.now())) {
        return false;
      }
      await _store.audit(tx, adminId: id, action: 'admin.seed');
      return true;
    });
    if (created) log.info('admin_seeded');
  }

  @override
  Future<void> stop() async {
    for (final ws in _logSockets.toList()) {
      await ws.sink.close(RealtimeCloseCode.goingAway, 'server shutting down');
    }
  }

  // ---------------------------------------------------------------- sessions

  AdminSession _issue(String adminId) {
    final now = context.clock.now();
    final expires = now.add(sessionLifetime);
    return AdminSession(
      token: _jwt.sign(
        audience: audience,
        type: tokenType,
        issuedAt: now,
        expiresAt: expires,
        claims: {'sub': adminId},
      ),
      expiresAt: expires,
    );
  }

  Future<AdminPrincipal?> _verify(String token) async {
    final payload = _jwt.verify(
      token,
      audience: audience,
      type: tokenType,
      now: context.clock.now(),
    );
    final sub = payload?['sub'];
    if (payload == null || sub is! String || !Uuid.isValid(sub)) return null;
    final admin = await _store.byId(context.db, sub);
    if (admin == null) return null;
    if (HmacJwt.issuedAtOf(payload).isBefore(admin.tokensValidAfter)) {
      return null;
    }
    return AdminPrincipal(adminId: admin.id);
  }

  static void _checkPassword(String password, String field) {
    if (password.length < AdminPasswordRequest.minLength ||
        password.length > AdminPasswordRequest.maxLength) {
      throw ApiError(
        ErrorCode.invalidField,
        message:
            'The password must be ${AdminPasswordRequest.minLength} to '
            '${AdminPasswordRequest.maxLength} characters.',
        details: {'field': field},
      );
    }
  }

  Future<Response> _setupStatus(HelixRequest q) async => jsonResponse(
    AdminSetupStatus(configured: await _store.configured(context.db)).toJson(),
  );

  Future<Response> _setup(HelixRequest q) async {
    final req = q.json(AdminPasswordRequest.fromJson);
    _checkPassword(req.password, 'password');
    if (await _store.configured(context.db)) {
      throw const ApiError(ErrorCode.alreadyExists, message: 'Setup is done.');
    }
    final hash = await PasswordHash.create(req.password, _kdf);
    final id = Uuid.v7();
    final created = await context.db.tx((tx) async {
      if (!await _store.createFirst(tx, id, hash, context.clock.now())) {
        return false;
      }
      await _store.audit(tx, adminId: id, action: 'admin.setup');
      return true;
    });
    if (!created) {
      throw const ApiError(ErrorCode.alreadyExists, message: 'Setup is done.');
    }
    log.info('admin_setup');
    return jsonResponse(_issue(id).toJson(), status: 201);
  }

  Future<Response> _signIn(HelixRequest q) async {
    final req = q.json(AdminPasswordRequest.fromJson);
    final admin = await _store.first(context.db);
    if (admin == null || req.password.length > AdminPasswordRequest.maxLength) {
      throw const ApiError(ErrorCode.invalidCredentials);
    }
    final locked = await context.db.tx(
      (tx) => _store.reserveAttempt(
        tx,
        admin.id,
        q.clientIp,
        perIp: lockAfter,
        firstLock: firstLock,
        maxLock: maxLock,
        global: globalLockAfter,
        globalLock: globalLock,
      ),
    );
    if (locked != null) {
      final wait = locked.difference(context.clock.now());
      throw ApiError(
        ErrorCode.passwordLocked,
        retryAfter: wait.isNegative ? Duration.zero : wait,
      );
    }
    if (!await admin.password.verify(req.password)) {
      log.warn('admin_sign_in_failed');
      throw const ApiError(ErrorCode.invalidCredentials);
    }
    await _store.recordSuccess(context.db, admin.id, q.clientIp);
    await _store.audit(context.db, adminId: admin.id, action: 'admin.sign_in');
    return jsonResponse(_issue(admin.id).toJson());
  }

  Future<Response> _changePassword(HelixRequest q) async {
    final req = q.json(ChangeAdminPasswordRequest.fromJson);
    _checkPassword(req.newPassword, 'new_password');
    final admin = (await _store.byId(context.db, q.admin.adminId))!;
    if (!await admin.password.verify(req.currentPassword)) {
      throw const ApiError(ErrorCode.invalidCredentials);
    }
    final hash = await PasswordHash.create(req.newPassword, _kdf);
    final now = context.clock.now();
    await context.db.tx((tx) async {
      await _store.setPassword(tx, admin.id, hash, now);
      await _store.audit(tx, adminId: admin.id, action: 'admin.password');
    });
    return jsonResponse(_issue(admin.id).toJson());
  }

  // ---------------------------------------------------------------- accounts

  PageRequest _page(HelixRequest q) =>
      PageRequest.fromQuery(q.raw.url.queryParameters);

  /// The optional `{reason}` body of suspend and ban.
  static String? _reason(HelixRequest q) {
    if (q.body == null || q.body!.isEmpty) return null;
    final reason = q.json(AdminActionRequest.fromJson).reason?.trim();
    if (reason != null && reason.length > AdminActionRequest.maxReasonLength) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'reason'},
      );
    }
    return reason == null || reason.isEmpty ? null : redactString(reason);
  }

  Future<void> _audit(
    SqlSession s,
    HelixRequest q,
    String action, {
    String? target,
    Map<String, String> details = const {},
  }) => _store.audit(
    s,
    adminId: q.admin.adminId,
    action: action,
    target: target,
    details: details,
  );

  Future<Response> _accounts(HelixRequest q) async {
    final statusWire = q.query('status');
    final status = statusWire == null
        ? null
        : AccountStatus.values.firstWhere(
            (s) => s.wire == statusWire && s != AccountStatus.unknown,
            orElse: () => throw const ApiError(
              ErrorCode.invalidField,
              details: {'field': 'status'},
            ),
          );
    final page = await identity.admin.accounts(
      context.db,
      page: _page(q),
      status: status,
      query: q.query('q'),
    );
    return jsonResponse(page.toJson((a) => a.toJson()));
  }

  Future<Response> _account(HelixRequest q) async {
    final id = q.uuidParam('account');
    final detail = await identity.admin.accountDetail(context.db, id);
    if (detail == null) throw const ApiError(ErrorCode.notFound);
    return jsonResponse(
      AdminAccountDetail(
        account: detail.account,
        devices: detail.devices,
        hasPassword: detail.hasPassword,
        openReports: await people.openReportsAbout(context.db, id),
      ).toJson(),
    );
  }

  Future<Response> _setSuspended(HelixRequest q, {required bool on}) async {
    final id = q.uuidParam('account');
    final reason = on ? _reason(q) : null;
    final found = await context.db.tx((tx) async {
      if (!await identity.admin.setSuspended(tx, id, suspended: on)) {
        return false;
      }
      await _audit(
        tx,
        q,
        on ? 'account.suspend' : 'account.unsuspend',
        target: id,
        details: {'reason': ?reason},
      );
      return true;
    });
    if (!found) throw const ApiError(ErrorCode.notFound);
    return noContent();
  }

  Future<Response> _suspend(HelixRequest q) => _setSuspended(q, on: true);

  Future<Response> _unsuspend(HelixRequest q) => _setSuspended(q, on: false);

  Future<Response> _ban(HelixRequest q) async {
    final id = q.uuidParam('account');
    final reason = _reason(q);
    final found = await context.db.tx((tx) async {
      if (!await identity.admin.ban(tx, id)) return false;
      await _audit(
        tx,
        q,
        'account.ban',
        target: id,
        details: {'reason': ?reason},
      );
      return true;
    });
    if (!found) throw const ApiError(ErrorCode.notFound);
    return noContent();
  }

  Future<Response> _deleteAccount(HelixRequest q) async {
    final id = q.uuidParam('account');
    final found = await context.db.tx((tx) async {
      if (await identity.account(tx, id) == null) return false;
      await identity.deleteAccount(tx, id);
      await _audit(tx, q, 'account.delete', target: id);
      return true;
    });
    if (!found) throw const ApiError(ErrorCode.notFound);
    return noContent();
  }

  Future<Response> _revokeDevice(HelixRequest q) async {
    final account = q.uuidParam('account');
    final device = q.uuidParam('device_id');
    final found = await context.db.tx((tx) async {
      if (!await identity.admin.revokeDevice(tx, account, device)) {
        return false;
      }
      await _audit(
        tx,
        q,
        'device.revoke',
        target: device,
        details: {'account_id': account},
      );
      return true;
    });
    if (!found) throw const ApiError(ErrorCode.notFound);
    return noContent();
  }

  Future<Response> _recoveryCode(HelixRequest q) async {
    final id = q.uuidParam('account');
    final code = await identity.admin.issueRecoveryCode(id);
    if (code == null) throw const ApiError(ErrorCode.notFound);
    await _audit(context.db, q, 'recovery_code.issue', target: id);
    return jsonResponse(code.toJson(), status: 201);
  }

  // ----------------------------------------------------------------- invites

  Future<Response> _invites(HelixRequest q) async {
    final page = await identity.admin.invites(context.db, page: _page(q));
    return jsonResponse(page.toJson((i) => i.toJson()));
  }

  Future<Response> _createInvite(HelixRequest q) async {
    final invite = await identity.admin.createInvite();
    await _audit(context.db, q, 'invite.create', target: invite.inviteId);
    return jsonResponse(invite.toJson(), status: 201);
  }

  Future<Response> _cancelInvite(HelixRequest q) async {
    final id = q.uuidParam('invite_id');
    if (!await identity.admin.cancelInvite(context.db, id)) {
      throw const ApiError(ErrorCode.notFound);
    }
    await _audit(context.db, q, 'invite.cancel', target: id);
    return noContent();
  }

  // ----------------------------------------------------------------- reports

  Future<Response> _reports(HelixRequest q) async {
    final statusWire = q.query('status');
    final status = statusWire == null
        ? null
        : ReportStatus.values.firstWhere(
            (s) => s.wire == statusWire && s != ReportStatus.unknown,
            orElse: () => throw const ApiError(
              ErrorCode.invalidField,
              details: {'field': 'status'},
            ),
          );
    final page = await people.reports(
      context.db,
      page: _page(q),
      status: status,
    );
    return jsonResponse(page.toJson((r) => r.toJson()));
  }

  Future<Response> _resolveReport(HelixRequest q) async {
    final id = q.uuidParam('report_id');
    final req = q.json(ResolveReportRequest.fromJson);
    final done = await context.db.tx((tx) async {
      if (!await people.resolveReport(tx, id, req.status)) return false;
      await _audit(tx, q, 'report.${req.status.wire}', target: id);
      return true;
    });
    if (!done) throw const ApiError(ErrorCode.notFound);
    return noContent();
  }

  Future<Response> _auditLog(HelixRequest q) async {
    final page = await _store.auditLog(context.db, page: _page(q));
    return jsonResponse(page.toJson((e) => e.toJson()));
  }

  // ------------------------------------------------------- config and flags

  AdminConfig _configOf(OpsSettings settings) => AdminConfig(
    serverName: settings.serverName,
    version: helixServerVersion,
    registration: context.config.globalMode
        ? RegistrationMode.phone
        : RegistrationMode.invite,
    maintenance: settings.maintenance,
    federationEnabled: settings.federationEnabled,
    maxAttachmentBytes: context.config.maxAttachmentBytes,
    nodeId: context.config.nodeId,
    federationDomain: settings.federationEnabled
        ? context.config.publicBaseUrl.host
        : null,
    integrations: _integrations(),
  );

  /// Which outside services are set up, by name. Reads the facades and the
  /// provider switches only: no key, address or secret leaves the process.
  AdminIntegrations _integrations() {
    String? named(String variable, bool configured) =>
        configured ? context.config.env[variable]?.trim() : null;
    return AdminIntegrations(
      push: AdminIntegrationStatus(
        configured: context.push.isConfigured,
        provider: named('HELIX_PUSH_PROVIDER', context.push.isConfigured),
      ),
      sms: AdminIntegrationStatus(
        configured: identity.smsConfigured,
        provider: named('HELIX_SMS_PROVIDER', identity.smsConfigured),
      ),
      turn: AdminIntegrationStatus(
        configured: calls.turnConfigured,
        count: calls.turnConfigured ? calls.turnUrlCount : null,
      ),
    );
  }

  Future<Response> _config(HelixRequest q) async =>
      jsonResponse(_configOf(await ops.settings()).toJson());

  Future<Response> _setConfig(HelixRequest q) async {
    final patch = q.json(AdminConfigPatch.fromJson);
    if (patch.isEmpty) {
      throw const ApiError(ErrorCode.badRequest, message: 'nothing to change');
    }
    final settings = await context.db.tx((tx) async {
      final updated = await ops.update(tx, patch);
      await _audit(
        tx,
        q,
        'config.update',
        details: {
          if (patch.serverName != null) 'server_name': patch.serverName!,
          if (patch.maintenance != null) 'maintenance': '${patch.maintenance}',
          if (patch.federationEnabled != null)
            'federation_enabled': '${patch.federationEnabled}',
        },
      );
      return updated;
    });
    return jsonResponse(_configOf(settings).toJson());
  }

  Future<Response> _flags(HelixRequest q) async =>
      jsonResponse(FeatureFlags(flags: (await ops.settings()).flags).toJson());

  Future<Response> _setFlag(HelixRequest q) async {
    final flag = q.param('name');
    if (!OpsApi.knownFlags.containsKey(flag)) {
      throw const ApiError(ErrorCode.notFound, message: 'unknown flag');
    }
    final req = q.json(SetFeatureFlagRequest.fromJson);
    await context.db.tx((tx) async {
      await ops.setFlag(tx, flag, req.enabled);
      await _audit(
        tx,
        q,
        'flag.set',
        target: flag,
        details: {'enabled': '${req.enabled}'},
      );
    });
    return noContent();
  }

  // -------------------------------------------------------------------- logs

  Future<Response> _logs(HelixRequest q) async {
    final limit = (int.tryParse(q.query('limit') ?? '') ?? 200).clamp(1, 500);
    return jsonResponse(
      AdminLogLines(lines: context.log.recent(limit)).toJson(),
    );
  }

  /// Live redacted log lines of this node as WS text frames.
  Future<Response> _logStream(HelixRequest q) async {
    final handler = webSocketHandler((WebSocketChannel ws, String? _) {
      _logSockets.add(ws);
      final lines = context.log.lines.listen(ws.sink.add);
      ws.stream.listen(
        (_) {},
        onDone: () {
          unawaited(lines.cancel());
          _logSockets.remove(ws);
        },
        onError: (Object _) {},
        cancelOnError: true,
      );
    }, pingInterval: const Duration(seconds: 30));
    return handler(q.raw);
  }

  Future<Response> _purge(HelixRequest q) async {
    final removed = {
      ...await identity.admin.purgeExpired(context.db),
      'dead_jobs': await context.outbox.purgeDead(context.db),
    };
    await _audit(
      context.db,
      q,
      'purge',
      details: {for (final e in removed.entries) e.key: '${e.value}'},
    );
    return jsonResponse(PurgeResult(removed: removed).toJson());
  }
}

final class _AdminAuthenticator implements Authenticator {
  _AdminAuthenticator(this._m);

  final AdminModule _m;

  @override
  Future<DevicePrincipal?> device(String bearerToken) async => null;

  @override
  Future<AdminPrincipal?> admin(String bearerToken) => _m._verify(bearerToken);

  @override
  Future<ServerPrincipal?> server(Request request, Uint8List body) async =>
      null;
}
