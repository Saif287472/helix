import 'dart:convert';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';

/// Migration 3 of schema `billing`: the Free plan's call time (ADR-036).
const callTimeMigration = Migration(3, 'call_time', _callTime);

String _callTime(String s) =>
    '''
-- Minutes claimed once a day. A claim holds voice and video minutes and runs
-- out at the end of its third Dhaka day.
CREATE TABLE $s.call_claims (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  day text NOT NULL,
  claimed_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  voice_left integer NOT NULL CHECK (voice_left >= 0),
  video_left integer NOT NULL CHECK (video_left >= 0),
  UNIQUE (account_id, day)
);
CREATE INDEX call_claims_live ON $s.call_claims (account_id, expires_at);

-- Time set aside for one call (or one group call, `room_id`), taken from the
-- starter's claims when the relay credentials are issued and settled when the
-- call ends. `parts` says which claims the minutes came from, so the unused
-- ones go back to them.
CREATE TABLE $s.call_reservations (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  pool text NOT NULL CHECK (pool IN ('voice', 'video')),
  room_id text,
  metered boolean NOT NULL,
  reserved integer NOT NULL CHECK (reserved >= 0),
  parts jsonb NOT NULL DEFAULT '[]',
  created_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  answered_at timestamptz,
  last_end_at timestamptz,
  finalized_at timestamptz,
  used integer
);
CREATE UNIQUE INDEX call_reservations_room ON $s.call_reservations (room_id) WHERE room_id IS NOT NULL;
CREATE INDEX call_reservations_open ON $s.call_reservations (account_id) WHERE finalized_at IS NULL;
CREATE INDEX call_reservations_due ON $s.call_reservations (expires_at) WHERE finalized_at IS NULL;

-- Which reservation a call (one leg of a room) runs under.
CREATE TABLE $s.call_reservation_calls (
  call_id text PRIMARY KEY,
  reservation_id uuid NOT NULL,
  caller_account uuid NOT NULL,
  created_at timestamptz NOT NULL
);
CREATE INDEX call_reservation_calls_by_reservation ON $s.call_reservation_calls (reservation_id);
''';

/// A reservation row.
final class ReservationRow {
  const ReservationRow({
    required this.id,
    required this.accountId,
    required this.pool,
    required this.metered,
    required this.reserved,
    required this.parts,
    required this.createdAt,
    required this.expiresAt,
    required this.finalized,
    this.roomId,
    this.answeredAt,
    this.lastEndAt,
  });

  final String id;
  final String accountId;
  final CallPool pool;
  final String? roomId;
  final bool metered;
  final int reserved;
  final List<({String claim, int minutes})> parts;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? answeredAt;
  final DateTime? lastEndAt;
  final bool finalized;
}

/// What came out of a claim when time was set aside.
final class Taken {
  const Taken(this.total, this.parts);

  final int total;
  final List<({String claim, int minutes})> parts;
}

/// SQL of the call-time tables (the billing module's own schema only).
final class CallTimeStore {
  const CallTimeStore(this.s);

  final String s;

  static String _column(CallPool pool) =>
      pool == CallPool.video ? 'video_left' : 'voice_left';

  /// Serialises everything that spends one account's call time.
  Future<void> lockAccount(Tx tx, String accountId) => tx.execute(
    'SELECT pg_advisory_xact_lock(hashtextextended(@k:text, 0))',
    {'k': 'billing:calls:$accountId'},
  );

  /// Serialises the two ends of one call (and the legs that share a room).
  Future<void> lockCall(Tx tx, String key) => tx.execute(
    'SELECT pg_advisory_xact_lock(hashtextextended(@k:text, 0))',
    {'k': 'billing:call:$key'},
  );

  // ----------------------------------------------------------------- claims

  /// False when this Dhaka day was already claimed.
  Future<bool> insertClaim(
    Tx tx, {
    required String id,
    required String accountId,
    required String day,
    required DateTime now,
    required DateTime expiresAt,
    required int voice,
    required int video,
  }) async =>
      await tx.execute(
        'INSERT INTO $s.call_claims '
        '(id, account_id, day, claimed_at, expires_at, voice_left, video_left) '
        'VALUES (@id:uuid, @a:uuid, @day:text, @now:timestamptz, @e:timestamptz, @v:int4, @vi:int4) '
        'ON CONFLICT (account_id, day) DO NOTHING',
        {
          'id': id,
          'a': accountId,
          'day': day,
          'now': now,
          'e': expiresAt,
          'v': voice,
          'vi': video,
        },
      ) >
      0;

  Future<bool> claimedOn(SqlSession db, String accountId, String day) async =>
      await db.queryOne(
        'SELECT 1 AS x FROM $s.call_claims WHERE account_id = @a:uuid AND day = @d:text',
        {'a': accountId, 'd': day},
      ) !=
      null;

