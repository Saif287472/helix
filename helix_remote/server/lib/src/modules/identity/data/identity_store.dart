import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/identity/api.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

/// SQL for accounts, devices, push tokens, security events and settings.
final class IdentityStore {
  IdentityStore(this.s);

  /// Schema name.
  final String s;

  static const _deviceColumns =
      'id, account_id, name, platform, identity_key, signing_key, certificate, '
      'certificate_created_at, status, created_at, last_seen_on';

  AccountRecord _account(Row r) => AccountRecord(
    id: r.string('id'),
    identityKey: r.bytes('identity_key'),
    status: r.string('status'),
    createdAt: r.time('created_at'),
    helixName: r.optString('helix_name'),
    phoneLast4: r.optString('phone_last4'),
  );

  DeviceRecord device(Row r) => DeviceRecord(
    id: r.string('id'),
    accountId: r.string('account_id'),
    name: r.string('name'),
    platform: DevicePlatform.values.firstWhere(
      (p) => p.wire == r.string('platform'),
      orElse: () => DevicePlatform.other,
    ),
    identityKey: r.bytes('identity_key'),
    signingKey: r.bytes('signing_key'),
    certificate: r.bytes('certificate'),
    certificateCreatedAt: r.time('certificate_created_at'),
    active: r.string('status') == 'active',
    createdAt: r.time('created_at'),
    lastSeenOn: r.optTime('last_seen_on'),
  );

  // ---------------------------------------------------------------- accounts

  Future<AccountRecord?> account(SqlSession db, String id) async {
    final r = await db.queryOne(
      'SELECT id, identity_key, status, created_at, helix_name, phone_last4 '
      'FROM $s.accounts WHERE id = @id:uuid',
      {'id': id},
    );
    return r == null ? null : _account(r);
  }

  Future<({String id, bool hasPassword})?> accountByPhone(
    SqlSession db,
    Uint8List phoneHash,
  ) async {
    final r = await db.queryOne(
      'SELECT a.id, (p.account_id IS NOT NULL) AS has_password '
      'FROM $s.accounts a LEFT JOIN $s.passwords p ON p.account_id = a.id '
      'WHERE a.phone_hash = @h:bytea',
      {'h': phoneHash},
    );
    return r == null
        ? null
        : (id: r.string('id'), hasPassword: r.boolean('has_password'));
  }

  Future<void> setPhoneSealed(
    SqlSession db,
    String accountId,
    Uint8List sealed,
  ) => db.execute(
    'UPDATE $s.accounts SET phone_sealed = @p:bytea WHERE id = @id:uuid',
    {'id': accountId, 'p': sealed},
  );

  Future<Uint8List?> phoneHashOf(SqlSession db, String accountId) async {
    final r = await db.queryOne(
      'SELECT phone_hash FROM $s.accounts WHERE id = @id:uuid',
      {'id': accountId},
    );
    return r?.optBytes('phone_hash');
  }

  Future<void> insertAccount(
    Tx tx, {
    required String id,
    required Uint8List identityKey,
    Uint8List? phoneHash,
    String? discoveryIndex,
    String? phoneLast4,
  }) async {
    await tx.execute(
      'INSERT INTO $s.accounts (id, identity_key, phone_hash, discovery_index, phone_last4) '
      'VALUES (@id:uuid, @ik:bytea, @ph:bytea, @dh:text, @l4:text)',
      {
        'id': id,
        'ik': identityKey,
        'ph': phoneHash,
        'dh': discoveryIndex,
        'l4': phoneLast4,
      },
    );
  }

  Future<void> setIdentityKey(Tx tx, String accountId, Uint8List key) async {
    await tx.execute(
      'UPDATE $s.accounts SET identity_key = @k:bytea, identity_key_changed_at = now() '
      'WHERE id = @id:uuid',
      {'id': accountId, 'k': key},
    );
  }

