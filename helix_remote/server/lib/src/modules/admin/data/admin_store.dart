import 'dart:convert';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/admin/domain/password_hash.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';

/// Schema `admin`: operator accounts and the audit log.
const adminMigrations = [Migration(1, 'admin_baseline', _baseline)];

String _baseline(String s) =>
    '''
CREATE TABLE $s.admins (
  id uuid PRIMARY KEY,
  kdf jsonb NOT NULL,
  salt bytea NOT NULL,
  hash bytea NOT NULL,
  failed_attempts integer NOT NULL DEFAULT 0,
  locked_until timestamptz,
  tokens_valid_after timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  password_changed_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE $s.audit (
  id uuid PRIMARY KEY,
  admin_id uuid,
  action text NOT NULL,
  target text,
  details jsonb NOT NULL DEFAULT '{}',
  at timestamptz NOT NULL DEFAULT now()
);
''';

final class AdminRow {
  const AdminRow({
    required this.id,
    required this.password,
    required this.failedAttempts,
    required this.tokensValidAfter,
    this.lockedUntil,
  });

  final String id;
  final PasswordHash password;
  final int failedAttempts;
  final DateTime tokensValidAfter;
  final DateTime? lockedUntil;
}

final class AdminStore {
  AdminStore(this.s);

  /// Tokens carry millisecond issue times, so cut-offs are stored at the
  /// same precision (a token issued in the same millisecond stays valid).
  static DateTime _millis(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
    t.millisecondsSinceEpoch,
    isUtc: true,
  );

  /// Schema name.
  final String s;

  AdminRow _row(Row r) => AdminRow(
    id: r.string('id'),
    password: PasswordHash(
      params: Argon2Params.fromJson(r.json('kdf')),
      salt: r.bytes('salt'),
      hash: r.bytes('hash'),
    ),
    failedAttempts: r.integer('failed_attempts'),
    tokensValidAfter: r.time('tokens_valid_after'),
    lockedUntil: r.optTime('locked_until'),
  );

  static const _columns =
      'id, kdf, salt, hash, failed_attempts, locked_until, tokens_valid_after';

  Future<bool> configured(SqlSession db) async =>
      await db.queryOne('SELECT 1 FROM $s.admins LIMIT 1') != null;

  /// The operator (one per server today; the table allows more later).
  Future<AdminRow?> first(SqlSession db) async {
    final r = await db.queryOne(
      'SELECT $_columns FROM $s.admins ORDER BY created_at LIMIT 1',
    );
    return r == null ? null : _row(r);
  }

  Future<AdminRow?> byId(SqlSession db, String id) async {
    final r = await db.queryOne(
      'SELECT $_columns FROM $s.admins WHERE id = @id:uuid',
      {'id': id},
    );
    return r == null ? null : _row(r);
  }

  /// Creates the first admin; false if one exists (the table lock makes
  /// two concurrent setups safe).
  Future<bool> createFirst(
    Tx tx,
    String id,
    PasswordHash password,
    DateTime now,
  ) async {
    await tx.execute('LOCK TABLE $s.admins IN EXCLUSIVE MODE');
    if (await configured(tx)) return false;
    await tx.execute(
      'INSERT INTO $s.admins (id, kdf, salt, hash, tokens_valid_after) '
      'VALUES (@id:uuid, @k:jsonb, @s:bytea, @h:bytea, @v:timestamptz)',
      {
        'id': id,
        'k': jsonEncode(password.params.toJson()),
        's': password.salt,
        'h': password.hash,
        'v': _millis(now),
      },
    );
    return true;
  }

  Future<void> recordFailure(
    SqlSession db,
    String id, {
    required DateTime? lockUntil,
  }) async {
    await db.execute(
      'UPDATE $s.admins SET failed_attempts = failed_attempts + 1, '
      'locked_until = COALESCE(@l:timestamptz, locked_until) WHERE id = @id:uuid',
      {'id': id, 'l': lockUntil},
    );
  }

  Future<void> recordSuccess(SqlSession db, String id) async {
    await db.execute(
      'UPDATE $s.admins SET failed_attempts = 0, locked_until = NULL WHERE id = @id:uuid',
      {'id': id},
    );
  }

  /// Replaces the password and ends every token issued before [validAfter].
  Future<void> setPassword(
    SqlSession db,
    String id,
    PasswordHash password,
    DateTime validAfter,
  ) async {
    await db.execute(
      'UPDATE $s.admins SET kdf = @k:jsonb, salt = @s:bytea, hash = @h:bytea, '
      'failed_attempts = 0, locked_until = NULL, tokens_valid_after = @v:timestamptz, '
      'password_changed_at = now() WHERE id = @id:uuid',
      {
        'id': id,
        'k': jsonEncode(password.params.toJson()),
        's': password.salt,
        'h': password.hash,
        'v': _millis(validAfter),
      },
    );
  }

  // ------------------------------------------------------------------- audit

  Future<void> audit(
    SqlSession db, {
    required String? adminId,
    required String action,
    String? target,
    Map<String, String> details = const {},
  }) async {
    await db.execute(
      'INSERT INTO $s.audit (id, admin_id, action, target, details) '
      'VALUES (@id:uuid, @a:uuid, @act:text, @t:text, @d:jsonb)',
      {
        'id': Uuid.v7(),
        'a': adminId,
        'act': action,
        't': target,
        'd': jsonEncode(details),
      },
    );
  }

  Future<Page<AuditEntry>> auditLog(
    SqlSession db, {
    required PageRequest page,
  }) async {
    final cursor = page.cursor;
    if (cursor != null && !Uuid.isValid(cursor)) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'cursor'},
      );
    }
    final rows = await db.query(
      'SELECT id, action, target, details, at FROM $s.audit '
      'WHERE (@cursor:uuid IS NULL OR id < @cursor:uuid) '
      'ORDER BY id DESC LIMIT @limit:int4',
      {'cursor': cursor, 'limit': page.limit + 1},
    );
    final items = [
      for (final r in rows.take(page.limit))
        AuditEntry(
          id: r.string('id'),
          action: r.string('action'),
          at: r.time('at'),
          target: r.optString('target'),
          details: {
            for (final e in r.json('details').entries) e.key: '${e.value}',
          },
        ),
    ];
    return Page(
      items: items,
      nextCursor: rows.length > page.limit ? items.last.id : null,
    );
  }
}
