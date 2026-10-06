import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

/// SQL behind the operator console's account and invite views.
final class AdminStore {
  AdminStore(this.s);

  /// Schema name.
  final String s;

  static String? _cursorId(PageRequest page) {
    final cursor = page.cursor;
    if (cursor == null) return null;
    if (!Uuid.isValid(cursor)) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'cursor'},
      );
    }
    return cursor;
  }

  static AdminAccount _account(Row r) => AdminAccount(
    accountId: r.string('id'),
    status: AccountStatus.values.firstWhere(
      (v) => v.wire == r.string('status'),
      orElse: () => AccountStatus.unknown,
    ),
    createdAt: r.time('created_at'),
    activeDevices: r.integer('active_devices'),
    helixName: r.optString('helix_name'),
    phoneLast4: r.optString('phone_last4'),
    lastSeenOn: r.optTime('last_seen_on'),
  );

  static const _accountSelect =
      'SELECT a.id, a.status, a.created_at, a.helix_name, a.phone_last4, '
      "(SELECT count(*)::int8 FROM {s}.devices d WHERE d.account_id = a.id AND d.status = 'active') AS active_devices, "
      '(SELECT max(d.last_seen_on) FROM {s}.devices d WHERE d.account_id = a.id) AS last_seen_on '
      'FROM {s}.accounts a';

  String get _select => _accountSelect.replaceAll('{s}', s);

  Future<Page<AdminAccount>> accounts(
    SqlSession db, {
    required PageRequest page,
    AccountStatus? status,
    String? query,
  }) async {
    final q = query?.trim().toLowerCase();
    final byLast4 = q != null && RegExp(r'^\d{4}$').hasMatch(q);
    final rows = await db.query(
      '$_select WHERE (@cursor:uuid IS NULL OR a.id < @cursor:uuid) '
      'AND (@status:text IS NULL OR a.status = @status:text) '
      'AND (@last4:text IS NULL OR a.phone_last4 = @last4:text) '
      "AND (@name:text IS NULL OR a.helix_name LIKE @name:text || '%') "
      'ORDER BY a.id DESC LIMIT @limit:int4',
      {
        'cursor': _cursorId(page),
        'status': status?.wire,
        'last4': byLast4 ? q : null,
        'name': q == null || q.isEmpty || byLast4
            ? null
            : q.replaceAll(RegExp(r'[%_\\]'), ''),
        'limit': page.limit + 1,
      },
    );
    final items = [for (final r in rows.take(page.limit)) _account(r)];
    return Page(
      items: items,
      nextCursor: rows.length > page.limit ? items.last.accountId : null,
    );
  }

  Future<AdminAccount?> account(SqlSession db, String accountId) async {
    final r = await db.queryOne('$_select WHERE a.id = @id:uuid', {
      'id': accountId,
    });
    return r == null ? null : _account(r);
  }

  Future<List<AdminDevice>> devices(SqlSession db, String accountId) async {
    final rows = await db.query(
      'SELECT id, name, platform, status, created_at, last_seen_on, revoked_at '
      'FROM $s.devices WHERE account_id = @a:uuid ORDER BY created_at',
      {'a': accountId},
    );
    return [
      for (final r in rows)
        AdminDevice(
          deviceId: r.string('id'),
          name: r.string('name'),
          platform: DevicePlatform.values.firstWhere(
            (p) => p.wire == r.string('platform'),
            orElse: () => DevicePlatform.other,
          ),
          active: r.string('status') == 'active',
          createdAt: r.time('created_at'),
          lastSeenOn: r.optTime('last_seen_on'),
          revokedAt: r.optTime('revoked_at'),
        ),
    ];
  }

  Future<Page<AdminInvite>> invites(
    SqlSession db, {
    required PageRequest page,
    required DateTime now,
  }) async {
    final rows = await db.query(
      'SELECT id, issuer, created_at, expires_at, redeemed_at, redeemed_by, cancelled_at '
      'FROM $s.invites WHERE (@cursor:uuid IS NULL OR id < @cursor:uuid) '
      'ORDER BY id DESC LIMIT @limit:int4',
      {'cursor': _cursorId(page), 'limit': page.limit + 1},
    );
    final items = [
      for (final r in rows.take(page.limit))
        AdminInvite(
          inviteId: r.string('id'),
          issuer: r.string('issuer'),
          status: !r.isNull('cancelled_at')
              ? InviteStatus.cancelled
              : !r.isNull('redeemed_at')
              ? InviteStatus.used
              : r.time('expires_at').isAfter(now)
              ? InviteStatus.open
              : InviteStatus.expired,
          createdAt: r.time('created_at'),
          expiresAt: r.time('expires_at'),
          redeemedBy: r.optString('redeemed_by'),
        ),
    ];
    return Page(
      items: items,
      nextCursor: rows.length > page.limit ? items.last.inviteId : null,
    );
  }

  Future<bool> cancelInvite(SqlSession db, String inviteId) async =>
      await db.execute(
        'UPDATE $s.invites SET cancelled_at = now() WHERE id = @id:uuid '
        'AND cancelled_at IS NULL AND redeemed_at IS NULL AND expires_at > now()',
        {'id': inviteId},
      ) ==
      1;

  Future<Map<String, int>> purgeExpired(SqlSession db) async => {
    'refresh_tokens': await db.execute(
      "DELETE FROM $s.refresh_tokens WHERE expires_at < now() - interval '1 day' "
      "OR revoked_at < now() - interval '1 day'",
    ),
    'phone_challenges': await db.execute(
      "DELETE FROM $s.phone_challenges WHERE expires_at < now() - interval '1 day'",
    ),
    'invites': await db.execute(
      "DELETE FROM $s.invites WHERE redeemed_at IS NULL AND expires_at < now() - interval '30 days'",
    ),
    'recovery_codes': await db.execute(
      "DELETE FROM $s.recovery_codes WHERE expires_at < now() - interval '1 day' "
      "OR used_at < now() - interval '1 day'",
    ),
  };

  // ------------------------------------------------------------------ export

  Future<Map<String, Object?>> export(SqlSession db, String accountId) async {
    final account = await db.queryOne(
      'SELECT id, identity_key, status, created_at, helix_name, phone_last4, '
      'identity_key_changed_at FROM $s.accounts WHERE id = @id:uuid',
      {'id': accountId},
    );
    if (account == null) return const {};
    final password = await db.queryOne(
      'SELECT updated_at FROM $s.passwords WHERE account_id = @a:uuid',
      {'a': accountId},
    );
    final events = await db.query(
      'SELECT kind, device_id, device_name, at FROM $s.security_events '
      'WHERE account_id = @a:uuid ORDER BY id DESC LIMIT 500',
      {'a': accountId},
    );
    final pushKinds = await db.query(
      'SELECT p.device_id, p.kind, p.updated_at FROM $s.push_tokens p '
      'JOIN $s.devices d ON d.id = p.device_id WHERE d.account_id = @a:uuid',
      {'a': accountId},
    );
    final identityKeyChanged = account.optTime('identity_key_changed_at');
    return {
      'account': compact({
        'account_id': account.string('id'),
        'status': account.string('status'),
        'created_at': toWireTime(account.time('created_at')),
        'helix_name': account.optString('helix_name'),
        'phone_last4': account.optString('phone_last4'),
        'identity_key': encodeBytes(account.bytes('identity_key')),
        'identity_key_changed_at': identityKeyChanged == null
            ? null
            : toWireTime(identityKeyChanged),
      }),
      'password': password == null
          ? null
          : {'updated_at': toWireTime(password.time('updated_at'))},
      'devices': [for (final d in await devices(db, accountId)) d.toJson()],
      'push_tokens': [
        for (final r in pushKinds)
          {
            'device_id': r.string('device_id'),
            'kind': r.string('kind'),
            'updated_at': toWireTime(r.time('updated_at')),
          },
      ],
      'security_events': [
        for (final r in events)
          compact({
            'kind': r.string('kind'),
            'device_id': r.optString('device_id'),
            'device_name': r.optString('device_name'),
            'at': toWireTime(r.time('at')),
          }),
      ],
    };
  }
}