  Future<void> setHelixName(
    SqlSession db,
    String accountId,
    String? name,
  ) async {
    await db.execute(
      'UPDATE $s.accounts SET helix_name = @n:text WHERE id = @id:uuid',
      {'id': accountId, 'n': name},
    );
  }

  Future<String?> accountByHelixName(SqlSession db, String name) async {
    final r = await db.queryOne(
      'SELECT id FROM $s.accounts WHERE helix_name = @n:text',
      {'n': name},
    );
    return r?.string('id');
  }

  Future<void> setDiscoveryIndex(Tx tx, String accountId, String? index) =>
      tx.execute(
        'UPDATE $s.accounts SET discovery_index = @i:text WHERE id = @id:uuid',
        {'id': accountId, 'i': index},
      );

  /// The verified phone hash and the discovery index, either may be null.
  Future<(Uint8List?, String?)> phoneAndIndex(Tx tx, String accountId) async {
    final r = await tx.queryOne(
      'SELECT phone_hash, discovery_index FROM $s.accounts WHERE id = @id:uuid FOR UPDATE',
      {'id': accountId},
    );
    return (r?.optBytes('phone_hash'), r?.optString('discovery_index'));
  }

  /// Account ids by keyed discovery index (see `IdentityContext`).
  Future<Map<String, String>> accountsByDiscoveryIndex(
    SqlSession db,
    Iterable<String> hashes,
  ) async {
    final list = hashes.toList();
    if (list.isEmpty) return const {};
    final rows = await db.query(
      "SELECT discovery_index, id FROM $s.accounts "
      "WHERE discovery_index = ANY(string_to_array(@h:text, ','))",
      {'h': list.join(',')},
    );
    return {for (final r in rows) r.string('discovery_index'): r.string('id')};
  }

  Future<void> setStatus(SqlSession db, String accountId, String status) async {
    await db.execute(
      'UPDATE $s.accounts SET status = @st:text WHERE id = @id:uuid',
      {'id': accountId, 'st': status},
    );
  }

  Future<void> deleteAccount(Tx tx, String accountId) async {
    await tx.execute('DELETE FROM $s.accounts WHERE id = @id:uuid', {
      'id': accountId,
    });
  }

  // ----------------------------------------------------------------- devices

  Future<DeviceRecord?> deviceById(SqlSession db, String id) async {
    final r = await db.queryOne(
      'SELECT $_deviceColumns FROM $s.devices WHERE id = @id:uuid',
      {'id': id},
    );
    return r == null ? null : device(r);
  }

  /// Takes the account's row lock, so adding devices to one account is
  /// serial: the count in [IdentityContext.addDevice] cannot be raced past
  /// [IdentityContext.maxDevices] by two sign-ins at once.
  Future<void> lockAccount(Tx tx, String accountId) => tx.execute(
    'SELECT 1 FROM $s.accounts WHERE id = @a:uuid FOR UPDATE',
    {'a': accountId},
  );

  Future<int> activeDeviceCount(SqlSession db, String accountId) async {
    final r = await db.queryOne(
      "SELECT count(*) AS n FROM $s.devices "
      "WHERE account_id = @a:uuid AND status = 'active'",
      {'a': accountId},
    );
    return r!.integer('n');
  }

  Future<List<DeviceRecord>> activeDevices(
    SqlSession db,
    String accountId,
  ) async {
    final rows = await db.query(
      "SELECT $_deviceColumns FROM $s.devices "
      "WHERE account_id = @a:uuid AND status = 'active' ORDER BY created_at",
      {'a': accountId},
    );
    return rows.map(device).toList();
  }

