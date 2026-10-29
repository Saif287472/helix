import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/kernel/crypto.dart';
import 'package:helix_remote_server/src/kernel/jwt.dart';
import 'package:helix_remote_server/src/modules/admin/data/admin_store.dart';
import 'package:helix_remote_server/src/modules/admin/domain/local_address.dart';
import 'package:helix_remote_server/src/modules/admin/domain/password_hash.dart';
import 'package:helix_remote_server/src/modules/billing/api.dart';
import 'package:helix_remote_server/src/modules/calls/api.dart';
import 'package:helix_remote_server/src/modules/identity/api.dart';
import 'package:helix_remote_server/src/modules/ops/api.dart';
import 'package:helix_remote_server/src/modules/people/api.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/http/websocket_limits.dart';
import 'package:helix_remote_server/src/platform/jobs/jobs.dart';
import 'package:helix_remote_server/src/platform/module.dart';
import 'package:helix_remote_server/src/platform/observability/log.dart';
import 'package:helix_remote_server/src/platform/observability/metrics.dart';
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
    required this.billing,
  }) {
    _store = AdminStore(schema);
    // The console's tokens are signed with keys derived from the ring, so a
    // device-token key alone cannot mint an operator token (and the reverse).
    _jwt = HmacJwt(
      keys: {
        for (final e in context.config.jwtKeys.entries)
          e.key: _adminKey(e.value),
      },
      activeKid: context.config.activeJwtKid,
    );
    _authEvents = context.metrics.counter(
      'helix_admin_auth_events_total',
      'Operator console sign-in failures, locks and refused setups',
    );
    _kdf = _kdfFrom(context.config.env, devMode: context.config.devMode);
    authenticator = _AdminAuthenticator(this);
  }

  /// HMAC-SHA256(ring key, "helix.admin.v1"): a key of its own per ring key.
  static Uint8List _adminKey(Uint8List ringKey) =>
      hmacSha256(ringKey, utf8.encode('helix.admin.v1'));

  final IdentityApi identity;
  final PeopleApi people;
  final OpsApi ops;
  final CallsApi calls;
  final BillingApi billing;
  late final AdminStore _store;
  late final HmacJwt _jwt;
  late final Argon2Params _kdf;
  late final Counter _authEvents;

  @override
  late final Authenticator authenticator;

  /// Live log streams and the token each was opened with, re-checked every
  /// [logStreamRecheck] and at once after a sign-out or password change.
  final Map<WebSocketChannel, String> _logSockets = {};
  Timer? _logCheck;

  static const logStreamRecheck = Duration(seconds: 60);

  /// The console never sends on the log stream; anything bigger than this
  /// closes it before it is buffered.
  static const maxLogStreamMessageBytes = 1024;

  /// Audit rows older than this are deleted daily (the operator's choice).
  static const auditRetention = Duration(days: 365);

  static const sessionLifetime = Duration(hours: 12);

  /// How long a password re-entry keeps the risky actions open. The token it
  /// gives is a different JWT type from the session, so it opens nothing alone.
  static const stepUpLifetime = Duration(minutes: 10);
  static const stepUpType = 'admin_step_up';
  static const audience = 'helix.admin';
  static const tokenType = 'admin';

  /// Per client address: 5 failures lock it for 15 minutes, doubling per
  /// further failure up to 24 hours.
  static const lockAfter = 5;
  static const firstLock = Duration(minutes: 15);
  static const maxLock = Duration(hours: 24);

  /// Global safety cap: 100 failures since the last success, from addresses
  /// outside the local network, lock sign-in from those addresses for 15
  /// minutes (then the count restarts). This machine and the LAN are exempt
  /// ([isLocalNetworkAddress]), so nobody on the internet can lock the
  /// operator at home out (review B-08).
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
    PeriodicJob(
      'admin.purge_audit',
      const Duration(hours: 24),
      () => _store.purgeAudit(context.db, auditRetention),
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
      ..add(name, Routes.adminSignOut, _signOut)
      ..add(name, Routes.adminPassword, _changePassword)
      ..add(name, Routes.adminStepUp, _stepUp)
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
      ..add(name, Routes.adminPaymentRequests, _paymentRequests)
      ..add(name, Routes.adminApprovePaymentRequest, _approvePayment)
      ..add(name, Routes.adminRejectPaymentRequest, _rejectPayment)
      ..add(name, Routes.adminGrantPlan, _grantPlan)
      ..add(name, Routes.adminRevokePlan, _revokePlan)
      ..add(name, Routes.adminAccountPlan, _accountPlan)
      ..add(name, Routes.adminAccountCallTime, _accountCallTime)
      ..add(name, Routes.adminGrantCallTime, _grantCallTime)
      ..add(name, Routes.adminSetPlanOverride, _setPlanOverride)
      ..add(name, Routes.adminClearPlanOverride, _clearPlanOverride)
      ..add(name, Routes.adminBillingSummary, _billingSummary)
      ..add(name, Routes.adminBillingSettings, _billingSettings)
      ..add(name, Routes.adminSetBillingSettings, _setBillingSettings)
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
    _logCheck = Timer.periodic(logStreamRecheck, (_) {
      unawaited(
        recheckLogStreams().catchError((Object e) {
          log.warn('log_stream_check_failed', {
            'error': e.runtimeType.toString(),
          });
        }),
      );
    });
    final seed = context.config.env['HELIX_ADMIN_PASSWORD'];
    if (seed == null || seed.isEmpty) return;
    if (await _store.configured(context.db)) {
      // It never replaces a password; left in .env it is only a stale
      // plaintext secret (review B-07).
      log.warn('admin_seed_still_set', {
        'why': 'an admin exists; remove HELIX_ADMIN_PASSWORD from .env',
      });
      return;
    }
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
    _logCheck?.cancel();
    for (final ws in _logSockets.keys.toList()) {
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
    // The first operator is claimed from this machine or the local network
    // only; from elsewhere, `HELIX_ADMIN_PASSWORD` or `bin/admin_tool.dart`.
    if (!isLocalNetworkAddress(q.clientIp) || q.clientIpUntrusted) {
      _authEvents.inc({'kind': 'setup_refused'});
      throw const ApiError(
        ErrorCode.forbidden,
        message:
            'First-time setup is only open from this machine or its local '
            'network. Set HELIX_ADMIN_PASSWORD or use bin/admin_tool.dart.',
      );
    }
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
    // A peer that forwards for others without being a trusted proxy is a
    // proxy missing from HELIX_TRUSTED_PROXIES, so this address is every
    // client behind it: it is not exempted from the global cap as a LAN
    // host would be, and the operator is told (AUD-7-1).
    if (q.clientIpUntrusted) {
      log.warn('admin_untrusted_proxy', {
        'peer_is_local': isLocalNetworkAddress(q.clientIp),
      });
    }
    await _reserveAttempt(q, admin.id);
    if (!await admin.password.verify(req.password)) {
      _authEvents.inc({'kind': 'sign_in_failed'});
      log.warn('admin_sign_in_failed');
      throw const ApiError(ErrorCode.invalidCredentials);
    }
    await context.db.tx((tx) async {
      await _store.recordSuccess(tx, admin.id, q.clientIp);
      await _store.audit(tx, adminId: admin.id, action: 'admin.sign_in');
    });
    return jsonResponse(_issue(admin.id).toJson());
  }

  /// Counts a password attempt against the sign-in lock (per address, doubling,
  /// and the global cap) and throws `password_locked` while it is shut. Sign-in
  /// and a password change share it: a token alone cannot be used to guess the
  /// operator's password here without the same lock.
  Future<void> _reserveAttempt(HelixRequest q, String adminId) async {
    final locked = await context.db.tx(
      (tx) => _store.reserveAttempt(
        tx,
        adminId,
        q.clientIp,
        perIp: lockAfter,
        firstLock: firstLock,
        maxLock: maxLock,
        global: isLocalNetworkAddress(q.clientIp) && !q.clientIpUntrusted
            ? null
            : globalLockAfter,
        globalLock: globalLock,
      ),
    );
    if (locked != null) {
      _authEvents.inc({'kind': 'locked'});
      final wait = locked.difference(context.clock.now());
      throw ApiError(
        ErrorCode.passwordLocked,
        retryAfter: wait.isNegative ? Duration.zero : wait,
      );
    }
  }

  /// Re-entering the password for the risky actions (ban, delete, recovery
  /// codes, plan and call-time grants, payments, the pay-to numbers, flags,
  /// purge). It shares the sign-in lock, so a stolen session token cannot be
  /// used to guess the password any faster than sign-in allows.
  Future<Response> _stepUp(HelixRequest q) async {
    final req = q.json(AdminPasswordRequest.fromJson);
    final admin = (await _store.byId(context.db, q.admin.adminId))!;
    if (req.password.length > AdminPasswordRequest.maxLength) {
      throw const ApiError(ErrorCode.invalidCredentials);
    }
    await _reserveAttempt(q, admin.id);
    if (!await admin.password.verify(req.password)) {
      _authEvents.inc({'kind': 'step_up_failed'});
      log.warn('admin_step_up_failed');
      throw const ApiError(ErrorCode.invalidCredentials);
    }
    await context.db.tx((tx) async {
      await _store.recordSuccess(tx, admin.id, q.clientIp);
      await _audit(tx, q, 'admin.step_up');
    });
    final now = context.clock.now();
    final expires = now.add(stepUpLifetime);
    return jsonResponse(
      AdminSession(
        token: _jwt.sign(
          audience: audience,
          type: stepUpType,
          issuedAt: now,
          expiresAt: expires,
          claims: {'sub': admin.id},
        ),
        expiresAt: expires,
      ).toJson(),
    );
  }

  /// Refuses a risky action unless the request carries a live step-up token
  /// of this operator, issued after their sessions were last ended.
  Future<void> _requireStepUp(HelixRequest q) async {
    final token = q.raw.headers[HelixHeaders.stepUp];
    final payload = token == null
        ? null
        : _jwt.verify(
            token,
            audience: audience,
            type: stepUpType,
            now: context.clock.now(),
          );
    var ok = payload != null && payload['sub'] == q.admin.adminId;
    if (ok) {
      final admin = await _store.byId(context.db, q.admin.adminId);
      ok =
          admin != null &&
          !HmacJwt.issuedAtOf(payload).isBefore(admin.tokensValidAfter);
    }
    if (!ok) {
      throw const ApiError(
        ErrorCode.stepUpRequired,
        message: 'Enter your password to continue.',
      );
    }
  }

  /// Ends every session of this operator, this one included: the console's
  /// "Sign out", and the way to cut off a token that may have leaked (review
  /// B-02). Open log streams close at once.
  Future<Response> _signOut(HelixRequest q) async {
    final id = q.admin.adminId;
    await context.db.tx((tx) async {
      await _store.endSessions(tx, id, context.clock.now());
      await _audit(tx, q, 'admin.sign_out');
    });
    await recheckLogStreams();
    return noContent();
  }

  /// `bin/admin_tool.dart reset-password`: sets the operator's password
  /// (creating the operator if there is none), ends every admin session and
  /// clears every sign-in lock, with an audit row (review B-07). Throws
  /// `invalid_field` for a password outside 12 to 256 characters.
  Future<void> resetPassword(String password) async {
    _checkPassword(password, 'password');
    final hash = await PasswordHash.create(password, _kdf);
    final now = context.clock.now();
    await context.db.tx((tx) async {
      final admin = await _store.first(tx);
      if (admin == null) {
        final id = Uuid.v7();
        await _store.createFirst(tx, id, hash, now);
        await _store.audit(
          tx,
          adminId: id,
          action: 'admin.password_reset',
          details: {'by': 'admin_tool', 'created': 'true'},
        );
        return;
      }
      await _store.setPassword(tx, admin.id, hash, now);
      await _store.clearSignInFailures(tx);
      await _store.audit(
        tx,
        adminId: admin.id,
        action: 'admin.password_reset',
        details: {'by': 'admin_tool'},
      );
    });
  }

  Future<Response> _changePassword(HelixRequest q) async {
    final req = q.json(ChangeAdminPasswordRequest.fromJson);
    _checkPassword(req.newPassword, 'new_password');
    final admin = (await _store.byId(context.db, q.admin.adminId))!;
    await _reserveAttempt(q, admin.id);
    if (!await admin.password.verify(req.currentPassword)) {
      _authEvents.inc({'kind': 'password_change_failed'});
      log.warn('admin_password_change_failed');
      throw const ApiError(ErrorCode.invalidCredentials);
    }
    await context.db.tx((tx) => _store.recordSuccess(tx, admin.id, q.clientIp));
    final hash = await PasswordHash.create(req.newPassword, _kdf);
    final now = context.clock.now();
    await context.db.tx((tx) async {
      await _store.setPassword(tx, admin.id, hash, now);
      await _store.audit(tx, adminId: admin.id, action: 'admin.password');
    });
    await recheckLogStreams();
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
    final names = await people.displayNames(context.db, [
      for (final a in page.items) a.accountId,
    ]);
    return jsonResponse(
      page.toJson((a) => a.copyWith(displayName: names[a.accountId]).toJson()),
    );
  }

  Future<Response> _account(HelixRequest q) async {
    final id = q.uuidParam('account');
    final detail = await identity.admin.accountDetail(context.db, id);
    if (detail == null) throw const ApiError(ErrorCode.notFound);
    final names = await people.displayNames(context.db, [id]);
    return jsonResponse(
      AdminAccountDetail(
        account: detail.account.copyWith(displayName: names[id]),
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
    await _requireStepUp(q);
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
    await _requireStepUp(q);
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
    await _requireStepUp(q);
    final id = q.uuidParam('account');
    final code = await context.db.tx((tx) async {
      final code = await identity.admin.issueRecoveryCode(tx, id);
      if (code != null) {
        await _audit(tx, q, 'recovery_code.issue', target: id);
      }
      return code;
    });
    if (code == null) throw const ApiError(ErrorCode.notFound);
    return jsonResponse(code.toJson(), status: 201);
  }

  // ----------------------------------------------------------------- invites

  Future<Response> _invites(HelixRequest q) async {
    final page = await identity.admin.invites(context.db, page: _page(q));
    return jsonResponse(page.toJson((i) => i.toJson()));
  }

  Future<Response> _createInvite(HelixRequest q) async {
    final invite = await context.db.tx((tx) async {
      final invite = await identity.admin.createInvite(tx);
      await _audit(tx, q, 'invite.create', target: invite.inviteId);
      return invite;
    });
    return jsonResponse(invite.toJson(), status: 201);
  }

  Future<Response> _cancelInvite(HelixRequest q) async {
    final id = q.uuidParam('invite_id');
    final cancelled = await context.db.tx((tx) async {
      if (!await identity.admin.cancelInvite(tx, id)) return false;
      await _audit(tx, q, 'invite.cancel', target: id);
      return true;
    });
    if (!cancelled) throw const ApiError(ErrorCode.notFound);
    return noContent();
  }

  // ----------------------------------------------------------------- billing

  Future<Response> _paymentRequests(HelixRequest q) async {
    final wire = q.query('status') ?? PaymentRequestStatus.pending.wire;
    final status = PaymentRequestStatus.values.firstWhere(
      (s) => s.wire == wire && s != PaymentRequestStatus.unknown,
      orElse: () => throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'status'},
      ),
    );
    final page = await billing.requestsByStatus(
      context.db,
      status: status,
      page: _page(q),
    );
    // The operator reads the person the way the accounts list shows them
    // (ADR-030), which is what lets them match a bKash sender to an account.
    final ids = {for (final r in page.items) r.accountId};
    final display = await people.displayNames(context.db, ids);
    final helix = await identity.admin.helixNames(context.db, ids);
    final numbers = await identity.admin.phoneNumbers(context.db, ids);
    return jsonResponse(
      page.toJson((r) {
        final shown = (display[r.accountId] ?? '').trim();
        return AdminPaymentRequest(
          request: r.info,
          accountId: r.accountId,
          accountName: shown.isEmpty ? helix[r.accountId] : shown,
          accountPhone: numbers[r.accountId],
        ).toJson();
      }),
    );
  }

  Future<Response> _approvePayment(HelixRequest q) async {
    await _requireStepUp(q);
    final id = q.uuidParam('request_id');
    await context.db.tx((tx) async {
      final change = await billing.approve(tx, id);
      await _audit(
        tx,
        q,
        'payment_request.approve',
        target: id,
        details: {'account': change.accountId, 'months': '${change.months}'},
      );
    });
    return noContent();
  }

  Future<Response> _rejectPayment(HelixRequest q) async {
    final id = q.uuidParam('request_id');
    final req = q.json(RejectPaymentRequest.fromJson);
    await context.db.tx((tx) async {
      final account = await billing.reject(tx, id, req.reason);
      await _audit(
        tx,
        q,
        'payment_request.reject',
        target: id,
        details: {'account': account},
      );
    });
    return noContent();
  }

  Future<Response> _grantPlan(HelixRequest q) async {
    await _requireStepUp(q);
    final id = q.uuidParam('account');
    final req = q.json(GrantPlanRequest.fromJson);
    await context.db.tx((tx) async {
      if (await identity.admin.accountDetail(tx, id) == null) {
        throw const ApiError(ErrorCode.notFound);
      }
      await billing.grant(tx, id, req.months);
      await _audit(
        tx,
        q,
        'plan.grant',
        target: id,
        details: {'months': '${req.months}'},
      );
    });
    return noContent();
  }

  Future<Response> _revokePlan(HelixRequest q) async {
    await _requireStepUp(q);
    final id = q.uuidParam('account');
    await context.db.tx((tx) async {
      if (!await billing.revoke(tx, id)) {
        throw const ApiError(ErrorCode.notFound);
      }
      await _audit(tx, q, 'plan.revoke', target: id);
    });
    return noContent();
  }

  Future<Response> _accountPlan(HelixRequest q) async {
    final id = q.uuidParam('account');
    if (await identity.admin.accountDetail(context.db, id) == null) {
      throw const ApiError(ErrorCode.notFound);
    }
    return jsonResponse((await billing.accountPlan(context.db, id)).toJson());
  }

  Future<Response> _accountCallTime(HelixRequest q) async {
    final id = q.uuidParam('account');
    if (await identity.admin.accountDetail(context.db, id) == null) {
      throw const ApiError(ErrorCode.notFound);
    }
    return jsonResponse((await billing.callTime(id)).toJson());
  }

  Future<Response> _grantCallTime(HelixRequest q) async {
    await _requireStepUp(q);
    final id = q.uuidParam('account');
    final req = q.json(GrantCallTimeRequest.fromJson);
    await context.db.tx((tx) async {
      if (await identity.admin.accountDetail(tx, id) == null) {
        throw const ApiError(ErrorCode.notFound);
      }
      await billing.grantCallTime(
        tx,
        id,
        voice: req.voiceMinutes,
        video: req.videoMinutes,
      );
      await _audit(
        tx,
        q,
        'call_time.grant',
        target: id,
        details: {
          'voice': '${req.voiceMinutes}',
          'video': '${req.videoMinutes}',
          'reason': req.reason,
        },
      );
    });
    return noContent();
  }

  PlanLimitKey _limitKey(HelixRequest q) => PlanLimitKey.values.firstWhere(
    (k) => k.wire == q.param('key') && k != PlanLimitKey.unknown,
    orElse: () => throw const ApiError(ErrorCode.notFound),
  );

  Future<Response> _setPlanOverride(HelixRequest q) async {
    await _requireStepUp(q);
    final id = q.uuidParam('account');
    final key = _limitKey(q);
    final req = q.json(SetPlanOverrideRequest.fromJson);
    if (req.value < key.min || req.value > key.max) {
      throw ApiError(
        ErrorCode.invalidField,
        message: '${key.wire} must be between ${key.min} and ${key.max}',
        details: const {'field': 'value'},
      );
    }
    final days = req.days;
    await context.db.tx((tx) async {
      if (await identity.admin.accountDetail(tx, id) == null) {
        throw const ApiError(ErrorCode.notFound);
      }
      await billing.setOverride(
        tx,
        id,
        key: key,
        value: req.value,
        reason: req.reason,
        expiresAt: days == null
            ? null
            : context.clock.now().add(Duration(days: days)),
      );
      await _audit(
        tx,
        q,
        'plan.override',
        target: id,
        details: {
          'key': key.wire,
          'value': '${req.value}',
          'days': days == null ? 'until removed' : '$days',
        },
      );
    });
    return noContent();
  }

  Future<Response> _clearPlanOverride(HelixRequest q) async {
    final id = q.uuidParam('account');
    final key = _limitKey(q);
    await context.db.tx((tx) async {
      if (!await billing.clearOverride(tx, id, key)) {
        throw const ApiError(ErrorCode.notFound);
      }
      await _audit(
        tx,
        q,
        'plan.override_clear',
        target: id,
        details: {'key': key.wire},
      );
    });
    return noContent();
  }

  Future<Response> _billingSummary(HelixRequest q) async =>
      jsonResponse((await billing.summary(context.db)).toJson());

  Future<Response> _billingSettings(HelixRequest q) async =>
      jsonResponse((await billing.settings(context.db)).toJson());

  Future<Response> _setBillingSettings(HelixRequest q) async {
    await _requireStepUp(q);
    final next = q.json(BillingSettings.fromJson);
    await context.db.tx((tx) async {
      await billing.setSettings(tx, next);
      // The numbers people pay to are not written to the audit row.
      await _audit(
        tx,
        q,
        'billing.settings',
        details: {
          'prices':
              '${next.priceOneMonth}/${next.priceSixMonths}/${next.priceTwelveMonths}',
          'bkash': next.bkashNumber == null ? 'off' : 'set',
          'nagad': next.nagadNumber == null ? 'off' : 'set',
        },
      );
    });
    return jsonResponse(next.toJson());
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
    // A report row is two account ids. The operator reads the people behind
    // them exactly as the accounts list does - the name they keep, else the
    // `~Helix name` they chose, and the number identity unseals (ADR-030) -
    // so the console can act on a report without a second lookup per row.
    final ids = {
      for (final r in page.items) ...[r.reporter, r.subject],
    };
    final display = await people.displayNames(context.db, ids);
    final helix = await identity.admin.helixNames(context.db, ids);
    final names = {
      for (final id in ids)
        id: ((display[id] ?? '').trim().isEmpty ? helix[id] : display[id]),
    };
    final numbers = await identity.admin.phoneNumbers(context.db, ids);
    return jsonResponse(
      page.toJson(
        (r) => r
            .copyWith(
              reporterName: names[r.reporter],
              reporterPhone: numbers[r.reporter],
              subjectName: names[r.subject],
              subjectPhone: numbers[r.subject],
            )
            .toJson(),
      ),
    );
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
    await _requireStepUp(q);
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

  /// Live redacted log lines of this node as WS text frames. The token is
  /// checked again every [logStreamRecheck] and after a sign-out or password
  /// change: a stream does not outlive its session (review B-03).
  Future<Response> _logStream(HelixRequest q) async {
    // The route authenticated this bearer token; keep it to re-check.
    final token = q.raw.headers[HelixHeaders.authorization]!
        .substring(7)
        .trim();
    final handler = webSocketHandler((WebSocketChannel ws, String? _) {
      _logSockets[ws] = token;
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
    return handler(
      limitWebSocketFrames(q.raw, maxMessageBytes: maxLogStreamMessageBytes),
    );
  }

  /// Closes every live log stream whose token no longer verifies (expired,
  /// signed out, password changed) with 4001. Public for tests.
  Future<void> recheckLogStreams() async {
    for (final MapEntry(key: ws, value: token)
        in _logSockets.entries.toList()) {
      if (await _verify(token) != null) continue;
      _logSockets.remove(ws);
      await ws.sink.close(RealtimeCloseCode.unauthorized, 'session ended');
    }
  }

  Future<Response> _purge(HelixRequest q) async {
    await _requireStepUp(q);
    final removed = await context.db.tx((tx) async {
      final removed = {
        ...await identity.admin.purgeExpired(tx),
        'dead_jobs': await context.outbox.purgeDead(tx),
      };
      await _audit(
        tx,
        q,
        'purge',
        details: {for (final e in removed.entries) e.key: '${e.value}'},
      );
      return removed;
    });
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
