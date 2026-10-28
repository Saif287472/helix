import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/db/paging.dart';

/// Schema `billing`: subscriptions, payment requests and the operator's
/// settings (ADR-035).
const billingMigrations = [Migration(1, 'billing_baseline', _baseline)];

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
    required int months,
    required String source,
    required DateTime now,
  }) async {
    final row = await tx.queryOne(
      'INSERT INTO $s.subscriptions AS sub '
      '(account_id, plan, source, period_end, created_at, updated_at) '
      "VALUES (@a:uuid, 'premium', @src:text, "
      '@now:timestamptz + make_interval(months => @m:int4), @now:timestamptz, @now:timestamptz) '
      'ON CONFLICT (account_id) DO UPDATE SET source = @src:text, '
      'period_end = GREATEST(sub.period_end, @now:timestamptz) '
      '+ make_interval(months => @m:int4), updated_at = @now:timestamptz '
      'RETURNING period_end',
      {'a': accountId, 'src': source, 'm': months, 'now': now},
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
}