  Future<Map<String, List<DeviceRecord>>> activeDevicesOf(
    SqlSession db,
    Iterable<String> accounts,
  ) async {
    final ids = accounts.toSet().toList();
    if (ids.isEmpty) return const {};
    final rows = await db.query(
      "SELECT $_deviceColumns FROM $s.devices "
      "WHERE account_id = ANY(string_to_array(@a:text, ',')::uuid[]) AND status = 'active' "
      "ORDER BY created_at",
      {'a': ids.join(',')},
    );
    final out = <String, List<DeviceRecord>>{for (final id in ids) id: []};
    for (final r in rows) {
      out[r.string('account_id')]!.add(device(r));
    }
    return out;
  }

  Future<void> insertDevice(
    Tx tx,
    String accountId,
    DeviceRegistration d,
  ) async {
    await tx.execute(
      'INSERT INTO $s.devices (id, account_id, name, platform, identity_key, signing_key, '
      'certificate, certificate_created_at) VALUES (@id:uuid, @a:uuid, @n:text, @p:text, '
      '@ik:bytea, @sk:bytea, @c:bytea, @ca:timestamptz)',
      {
        'id': d.deviceId,
        'a': accountId,
        'n': d.name,
        'p': d.platform.wire,
        'ik': d.identityKey,
        'sk': d.signingKey,
        'c': d.certificate.signature,
        'ca': d.certificate.createdAt,
      },
    );
  }

  Future<void> renameDevice(
    SqlSession db,
    String accountId,
    String deviceId,
    String name,
  ) async {
    final n = await db.execute(
      "UPDATE $s.devices SET name = @n:text WHERE id = @id:uuid AND account_id = @a:uuid "
      "AND status = 'active'",
      {'id': deviceId, 'a': accountId, 'n': name},
    );
    if (n == 0) throw const ApiError(ErrorCode.notFound);
  }

  /// Marks a device revoked; returns it if it was active.
  /// Revokes [deviceId] if it is an active device of [accountId]; null
  /// otherwise (another account's device, a revoked one, none) with nothing
  /// changed. The owner is part of the statement, so a caller that skipped
  /// its own check cannot revoke across accounts (AUD-2-3).
  Future<DeviceRecord?> revokeDevice(
    Tx tx,
    String accountId,
    String deviceId,
    String reason,
  ) async {
    final r = await tx.queryOne(
      "UPDATE $s.devices SET status = 'revoked', revoked_at = now(), revoke_reason = @r:text, "
      "tokens_valid_after = now() WHERE id = @id:uuid AND account_id = @a:uuid "
      "AND status = 'active' RETURNING $_deviceColumns",
      {'id': deviceId, 'a': accountId, 'r': reason},
    );
    if (r == null) return null;
    await tx.execute(
      'UPDATE $s.refresh_tokens SET revoked_at = now() WHERE device_id = @d:uuid AND revoked_at IS NULL',
      {'d': deviceId},
    );
    await tx.execute('DELETE FROM $s.push_tokens WHERE device_id = @d:uuid', {
      'd': deviceId,
    });
    return device(r);
  }

  /// Ends every session of a device without revoking it (sign-out). Use
  /// `SessionIssuer.endSessions`, which also tells every node's sockets.
  /// Returns the cut-off at the precision [authState] compares (null if
  /// there is no such device).
  Future<DateTime?> invalidateSessions(SqlSession db, String deviceId) async {
    final r = await db.queryOne(
      'UPDATE $s.devices SET tokens_valid_after = now() WHERE id = @d:uuid '
      "RETURNING date_trunc('milliseconds', tokens_valid_after) AS cut_off",
      {'d': deviceId},
    );
    await db.execute(
      'UPDATE $s.refresh_tokens SET revoked_at = now() WHERE device_id = @d:uuid AND revoked_at IS NULL',
      {'d': deviceId},
    );
    return r?.time('cut_off');
  }