  /// Minutes held now, and when the oldest of them run out.
  Future<({int minutes, DateTime? expiresAt})> held(
    SqlSession db,
    String accountId,
    CallPool pool,
    DateTime now,
  ) async {
    final c = _column(pool);
    final row = await db.queryOne(
      'SELECT coalesce(sum($c), 0)::int4 AS n, '
      'min(expires_at) FILTER (WHERE $c > 0) AS soonest '
      'FROM $s.call_claims WHERE account_id = @a:uuid AND expires_at > @now:timestamptz',
      {'a': accountId, 'now': now},
    );
    return (minutes: row!.integer('n'), expiresAt: row.optTime('soonest'));
  }

  /// Takes every minute the account holds in [pool], oldest claim first.
  Future<Taken> takeAll(
    Tx tx,
    String accountId,
    CallPool pool,
    DateTime now,
  ) async {
    final c = _column(pool);
    final rows = await tx.query(
      'SELECT id, $c AS n FROM $s.call_claims '
      'WHERE account_id = @a:uuid AND expires_at > @now:timestamptz AND $c > 0 '
      'ORDER BY expires_at, claimed_at FOR UPDATE',
      {'a': accountId, 'now': now},
    );
    final parts = <({String claim, int minutes})>[];
    var total = 0;
    for (final r in rows) {
      final n = r.integer('n');
      await tx.execute('UPDATE $s.call_claims SET $c = 0 WHERE id = @id:uuid', {
        'id': r.string('id'),
      });
      parts.add((claim: r.string('id'), minutes: n));
      total += n;
    }
    return Taken(total, parts);
  }

  /// Gives [minutes] back to the claims they came from, the last taken first,
  /// except those that have run out meanwhile.
  Future<void> refund(
    Tx tx,
    List<({String claim, int minutes})> parts,
    CallPool pool,
    int minutes,
    DateTime now,
  ) async {
    final c = _column(pool);
    var left = minutes;
    for (final part in parts.reversed) {
      if (left <= 0) break;
      final give = left < part.minutes ? left : part.minutes;
      await tx.execute(
        'UPDATE $s.call_claims SET $c = $c + @n:int4 '
        'WHERE id = @id:uuid AND expires_at > @now:timestamptz',
        {'n': give, 'id': part.claim, 'now': now},
      );
      left -= give;
    }
  }

  Future<int> purgeClaims(SqlSession db, DateTime before) => db.execute(
    'DELETE FROM $s.call_claims WHERE expires_at < @b:timestamptz',
    {'b': before},
  );

  // ----------------------------------------------------------- reservations

  static const _columns =
      'id, account_id, pool, room_id, metered, reserved, parts, created_at, '
      'expires_at, answered_at, last_end_at, finalized_at';

  ReservationRow _row(Row r) => ReservationRow(
    id: r.string('id'),
    accountId: r.string('account_id'),
    pool: CallPool.values.firstWhere((p) => p.wire == r.string('pool')),
    roomId: r.optString('room_id'),
    metered: r.boolean('metered'),
    reserved: r.integer('reserved'),
    parts: [
      for (final p
          in (r['parts'] is String
              ? jsonDecode(r['parts']! as String) as List
              : r['parts']! as List))
        (
          claim: (p as Map)['claim'] as String,
          minutes: (p['minutes'] as num).toInt(),
        ),
    ],
    createdAt: r.time('created_at'),
    expiresAt: r.time('expires_at'),
    answeredAt: r.optTime('answered_at'),
    lastEndAt: r.optTime('last_end_at'),
    finalized: !r.isNull('finalized_at'),
  );

  Future<ReservationRow?> forCall(Tx tx, String callId) async {
    final row = await tx.queryOne(
      'SELECT ${_columns.split(', ').map((c) => 'r.$c').join(', ')} '
      'FROM $s.call_reservations r '
      'JOIN $s.call_reservation_calls c ON c.reservation_id = r.id '
      'WHERE c.call_id = @c:text FOR UPDATE OF r',
      {'c': callId},
    );
    return row == null ? null : _row(row);
  }

  Future<ReservationRow?> forRoom(Tx tx, String roomId) async {
    final row = await tx.queryOne(
      'SELECT $_columns FROM $s.call_reservations WHERE room_id = @r:text FOR UPDATE',
      {'r': roomId},
    );
    return row == null ? null : _row(row);
  }

  Future<void> insertReservation(
    Tx tx, {
    required String id,
    required String accountId,
    required CallPool pool,
    required bool metered,
    required int reserved,
    required List<({String claim, int minutes})> parts,
    required DateTime now,
    required DateTime expiresAt,
    String? roomId,
  }) => tx.execute(
    'INSERT INTO $s.call_reservations '
    '(id, account_id, pool, room_id, metered, reserved, parts, created_at, expires_at) '
    'VALUES (@id:uuid, @a:uuid, @p:text, @room:text, @m:boolean, @r:int4, @parts:jsonb, @now:timestamptz, @e:timestamptz)',
    {
      'id': id,
      'a': accountId,
      'p': pool.wire,
      'room': roomId,
      'm': metered,
      'r': reserved,
      'parts': [
        for (final p in parts) {'claim': p.claim, 'minutes': p.minutes},
      ],
      'now': now,
      'e': expiresAt,
    },
  );

