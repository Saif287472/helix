import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/kernel/entitlements.dart';
import 'package:helix_remote_server/src/modules/billing/api.dart';
import 'package:helix_remote_server/src/modules/billing/application/call_time_service.dart';
import 'package:helix_remote_server/src/modules/billing/data/billing_store.dart';
import 'package:helix_remote_server/src/modules/billing/data/call_time_store.dart';
import 'package:helix_remote_server/src/modules/identity/api.dart';
import 'package:helix_remote_server/src/modules/ops/api.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/jobs/jobs.dart';
import 'package:helix_remote_server/src/platform/push/push.dart';
import 'package:helix_remote_server/src/platform/module.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:shelf/shelf.dart';

/// Plans and manual payments (ADR-035). Schema `billing`.
///
/// Everything is off until the operator sets the flag `billing_enabled`:
/// then every account's [Entitlements] are Free's or Premium's, and before
/// that they are the limits the server always had.
final class BillingModule extends ModuleBase
    implements ProvidesAccountExport, BillingApi {
  BillingModule(super.context, {required this.ops, required this.identity})
    : _store = BillingStore(context.schema('billing')) {
    _wakes = PushTrail(log, context.metrics);
    _calls = CallTimeService(
      db: context.db,
      store: CallTimeStore(context.schema('billing')),
      clock: context.clock,
      isMetered: (accountId) async =>
          await enabled() && !(await forAccount(accountId)).unlimitedCalls,
    );
  }

  final OpsApi ops;

  /// Identity is built after billing (it asks billing for device limits), so
  /// the facade is read when the server starts, not when this is made.
  final IdentityApi Function() identity;

  final BillingStore _store;
  late final PushTrail _wakes;
  late final CallTimeService _calls;

  /// The outbox job that wakes one device after its plan changed.
  static const pushJob = 'billing.push';

  static const flagName = 'billing_enabled';

  /// A pending request nobody answers expires after this long.
  static const requestLifetime = Duration(
    days: BillingLimits.requestLifetimeDays,
  );
  static const grace = Duration(days: BillingLimits.graceDays);

  /// Decided requests are kept a year.
  static const requestRetention = Duration(days: 365);

  static final _claimLimit = RateLimitPolicy.per(
    'billing.call_claims',
    20,
    const Duration(days: 1),
  );

  static final _submitLimit = RateLimitPolicy.per(
    'billing.requests',
    10,
    const Duration(hours: 1),
  );

  // The prices and numbers a fresh server starts with (taka).
  static const _defaultPrices = {1: 20, 6: 100, 12: 180};

  @override
  String get name => 'billing';

  @override
  List<Migration> get migrations => billingMigrations;

  @override
  Map<String, JobHandler> get jobs => {pushJob: _push};

  @override
  List<PeriodicJob> get periodic => [
    PeriodicJob('billing.expire_requests', const Duration(hours: 1), () async {
      final now = context.clock.now();
      await _store.expirePending(context.db, now.subtract(requestLifetime));
      await _store.purgeDecided(context.db, now.subtract(requestRetention));
      await _store.purgeExpiredOverrides(context.db, now);
    }),
    PeriodicJob('billing.settle_calls', const Duration(minutes: 1), () async {
      await _calls.settleDue();
    }),
    PeriodicJob('billing.purge_calls', const Duration(hours: 6), () async {
      final cutoff = context.clock.now().subtract(const Duration(days: 7));
      await _calls.store.purgeClaims(context.db, cutoff);
      await _calls.store.purgeReservations(context.db, cutoff);
    }),
  ];

  @override
  Future<void> start() async {
    identity()
      ..onAccountDeleted((tx, accountId) async {
        await _store.deleteAccount(tx, accountId);
        await _calls.store.deleteAccount(tx, accountId);
      })
      ..onDeviceAdded((tx, device, _) => _startTrial(tx, device));
  }

  @override
  void routes(RouteRegistry r) {
    r
      ..add(name, Routes.billingPlan, _plan, allowSuspended: true)
      ..add(name, Routes.submitPaymentRequest, _submit, rateLimit: _submitLimit)
      ..add(name, Routes.paymentRequests, _requests)
      ..add(name, Routes.callTime, _callTimeRoute, allowSuspended: true)
      ..add(name, Routes.claimCallTime, _claimRoute, rateLimit: _claimLimit);
  }

  BillingApi get api => this;

  // ---------------------------------------------------------- entitlements

  @override
  Future<bool> enabled() => ops.flag(flagName);

  @override
  Future<Entitlements> forAccount(String accountId) async {
    final base = context.config.maxAttachmentBytes;
    if (!await enabled()) {
      return Entitlements.standard(maxAttachmentBytes: base);
    }
    final now = context.clock.now();
    final sub = await _store.subscription(context.db, accountId);
    final plan = sub != null && now.isBefore(sub.time('period_end').add(grace))
        ? Entitlements.premium(maxAttachmentBytes: base)
        : Entitlements.free(maxAttachmentBytes: base);
    return plan.withOverrides(
      await _store.activeOverrides(context.db, accountId, now),
    );
  }

  /// A new account's first week of Premium, once per phone number (and never
  /// for an account that already has Premium time). Runs inside the
  /// transaction that adds the account's first device.
  Future<void> _startTrial(Tx tx, DeviceRecord device) async {
    final accountId = device.accountId;
    if (!await enabled()) return;
    if (await _store.subscription(tx, accountId) != null) return;
    // New accounts only: the trial starts with an account's first device. An
    // account that already has one (or had Premium) adding another is not new.
    if ((await identity().activeDevices(tx, accountId)).length != 1) return;
    final number = await identity().phoneHash(tx, accountId);
    if (number == null) return;
    final now = context.clock.now();
    if (!await _store.recordTrial(tx, number, now)) return;
    await _store.extend(
      tx,
      accountId,
      days: BillingLimits.trialDays,
      source: 'trial',
      now: now,
    );
  }

  // ------------------------------------------------------------- settings

  @override
  Future<BillingSettings> settings(SqlSession s) async {
    final stored = await _store.settings(s);
    int price(int months) =>
        int.tryParse(stored['price_$months'] ?? '') ?? _defaultPrices[months]!;
    return BillingSettings(
      priceOneMonth: price(1),
      priceSixMonths: price(6),
      priceTwelveMonths: price(12),
      bkashNumber: stored['bkash_number'],
      nagadNumber: stored['nagad_number'],
    );
  }

  @override
  Future<void> setSettings(Tx tx, BillingSettings settings) async {
    await _store.putSetting(tx, 'price_1', '${settings.priceOneMonth}');
    await _store.putSetting(tx, 'price_6', '${settings.priceSixMonths}');
    await _store.putSetting(tx, 'price_12', '${settings.priceTwelveMonths}');
    await _store.putSetting(tx, 'bkash_number', settings.bkashNumber);
    await _store.putSetting(tx, 'nagad_number', settings.nagadNumber);
  }

  // ----------------------------------------------------------- the plan page

  @override
  Future<BillingPlan> planFor(String accountId) async {
    final base = context.config.maxAttachmentBytes;
    final on = await enabled();
    final entitlements = await forAccount(accountId);
    final current = await settings(context.db);
    final prices = [
      for (final months in BillingLimits.durations)
        PlanPrice(
          months: months,
          price: current.priceFor(months),
          listPrice: months * current.priceOneMonth,
        ),
    ];
    final targets = [
      if (current.bkashNumber != null)
        PaymentTarget(
          method: PaymentMethod.bkash,
          number: current.bkashNumber!,
        ),
      if (current.nagadNumber != null)
        PaymentTarget(
          method: PaymentMethod.nagad,
          number: current.nagadNumber!,
        ),
    ];
    final sub = await _store.subscription(context.db, accountId);
    final end = sub?.time('period_end');
    final premium = entitlements.plan == PlanId.premium;
    final now = context.clock.now();
    return BillingPlan(
      enabled: on,
      plan: entitlements.plan,
      periodEnd: premium ? end : null,
      inGrace: premium && end != null && !now.isBefore(end),
      onTrial:
          premium && sub?.string('source') == 'trial' && !now.isAfter(end!),
      limits: on
          ? entitlements.toLimits()
          : Entitlements.standard(maxAttachmentBytes: base).toLimits(),
      premiumLimits: Entitlements.premium(maxAttachmentBytes: base).toLimits(),
      prices: prices,
      paymentTargets: on ? targets : const [],
      openRequest: await _store.openRequest(context.db, accountId),
      lastRequest: await _store.lastDecided(context.db, accountId),
    );
  }

  Future<Response> _plan(HelixRequest q) async =>
      jsonResponse((await planFor(q.device.accountId)).toJson());

  // -------------------------------------------------------------- call time

  @override
  Future<CallTime> callTime(String accountId) => _calls.balance(accountId);

  @override
  Future<CallTime> claimCallTime(String accountId) => _calls.claim(accountId);

  @override
  Future<CallGrant> grantCall({
    required String accountId,
    required String callId,
    required CallRole role,
    required CallPool pool,
    String? roomId,
    bool callerIsRemote = false,
  }) async {
    // A server without plans does not meter, and keeps no record of calls.
    if (!await enabled()) {
      return CallGrant(
        metered: false,
        expiresAt: context.clock.now().add(CallTimeLimits.unmeteredLifetime),
        pool: pool,
      );
    }
    return _calls.grant(
      accountId: accountId,
      callId: callId,
      role: role,
      pool: pool,
      roomId: roomId,
      callerIsRemote: callerIsRemote,
    );
  }

  @override
  Future<void> callEnded(String callId) async {
    if (await enabled()) await _calls.callEnded(callId);
  }

  Future<Response> _callTimeRoute(HelixRequest q) async =>
      jsonResponse((await callTime(q.device.accountId)).toJson());

  Future<Response> _claimRoute(HelixRequest q) async {
    final result = await claimCallTime(q.device.accountId);
    log.info('call_time_claimed', {'account_id': q.device.accountId});
    return jsonResponse(result.toJson());
  }

  // -------------------------------------------------------------- requests

  @override
  Future<PaymentRequestInfo> submitRequest(
    String accountId,
    SubmitPaymentRequest request,
  ) async {
    if (!await enabled()) {
      throw const ApiError(
        ErrorCode.unavailable,
        message: 'Plans are not available yet.',
      );
    }
    if (!BillingLimits.durations.contains(request.months)) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'months'},
      );
    }
    if (request.method == PaymentMethod.unknown) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'method'},
      );
    }
    final trx = BillingLimits.normalizeTrxId(request.trxId);
    if (trx == null) {
      throw const ApiError(
        ErrorCode.invalidField,
        message: 'That does not look like a transaction ID.',
        details: {'field': 'trx_id'},
      );
    }
    final current = await settings(context.db);
    final number = switch (request.method) {
      PaymentMethod.bkash => current.bkashNumber,
      PaymentMethod.nagad => current.nagadNumber,
      PaymentMethod.unknown => null,
    };
    if (number == null) {
      throw const ApiError(
        ErrorCode.unavailable,
        message: 'That way of paying is not available.',
      );
    }
    try {
      return await context.db.tx(
        (tx) => _store.insertRequest(
          tx,
          id: Uuid.v7(),
          accountId: accountId,
          months: request.months,
          amount: current.priceFor(request.months),
          method: request.method,
          trxId: trx,
          now: context.clock.now(),
        ),
      );
    } on DbConstraintViolation catch (e) {
      if (e.kind != DbConstraintKind.unique) rethrow;
      final open = (e.constraint ?? '').contains('open');
      throw ApiError(
        ErrorCode.conflict,
        message: open
            ? 'You already have a request waiting for approval.'
            : 'That transaction ID was already used.',
        details: {'reason': open ? 'request_open' : 'trx_id_used'},
      );
    }
  }

  Future<Response> _submit(HelixRequest q) async {
    final created = await submitRequest(
      q.device.accountId,
      q.json(SubmitPaymentRequest.fromJson),
    );
    log.info('payment_request_submitted', {
      'account_id': q.device.accountId,
      'months': created.months,
      'method': created.method.wire,
    });
    return jsonResponse(created.toJson(), status: 201);
  }

  @override
  Future<Page<PaymentRequestInfo>> requestsOf(
    String accountId, {
    required PageRequest page,
  }) => _store.requestsOf(context.db, accountId, page: page);

  Future<Response> _requests(HelixRequest q) async {
    final page = await requestsOf(
      q.device.accountId,
      page: PageRequest.fromQuery(q.raw.url.queryParameters),
    );
    return jsonResponse(page.toJson((r) => r.toJson()));
  }

  // ------------------------------------------------------------------ admin

  @override
  Future<Page<PaymentRequestEntry>> requestsByStatus(
    SqlSession s, {
    required PaymentRequestStatus status,
    required PageRequest page,
  }) async {
    final rows = await _store.requestsByStatus(s, status: status, page: page);
    return Page(
      items: [
        for (final r in rows.items)
          PaymentRequestEntry(accountId: r.accountId, info: r.info),
      ],
      nextCursor: rows.nextCursor,
    );
  }

  @override
  Future<PlanChange> approve(Tx tx, String requestId) async {
    final row = await _store.requestForUpdate(tx, requestId);
    if (row == null) throw const ApiError(ErrorCode.notFound);
    if (row.info.status != PaymentRequestStatus.pending) {
      throw const ApiError(
        ErrorCode.conflict,
        message: 'That request was already decided.',
      );
    }
    final now = context.clock.now();
    await _store.decide(
      tx,
      requestId,
      status: PaymentRequestStatus.approved,
      now: now,
    );
    final end = await _store.extend(
      tx,
      row.accountId,
      months: row.info.months,
      source: 'payment',
      now: now,
    );
    await _wake(tx, row.accountId);
    return PlanChange(
      accountId: row.accountId,
      months: row.info.months,
      periodEnd: end,
    );
  }

  @override
  Future<String> reject(Tx tx, String requestId, String reason) async {
    final row = await _store.requestForUpdate(tx, requestId);
    if (row == null) throw const ApiError(ErrorCode.notFound);
    if (row.info.status != PaymentRequestStatus.pending) {
      throw const ApiError(
        ErrorCode.conflict,
        message: 'That request was already decided.',
      );
    }
    await _store.decide(
      tx,
      requestId,
      status: PaymentRequestStatus.rejected,
      now: context.clock.now(),
      reason: reason.trim(),
    );
    await _wake(tx, row.accountId);
    return row.accountId;
  }

  @override
  Future<PlanChange> grant(Tx tx, String accountId, int months) async {
    final end = await _store.extend(
      tx,
      accountId,
      months: months,
      source: 'admin',
      now: context.clock.now(),
    );
    await _wake(tx, accountId);
    return PlanChange(accountId: accountId, months: months, periodEnd: end);
  }

  @override
  Future<bool> revoke(Tx tx, String accountId) async {
    final ended = await _store.endNow(tx, accountId);
    if (ended) await _wake(tx, accountId);
    return ended;
  }

  // ------------------------------------------------------- operator's views

  @override
  Future<AdminAccountPlan> accountPlan(SqlSession s, String accountId) async {
    final now = context.clock.now();
    final entitlements = await forAccount(accountId);
    final sub = await _store.subscription(s, accountId);
    final end = sub?.time('period_end');
    final premium = entitlements.plan == PlanId.premium;
    return AdminAccountPlan(
      plan: entitlements.plan,
      periodEnd: end,
      source: sub?.string('source'),
      inGrace: premium && end != null && !now.isBefore(end),
      limits: entitlements.toLimits(),
      overrides: await _store.overridesOf(s, accountId, now),
    );
  }

  @override
  Future<void> setOverride(
    Tx tx,
    String accountId, {
    required PlanLimitKey key,
    required int value,
    required String reason,
    DateTime? expiresAt,
  }) async {
    await _store.putOverride(
      tx,
      accountId,
      key: key,
      value: value,
      reason: reason.trim(),
      expiresAt: expiresAt,
    );
    await _wake(tx, accountId);
  }

  @override
  Future<bool> clearOverride(Tx tx, String accountId, PlanLimitKey key) async {
    final cleared = await _store.clearOverride(tx, accountId, key);
    if (cleared) await _wake(tx, accountId);
    return cleared;
  }

  @override
  Future<BillingSummary> summary(SqlSession s) =>
      _store.summary(s, now: context.clock.now(), grace: grace);

  // ------------------------------------------------------------------- wake

  /// Wakes the account's devices so they read the plan again (and, for a
  /// decided request, tell the person). The wake-up says nothing about what
  /// changed. Queued in [tx], so a rolled-back decision wakes nobody.
  Future<void> _wake(Tx tx, String accountId) async {
    final devices = await identity().activeDevices(tx, accountId);
    if (devices.isEmpty) return;
    await context.outbox.enqueueMany(tx, [
      for (final d in devices)
        QueuedJob(
          pushJob,
          {'device': d.id},
          maxAttempts: 3,
          dedupeKey: 'plan:$accountId:${d.id}',
        ),
    ]);
  }

  Future<void> _push(Map<String, Object?> payload) async {
    final device = payload['device']! as String;
    const reason = PushReason.plan;
    final target = await identity().pushTarget(context.db, device);
    if (target == null) {
      _wakes.record(PushOutcome.noToken, reason, device);
      return;
    }
    if (!context.push.isConfigured) {
      _wakes.record(PushOutcome.providerOff, reason, device);
      return;
    }
    try {
      await context.push.send(
        token: target.token,
        kind: target.kind.wire,
        reason: reason,
      );
      _wakes.record(PushOutcome.sent, reason, device);
    } on PushTokenGone {
      await identity().dropPushToken(context.db, device);
      _wakes.record(PushOutcome.tokenGone, reason, device);
    } on PushFailed catch (failure) {
      _wakes.record(PushOutcome.failed, reason, device, error: failure.reason);
      rethrow;
    }
  }

  // ----------------------------------------------------------------- export

  @override
  Future<Object?> exportAccount(SqlSession s, String accountId) async {
    final sub = await _store.subscription(s, accountId);
    final requests = await _store.allRequestsOf(s, accountId);
    final claims = await _calls.store.claimsOf(s, accountId);
    return {
      'call_claims': [
        for (final c in claims)
          {
            'day': c.string('day'),
            'voice_minutes_left': c.integer('voice_left'),
            'video_minutes_left': c.integer('video_left'),
            'expires_at': toWireTime(c.time('expires_at')),
          },
      ],
      'subscription': sub == null
          ? null
          : {
              'plan': sub.string('plan'),
              'source': sub.string('source'),
              'period_end': toWireTime(sub.time('period_end')),
            },
      'payment_requests': [
        for (final r in requests)
          {
            'id': r.string('id'),
            'months': r.integer('months'),
            'amount': r.integer('amount'),
            'method': r.string('method'),
            'trx_id': r.string('trx_id'),
            'status': r.string('status'),
            'created_at': toWireTime(r.time('created_at')),
          },
      ],
    };
  }
}