  /// Device, account status and session cut-off for authenticating a token.
  /// The cut-off is cut to milliseconds, the precision of a token's issue
  /// time, so a session minted in the same millisecond as the cut-off (a new
  /// device, a sign-in right after sign-out) is valid.
  Future<({bool active, String accountStatus, DateTime tokensValidAfter})?>
  authState(SqlSession db, String deviceId) async {
    final r = await db.queryOne(
      "SELECT d.status, date_trunc('milliseconds', d.tokens_valid_after) AS tokens_valid_after, "
      'a.status AS account_status '
      'FROM $s.devices d JOIN $s.accounts a ON a.id = d.account_id WHERE d.id = @d:uuid',
      {'d': deviceId},
    );
    if (r == null) return null;
    return (
      active: r.string('status') == 'active',
      accountStatus: r.string('account_status'),
      tokensValidAfter: r.time('tokens_valid_after'),
    );
  }

  Future<void> touchLastSeen(SqlSession db, String deviceId) async {
    await db.execute(
      // The UTC day, whatever the database's session time zone is: the cache in
      // `SessionService._touch` counts UTC days, and a different day here would
      // let it skip a write that moves the date.
      "UPDATE $s.devices SET last_seen_on = (now() AT TIME ZONE 'utc')::date "
      'WHERE id = @d:uuid AND (last_seen_on IS NULL '
      "OR last_seen_on < (now() AT TIME ZONE 'utc')::date)",
      {'d': deviceId},
    );
  }

  /// The active devices among [deviceIds], each row locked FOR SHARE until
  /// [tx] ends. Rows are locked in id order, so two transactions never take
  /// them in opposite orders. A revoke updates the row: it waits for a
  /// delivery that holds the lock (and its hooks then purge what that
  /// delivery stored), and a delivery that comes after it sees the revoke.
  Future<Set<String>> lockActiveDevices(Tx tx, List<String> deviceIds) async {
    if (deviceIds.isEmpty) return const {};
    final rows = await tx.query(
      "SELECT id FROM $s.devices WHERE id = ANY(@ids:_uuid) AND status = 'active' "
      'ORDER BY id FOR SHARE',
      {'ids': deviceIds},
    );
    return {for (final r in rows) r.string('id')};
  }

  // A device's activity: the last day it authenticated, or the day it was
  // added if it never has. An account's "newest" device is the one with the
  // latest (activity, created_at, id).
  static const _seen = 'coalesce(last_seen_on, created_at::date)';

  /// Active devices unused for more than [days] days, least recently used
  /// first. Never an account's most recently used device, so no account is
  /// left without one.
  Future<List<({String accountId, String deviceId})>> inactiveDevices(
    SqlSession db, {
    required int days,
    required int limit,
  }) async {
    final rows = await db.query(
      'SELECT id, account_id FROM ('
      '  SELECT id, account_id, $_seen AS seen, row_number() OVER ('
      '    PARTITION BY account_id ORDER BY $_seen DESC, created_at DESC, id DESC'
      "  ) AS rank FROM $s.devices WHERE status = 'active'"
      ') d WHERE rank > 1 AND seen < current_date - @days:int4 '
      'ORDER BY seen LIMIT @n:int4',
      {'days': days, 'n': limit},
    );
    return [
      for (final r in rows)
        (accountId: r.string('account_id'), deviceId: r.string('id')),
    ];
  }

  /// Locks [deviceId] and tells whether it may still be revoked for
  /// inactivity: active, unused for more than [days] days, and some other
  /// active device of its account is newer.
  Future<bool> stillInactive(Tx tx, String deviceId, int days) async {
    final r = await tx.queryOne(
      'SELECT coalesce(d.last_seen_on, d.created_at::date) < current_date - @days:int4 AS stale, '
      'EXISTS (SELECT 1 FROM $s.devices o WHERE o.account_id = d.account_id '
      "AND o.id <> d.id AND o.status = 'active' AND "
      '(coalesce(o.last_seen_on, o.created_at::date), o.created_at, o.id) > '
      '(coalesce(d.last_seen_on, d.created_at::date), d.created_at, d.id)) AS newer '
      "FROM $s.devices d WHERE d.id = @id:uuid AND d.status = 'active' FOR UPDATE OF d",
      {'id': deviceId, 'days': days},
    );
    return r != null && r.boolean('stale') && r.boolean('newer');
  }