  Future<void> mapCall(
    Tx tx, {
    required String callId,
    required String reservationId,
    required String callerAccount,
    required DateTime now,
  }) => tx.execute(
    'INSERT INTO $s.call_reservation_calls (call_id, reservation_id, caller_account, created_at) '
    'VALUES (@c:text, @r:uuid, @a:uuid, @now:timestamptz) ON CONFLICT (call_id) DO NOTHING',
    {'c': callId, 'r': reservationId, 'a': callerAccount, 'now': now},
  );

  /// Points a call at another reservation (a one-to-one call that changed
  /// between voice and video).
  Future<void> remapCall(Tx tx, String callId, String reservationId) =>
      tx.execute(
        'UPDATE $s.call_reservation_calls SET reservation_id = @r:uuid '
        'WHERE call_id = @c:text',
        {'c': callId, 'r': reservationId},
      );

  Future<void> markAnswered(Tx tx, String id, DateTime now) => tx.execute(
    'UPDATE $s.call_reservations SET answered_at = coalesce(answered_at, @now:timestamptz) '
    'WHERE id = @id:uuid',
    {'id': id, 'now': now},
  );

  Future<void> markEnded(Tx tx, String id, DateTime now) => tx.execute(
    'UPDATE $s.call_reservations SET last_end_at = greatest(coalesce(last_end_at, @now:timestamptz), @now:timestamptz) '
    'WHERE id = @id:uuid',
    {'id': id, 'now': now},
  );

  Future<void> markFinalized(
    Tx tx,
    String id,
    int used,
    DateTime now,
  ) => tx.execute(
    'UPDATE $s.call_reservations SET finalized_at = @now:timestamptz, used = @u:int4 '
    'WHERE id = @id:uuid',
    {'id': id, 'u': used, 'now': now},
  );

  /// The account's reservations whose call has ended but that still hold
  /// minutes (a group call waits a minute for its last leg).
  Future<List<ReservationRow>> endedOpen(Tx tx, String accountId) async => [
    for (final r in await tx.query(
      'SELECT $_columns FROM $s.call_reservations '
      'WHERE account_id = @a:uuid AND finalized_at IS NULL AND last_end_at IS NOT NULL FOR UPDATE',
      {'a': accountId},
    ))
      _row(r),
  ];

  /// Reservations that are over: out of time, or a minute past their last end.
  Future<List<String>> due(
    SqlSession db,
    DateTime now,
    Duration endGrace,
  ) async => [
    for (final r in await db.query(
      'SELECT id FROM $s.call_reservations WHERE finalized_at IS NULL AND '
      '(expires_at <= @now:timestamptz OR (last_end_at IS NOT NULL AND last_end_at <= @grace:timestamptz)) '
      'LIMIT 200',
      {'now': now, 'grace': now.subtract(endGrace)},
    ))
      r.string('id'),
  ];

  Future<ReservationRow?> byId(Tx tx, String id) async {
    final row = await tx.queryOne(
      'SELECT $_columns FROM $s.call_reservations WHERE id = @id:uuid FOR UPDATE',
      {'id': id},
    );
    return row == null ? null : _row(row);
  }

  Future<int> purgeReservations(SqlSession db, DateTime before) async {
    await db.execute(
      'DELETE FROM $s.call_reservation_calls WHERE reservation_id IN '
      '(SELECT id FROM $s.call_reservations WHERE finalized_at IS NOT NULL AND finalized_at < @b:timestamptz)',
      {'b': before},
    );
    return db.execute(
      'DELETE FROM $s.call_reservations WHERE finalized_at IS NOT NULL AND finalized_at < @b:timestamptz',
      {'b': before},
    );
  }

  Future<void> deleteAccount(Tx tx, String accountId) async {
    await tx.execute(
      'DELETE FROM $s.call_reservation_calls WHERE caller_account = @a:uuid',
      {'a': accountId},
    );
    await tx.execute(
      'DELETE FROM $s.call_reservations WHERE account_id = @a:uuid',
      {'a': accountId},
    );
    await tx.execute('DELETE FROM $s.call_claims WHERE account_id = @a:uuid', {
      'a': accountId,
    });
  }

  Future<List<Row>> claimsOf(SqlSession db, String accountId) => db.query(
    'SELECT day, claimed_at, expires_at, voice_left, video_left FROM $s.call_claims '
    'WHERE account_id = @a:uuid ORDER BY day DESC LIMIT 10',
    {'a': accountId},
  );
}
