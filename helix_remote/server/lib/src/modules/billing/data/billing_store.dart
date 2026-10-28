import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/billing/data/call_time_store.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/db/paging.dart';

/// Schema `billing`: subscriptions, payment requests and the operator's
/// settings (ADR-035).
const billingMigrations = [
  Migration(1, 'billing_baseline', _baseline),
  Migration(2, 'trial_and_overrides', _trialAndOverrides),
  callTimeMigration,
];

String _trialAndOverrides(String s) =>
    '''
ALTER TABLE $s.subscriptions DROP CONSTRAINT IF EXISTS subscriptions_source_check;
ALTER TABLE $s.subscriptions ADD CONSTRAINT subscriptions_source_check
  CHECK (source IN ('payment', 'admin', 'trial'));

-- One free trial per phone number, kept even after the account is deleted so
-- a new account on the same number does not get another. It holds only the
-- keyed hash identity already keeps, never the number.
CREATE TABLE $s.trials_used (
  phone_key bytea PRIMARY KEY,
  used_at timestamptz NOT NULL DEFAULT now()
);

-- A limit an operator changed for one account (support cases).
CREATE TABLE $s.entitlement_overrides (
  account_id uuid NOT NULL,
  key text NOT NULL CHECK (key IN (
    'max_devices', 'attachment_quota_bytes', 'max_attachment_bytes',
    'attachment_retention_days', 'backup_max_bytes', 'backup_quota_bytes')),
  value bigint NOT NULL CHECK (value >= 0),
  reason text NOT NULL,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, key)
);
''';

String _baseline(String s) =>
    '''
CREATE TABLE $s.subscriptions (
  account_id uuid PRIMARY KEY,
  plan text NOT NULL CHECK (plan IN ('premium')),
  source text NOT NULL CHECK (source IN ('payment', 'admin')),
  period_end timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE $s.payment_requests (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  months integer NOT NULL CHECK (months IN (1, 6, 12)),
  amount integer NOT NULL CHECK (amount > 0),
  method text NOT NULL CHECK (method IN ('bkash', 'nagad')),
  trx_id text NOT NULL,
  status text NOT NULL CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
  reason text,
  decided_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- A transaction ID is accepted once, and an account has one open request.
CREATE UNIQUE INDEX payment_requests_trx ON $s.payment_requests (trx_id)
  WHERE status IN ('pending', 'approved');
CREATE UNIQUE INDEX payment_requests_open ON $s.payment_requests (account_id)
  WHERE status = 'pending';
CREATE INDEX payment_requests_by_account ON $s.payment_requests (account_id, id DESC);
CREATE INDEX payment_requests_by_status ON $s.payment_requests (status, id DESC);

CREATE TABLE $s.settings (
  key text PRIMARY KEY,
  value text NOT NULL
);
''';

/// A payment request row with its owner.
final class PaymentRequestRow {
  const PaymentRequestRow({required this.accountId, required this.info});

  final String accountId;
  final PaymentRequestInfo info;
}

final class BillingStore {
  const BillingStore(this.s);

  /// The schema name.
  final String s;

  static const _columns =
      'id, account_id, months, amount, method, trx_id, status, reason, '
      'decided_at, created_at';

  // ----------------------------------------------------------- subscription

  Future<DateTime?> periodEnd(SqlSession db, String accountId) async {
    final row = await db.queryOne(
      'SELECT period_end FROM $s.subscriptions WHERE account_id = @a:uuid',
      {'a': accountId},
    );
    return row?.time('period_end');
  }

  /// Adds [months] after the later of [now] and the current end. Returns the
  /// new end.
  Future<DateTime> extend(
    Tx tx,
    String accountId, {
    int months = 0,
    int days = 0,
    required String source,
    required DateTime now,
  }) async {
    final row = await tx.queryOne(
      'INSERT INTO $s.subscriptions AS sub '
      '(account_id, plan, source, period_end, created_at, updated_at) '
      "VALUES (@a:uuid, 'premium', @src:text, "
      '@now:timestamptz + make_interval(months => @m:int4, days => @d:int4), '
      '@now:timestamptz, @now:timestamptz) '
      'ON CONFLICT (account_id) DO UPDATE SET source = @src:text, '
      'period_end = GREATEST(sub.period_end, @now:timestamptz) '
      '+ make_interval(months => @m:int4, days => @d:int4), '
      'updated_at = @now:timestamptz '
      'RETURNING period_end',
      {'a': accountId, 'src': source, 'm': months, 'd': days, 'now': now},
    );
    return row!.time('period_end');
  }