  // ------------------------------------------------------------- push tokens

  Future<void> setPushToken(
    SqlSession db,
    String deviceId,
    PushTokenRequest token,
  ) async {
    await db.execute(
      'INSERT INTO $s.push_tokens (device_id, kind, token) VALUES (@d:uuid, @k:text, @t:text) '
      'ON CONFLICT (device_id) DO UPDATE SET kind = excluded.kind, token = excluded.token, updated_at = now()',
      {'d': deviceId, 'k': token.kind.wire, 't': token.token},
    );
  }

  Future<void> clearPushToken(SqlSession db, String deviceId) async {
    await db.execute('DELETE FROM $s.push_tokens WHERE device_id = @d:uuid', {
      'd': deviceId,
    });
  }

  Future<PushTarget?> pushTarget(SqlSession db, String deviceId) async {
    final r = await db.queryOne(
      'SELECT kind, token FROM $s.push_tokens WHERE device_id = @d:uuid',
      {'d': deviceId},
    );
    if (r == null) return null;
    return PushTarget(
      deviceId: deviceId,
      kind: PushTokenKind.values.firstWhere(
        (k) => k.wire == r.string('kind'),
        orElse: () => PushTokenKind.fcm,
      ),
      token: r.string('token'),
    );
  }

  // --------------------------------------------------------- security events

  Future<void> addEvent(
    SqlSession db,
    String accountId,
    SecurityEventKind kind, {
    String? deviceId,
    String? deviceName,
  }) async {
    await db.execute(
      'INSERT INTO $s.security_events (id, account_id, kind, device_id, device_name) '
      'VALUES (@id:uuid, @a:uuid, @k:text, @d:uuid, @n:text)',
      {
        'id': Uuid.v7(),
        'a': accountId,
        'k': kind.wire,
        'd': deviceId,
        'n': deviceName,
      },
    );
  }

  /// Newest first; [before] is the id of the last event of the previous page.
  Future<List<({String id, SecurityEvent event})>> events(
    SqlSession db,
    String accountId, {
    String? before,
    required int limit,
  }) async {
    final rows = await db.query(
      'SELECT id, kind, device_id, device_name, at FROM $s.security_events '
      'WHERE account_id = @a:uuid AND (@before:uuid IS NULL OR id < @before:uuid) '
      'ORDER BY id DESC LIMIT @l:int4',
      {'a': accountId, 'before': before, 'l': limit},
    );
    return [
      for (final r in rows)
        (
          id: r.string('id'),
          event: SecurityEvent(
            kind: SecurityEventKind.values.firstWhere(
              (k) => k.wire == r.string('kind'),
              orElse: () => SecurityEventKind.unknown,
            ),
            at: r.time('at'),
            deviceId: r.optString('device_id'),
            deviceName: r.optString('device_name'),
          ),
        ),
    ];
  }

  // ---------------------------------------------------------------- settings

  /// A server-wide random secret, created on first use (discovery salt).
  Future<Uint8List> setting(
    Db db,
    String key,
    Uint8List Function() create,
  ) async {
    final existing = await db.queryOne(
      'SELECT value FROM $s.settings WHERE key = @k:text',
      {'k': key},
    );
    if (existing != null) return existing.bytes('value');
    await db.execute(
      'INSERT INTO $s.settings (key, value) VALUES (@k:text, @v:bytea) ON CONFLICT (key) DO NOTHING',
      {'k': key, 'v': create()},
    );
    final row = await db.queryOne(
      'SELECT value FROM $s.settings WHERE key = @k:text',
      {'k': key},
    );
    return row!.bytes('value');
  }
}

String encodeJson(Object value) => jsonEncode(value);