  Future<bool> endNow(Tx tx, String accountId) async =>
      await tx.execute(
        'DELETE FROM $s.subscriptions WHERE account_id = @a:uuid',
        {'a': accountId},
      ) >
      0;

  Future<Row?> subscription(SqlSession db, String accountId) => db.queryOne(
    'SELECT plan, source, period_end FROM $s.subscriptions '
    'WHERE account_id = @a:uuid',
    {'a': accountId},
  );

  // --------------------------------------------------------------- requests

  PaymentRequestInfo _info(Row r) => PaymentRequestInfo(
    requestId: r.string('id'),
    months: r.integer('months'),
    amount: r.integer('amount'),
    method: PaymentMethod.values.firstWhere(
      (m) => m.wire == r.string('method'),
      orElse: () => PaymentMethod.unknown,
    ),
    trxId: r.string('trx_id'),
    status: PaymentRequestStatus.values.firstWhere(
      (m) => m.wire == r.string('status'),
      orElse: () => PaymentRequestStatus.unknown,
    ),
    reason: r.optString('reason'),
    createdAt: r.time('created_at'),
    decidedAt: r.optTime('decided_at'),
  );

  PaymentRequestRow _row(Row r) =>
      PaymentRequestRow(accountId: r.string('account_id'), info: _info(r));

  Future<PaymentRequestInfo> insertRequest(
    Tx tx, {
    required String id,
    required String accountId,
    required int months,
    required int amount,
    required PaymentMethod method,
    required String trxId,
    required DateTime now,
  }) async {
    final row = await tx.queryOne(
      'INSERT INTO $s.payment_requests '
      '(id, account_id, months, amount, method, trx_id, status, created_at) '
      "VALUES (@id:uuid, @a:uuid, @m:int4, @amount:int4, @method:text, @trx:text, 'pending', @now:timestamptz) "
      'RETURNING $_columns',
      {
        'id': id,
        'a': accountId,
        'm': months,
        'amount': amount,
        'method': method.wire,
        'trx': trxId,
        'now': now,
      },
    );
    return _info(row!);
  }

  Future<PaymentRequestRow?> requestForUpdate(Tx tx, String id) async {
    final row = await tx.queryOne(
      'SELECT $_columns FROM $s.payment_requests WHERE id = @id:uuid FOR UPDATE',
      {'id': id},
    );
    return row == null ? null : _row(row);
  }

  Future<void> decide(
    Tx tx,
    String id, {
    required PaymentRequestStatus status,
    required DateTime now,
    String? reason,
  }) => tx.execute(
    'UPDATE $s.payment_requests SET status = @st:text, reason = @reason:text, '
    'decided_at = @now:timestamptz WHERE id = @id:uuid',
    {'id': id, 'st': status.wire, 'reason': reason, 'now': now},
  );

  Future<PaymentRequestInfo?> openRequest(
    SqlSession db,
    String accountId,
  ) async {
    final row = await db.queryOne(
      'SELECT $_columns FROM $s.payment_requests '
      "WHERE account_id = @a:uuid AND status = 'pending'",
      {'a': accountId},
    );
    return row == null ? null : _info(row);
  }

  Future<PaymentRequestInfo?> lastDecided(
    SqlSession db,
    String accountId,
  ) async {
    final row = await db.queryOne(
      'SELECT $_columns FROM $s.payment_requests '
      "WHERE account_id = @a:uuid AND status <> 'pending' "
      'ORDER BY id DESC LIMIT 1',
      {'a': accountId},
    );
    return row == null ? null : _info(row);
  }

  Future<Page<PaymentRequestInfo>> requestsOf(
    SqlSession db,
    String accountId, {
    required PageRequest page,
  }) async {
    final cursor = _cursor(page);
    final rows = await db.query(
      'SELECT $_columns FROM $s.payment_requests '
      'WHERE account_id = @a:uuid AND id < COALESCE(@cursor:uuid, $lastUuidSql) '
      'ORDER BY id DESC LIMIT @limit:int4',
      {'a': accountId, 'cursor': cursor, 'limit': page.limit + 1},
    );
    final items = [for (final r in rows.take(page.limit)) _info(r)];
    return Page(
      items: items,
      nextCursor: rows.length > page.limit ? items.last.requestId : null,
    );
  }

  /// Every account's requests with [status], newest first.
  Future<Page<PaymentRequestRow>> requestsByStatus(
    SqlSession db, {
    required PaymentRequestStatus status,
    required PageRequest page,
  }) async {
    final cursor = _cursor(page);
    final rows = await db.query(
      'SELECT $_columns FROM $s.payment_requests '
      'WHERE status = @st:text AND id < COALESCE(@cursor:uuid, $lastUuidSql) '
      'ORDER BY id DESC LIMIT @limit:int4',
      {'st': status.wire, 'cursor': cursor, 'limit': page.limit + 1},
    );
    final items = [for (final r in rows.take(page.limit)) _row(r)];
    return Page(
      items: items,
      nextCursor: rows.length > page.limit ? items.last.info.requestId : null,
    );
  }

  String? _cursor(PageRequest page) {
    final cursor = page.cursor;
    if (cursor != null && !Uuid.isValid(cursor)) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'cursor'},
      );
    }
    return cursor;
  }

  /// Pending requests nobody answered in time become `expired`.
  Future<int> expirePending(SqlSession db, DateTime before) => db.execute(
    "UPDATE $s.payment_requests SET status = 'expired', decided_at = @now:timestamptz "
    "WHERE status = 'pending' AND created_at < @before:timestamptz",
    {'before': before, 'now': before},
  );

  /// Decided requests are kept a year, like audit rows.
  Future<int> purgeDecided(SqlSession db, DateTime before) => db.execute(
    "DELETE FROM $s.payment_requests WHERE status <> 'pending' "
    'AND created_at < @before:timestamptz',
    {'before': before},
  );

  Future<void> deleteAccount(Tx tx, String accountId) async {
    await tx.execute(
      'DELETE FROM $s.subscriptions WHERE account_id = @a:uuid',
      {'a': accountId},
    );
    await tx.execute(
      'DELETE FROM $s.entitlement_overrides WHERE account_id = @a:uuid',
      {'a': accountId},
    );
    await tx.execute(
      'DELETE FROM $s.payment_requests WHERE account_id = @a:uuid',
      {'a': accountId},
    );
  }

  Future<List<Row>> allRequestsOf(SqlSession db, String accountId) => db.query(
    'SELECT $_columns FROM $s.payment_requests '
    'WHERE account_id = @a:uuid ORDER BY id DESC LIMIT 200',
    {'a': accountId},
  );

  // --------------------------------------------------------------- settings

  Future<Map<String, String>> settings(SqlSession db) async => {
    for (final r in await db.query('SELECT key, value FROM $s.settings'))
      r.string('key'): r.string('value'),
  };

  Future<void> putSetting(Tx tx, String key, String? value) async {
    if (value == null) {
      await tx.execute('DELETE FROM $s.settings WHERE key = @k:text', {
        'k': key,
      });
      return;
    }
    await tx.execute(
      'INSERT INTO $s.settings (key, value) VALUES (@k:text, @v:text) '
      'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
      {'k': key, 'v': value},
    );
  }

  // ------------------------------------------------------------------ trial

  /// Marks a phone number as having had its trial. False when it already had
  /// one (nothing changes then).
  Future<bool> recordTrial(Tx tx, Uint8List phoneKey, DateTime now) async =>
      await tx.execute(
        'INSERT INTO $s.trials_used (phone_key, used_at) '
        'VALUES (@k:bytea, @now:timestamptz) ON CONFLICT DO NOTHING',
        {'k': phoneKey, 'now': now},
      ) >
      0;

  // -------------------------------------------------------------- overrides

  /// The overrides in force at [now], by wire key.
  Future<Map<String, int>> activeOverrides(
    SqlSession db,
    String accountId,
    DateTime now,
  ) async => {
    for (final r in await db.query(
      'SELECT key, value FROM $s.entitlement_overrides '
      'WHERE account_id = @a:uuid AND (expires_at IS NULL OR expires_at > @now:timestamptz)',
      {'a': accountId, 'now': now},
    ))
      r.string('key'): r.integer('value'),
  };

  Future<List<PlanOverride>> overridesOf(
    SqlSession db,
    String accountId,
    DateTime now,
  ) async => [
    for (final r in await db.query(
      'SELECT key, value, reason, expires_at FROM $s.entitlement_overrides '
      'WHERE account_id = @a:uuid AND (expires_at IS NULL OR expires_at > @now:timestamptz) '
      'ORDER BY key',
      {'a': accountId, 'now': now},
    ))
      PlanOverride(
        key: PlanLimitKey.values.firstWhere(
          (k) => k.wire == r.string('key'),
          orElse: () => PlanLimitKey.unknown,
        ),
        value: r.integer('value'),
        reason: r.string('reason'),
        expiresAt: r.optTime('expires_at'),
      ),
  ];

  Future<void> putOverride(
    Tx tx,
    String accountId, {
    required PlanLimitKey key,
    required int value,
    required String reason,
    DateTime? expiresAt,
  }) => tx.execute(
    'INSERT INTO $s.entitlement_overrides (account_id, key, value, reason, expires_at) '
    'VALUES (@a:uuid, @k:text, @v:int8, @r:text, @e:timestamptz) '
    'ON CONFLICT (account_id, key) DO UPDATE SET value = excluded.value, '
    'reason = excluded.reason, expires_at = excluded.expires_at, created_at = now()',
    {'a': accountId, 'k': key.wire, 'v': value, 'r': reason, 'e': expiresAt},
  );

  Future<bool> clearOverride(Tx tx, String accountId, PlanLimitKey key) async =>
      await tx.execute(
        'DELETE FROM $s.entitlement_overrides WHERE account_id = @a:uuid AND key = @k:text',
        {'a': accountId, 'k': key.wire},
      ) >
      0;

  Future<int> purgeExpiredOverrides(SqlSession db, DateTime now) => db.execute(
    'DELETE FROM $s.entitlement_overrides WHERE expires_at IS NOT NULL AND expires_at <= @now:timestamptz',
    {'now': now},
  );

  // ---------------------------------------------------------------- summary

  Future<BillingSummary> summary(
    SqlSession db, {
    required DateTime now,
    required Duration grace,
  }) async {
    final subs = (await db.queryOne(
      'SELECT '
      '(count(*) FILTER (WHERE period_end > @now:timestamptz))::int4 AS running, '
      '(count(*) FILTER (WHERE period_end <= @now:timestamptz AND period_end + make_interval(secs => @grace:int8) > @now:timestamptz))::int4 AS grace, '
      "(count(*) FILTER (WHERE source = 'trial' AND period_end > @now:timestamptz))::int4 AS trial "
      'FROM $s.subscriptions',
      {'now': now, 'grace': grace.inSeconds},
    ))!;
    final reqs = (await db.queryOne(
      'SELECT '
      "(count(*) FILTER (WHERE status = 'pending'))::int4 AS pending, "
      "(count(*) FILTER (WHERE status = 'approved' AND decided_at > @since:timestamptz))::int4 AS approved, "
      "coalesce(sum(amount) FILTER (WHERE status = 'approved' AND decided_at > @since:timestamptz), 0)::int8 AS taken "
      'FROM $s.payment_requests',
      {'since': now.subtract(const Duration(days: 30))},
    ))!;
    return BillingSummary(
      premium: subs.integer('running'),
      inGrace: subs.integer('grace'),
      onTrial: subs.integer('trial'),
      pendingRequests: reqs.integer('pending'),
      approvedLast30Days: reqs.integer('approved'),
      takenLast30Days: reqs.integer('taken'),
    );
  }
}
