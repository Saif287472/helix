import 'dart:async';
import 'dart:math' as math;

import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:postgres/postgres.dart' as pg;

/// [Db] over a `package:postgres` pool. This file and its siblings are the
/// only code that imports the driver (architecture test).
final class PostgresDb implements Db {
  PostgresDb._(this._pool, this._url);

  /// Opens a pool for [url] (`postgresql://user:pass@host:port/db?sslmode=`).
  /// The URL is never logged.
  static Future<PostgresDb> open(String url, {int maxConnections = 10}) async {
    final parsed = Uri.parse(url);
    final separator = parsed.hasQuery ? '&' : '?';
    final pool = pg.Pool<void>.withUrl(
      '$url${separator}max_connection_count=$maxConnections',
    );
    final db = PostgresDb._(pool, url);
    if (!await db.ping()) {
      await pool.close();
      throw StateError('database is not reachable');
    }
    return db;
  }

  /// Zone key under which a running [tx] body finds its transaction.
  static final Object _txZoneKey = Object();

  /// Backoff of `LISTEN` reconnects: 250 ms doubling, at most 30 s.
  static Duration reconnectDelay(int attempt) => Duration(
    milliseconds: math.min(30000, 250 * (1 << math.min(attempt, 7))),
  );

  final pg.Pool<void> _pool;
  final String _url;
  Future<pg.Connection>? _listener;
  StreamSubscription<pg.Notification>? _notifications;
  final Set<String> _listening = {};
  final Map<String, StreamController<String>> _channels = {};
  final StreamController<void> _restored = StreamController.broadcast();
  Timer? _reconnect;
  bool _closed = false;

  @override
  Future<List<Row>> query(
    String sql, [
    Map<String, Object?> params = const {},
  ]) => _query(_pool, sql, params);

  @override
  Future<Row?> queryOne(
    String sql, [
    Map<String, Object?> params = const {},
  ]) async => _single(await query(sql, params));

  @override
  Future<int> execute(String sql, [Map<String, Object?> params = const {}]) =>
      _execute(_pool, sql, params);

  @override
  Future<T> tx<T>(Future<T> Function(Tx tx) body, {int retries = 3}) async {
    // Nested: join the running transaction rather than waiting for a second
    // pool connection (at pool-size concurrency that wait never ends).
    final outer = Zone.current[_txZoneKey];
    if (outer is _PgTx && identical(outer._owner, this) && outer._open) {
      return body(outer);
    }
    var attempt = 0;
    while (true) {
      final pending = <Future<void> Function()>[];
      try {
        final result = await _pool.runTx((session) async {
          final tx = _PgTx(this, session, pending);
          try {
            return await runZoned(() => body(tx), zoneValues: {_txZoneKey: tx});
          } finally {
            tx._open = false;
          }
        });
        for (final action in pending) {
          await action();
        }
        return result;
      } on pg.ServerException catch (e) {
        final retryable = e.code == '40001' || e.code == '40P01';
        if (!retryable || attempt >= retries) throw _translate(e);
        attempt++;
        await Future<void>.delayed(
          Duration(milliseconds: 10 * attempt * attempt),
        );
      }
    }
  }

  static final RegExp _channelName = RegExp(r'^[a-z][a-z0-9_]{0,62}$');

  @override
  Future<Stream<String>> listen(String channel) async {
    if (!_channelName.hasMatch(channel)) {
      throw ArgumentError.value(channel, 'channel', 'must be [a-z][a-z0-9_]*');
    }
    final controller = _channels.putIfAbsent(
      channel,
      StreamController<String>.broadcast,
    );
    final connection = await _listenerConnection();
    if (_listening.add(channel)) {
      // Kept in [_listening] even if this fails: a reconnect listens again.
      await connection.execute('LISTEN "$channel"');
    }
    return controller.stream;
  }

  @override
  Stream<void> get listenRestored => _restored.stream;

  /// The backend process id of the `LISTEN` connection (tests terminate it
  /// to exercise reconnects).
  Future<int> listenerBackendPid() async {
    final rows = await (await _listenerConnection()).execute(
      'SELECT pg_backend_pid()',
    );
    return rows.single.single! as int;
  }

  Future<pg.Connection> _listenerConnection() {
    final existing = _listener;
    if (existing != null) return existing;
    final opening = _openListener();
    _listener = opening;
    unawaited(
      opening.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_listener, opening)) _listener = null;
        },
      ),
    );
    return opening;
  }

  Future<pg.Connection> _openListener() async {
    final connection = await pg.Connection.openFromUrl(_url);
    try {
      _notifications = connection.channels.all.listen(
        (n) => _channels[n.channel]?.add(n.payload),
        onError: (Object _) {},
      );
      for (final channel in _listening.toList()) {
        await connection.execute('LISTEN "$channel"');
      }
    } on Object {
      await _notifications?.cancel();
      await connection.close();
      rethrow;
    }
    unawaited(connection.closed.then((_) => _lost(connection)));
    return connection;
  }

  /// The `LISTEN` connection dropped (Postgres restarted, the backend was
  /// terminated, the network blipped): reopen it with backoff.
  void _lost(pg.Connection connection) {
    if (_closed) return;
    unawaited(_notifications?.cancel());
    _notifications = null;
    _listener = null;
    _scheduleReconnect(0);
  }

  void _scheduleReconnect(int attempt) {
    if (_closed) return;
    _reconnect?.cancel();
    _reconnect = Timer(reconnectDelay(attempt), () async {
      if (_closed) return;
      try {
        await _listenerConnection();
        if (!_closed) _restored.add(null);
      } on Object {
        _scheduleReconnect(attempt + 1);
      }
    });
  }

  @override
  Future<void> notify(String channel, String payload) async {
    await _pool.execute(
      pg.Sql.named('SELECT pg_notify(@channel:text, @payload:text)'),
      parameters: {'channel': channel, 'payload': payload},
    );
  }

  @override
  Future<bool> ping() async {
    try {
      final rows = await _pool.execute('SELECT 1');
      return rows.isNotEmpty;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _reconnect?.cancel();
    final listener = _listener;
    if (listener != null) {
      try {
        await (await listener).close();
      } on Object {
        // It was never opened or is already gone.
      }
    }
    await _notifications?.cancel();
    for (final c in _channels.values) {
      await c.close();
    }
    await _restored.close();
    await _pool.close();
  }
}

final class _PgTx implements Tx {
  _PgTx(this._owner, this._session, this._afterCommit);

  final PostgresDb _owner;
  final pg.TxSession _session;
  final List<Future<void> Function()> _afterCommit;

  /// False once the body has finished; later nested `tx` calls (from work
  /// the body left running) start their own transaction.
  bool _open = true;

  @override
  Future<List<Row>> query(
    String sql, [
    Map<String, Object?> params = const {},
  ]) => _query(_session, sql, params);

  @override
  Future<Row?> queryOne(
    String sql, [
    Map<String, Object?> params = const {},
  ]) async => _single(await query(sql, params));

  @override
  Future<int> execute(String sql, [Map<String, Object?> params = const {}]) =>
      _execute(_session, sql, params);

  @override
  void afterCommit(Future<void> Function() action) => _afterCommit.add(action);
}

Future<List<Row>> _query(
  pg.Session session,
  String sql,
  Map<String, Object?> params,
) async {
  _checkRanges(sql, params);
  try {
    final result = await session.execute(pg.Sql.named(sql), parameters: params);
    return [for (final row in result) Row(row.toColumnMap())];
  } on pg.ServerException catch (e) {
    throw _translate(e);
  }
}

Future<int> _execute(
  pg.Session session,
  String sql,
  Map<String, Object?> params,
) async {
  _checkRanges(sql, params);
  try {
    final result = await session.execute(
      pg.Sql.named(sql),
      parameters: params,
      ignoreRows: true,
    );
    return result.affectedRows;
  } on pg.ServerException catch (e) {
    throw _translate(e);
  }
}

/// `@name:int4` / `@name:int2` parameters by statement. The driver encodes
/// integers with `ByteData.setInt32`, which silently wraps (2^32 + 1 would
/// be stored as 1), so out-of-range values are refused here instead.
final Map<String, List<(String, int, int)>> _rangeChecks = {};
final RegExp _smallIntParam = RegExp(r'@([A-Za-z_][A-Za-z0-9_]*):int([24])\b');

void _checkRanges(String sql, Map<String, Object?> params) {
  if (params.isEmpty) return;
  if (_rangeChecks.length > 4000) _rangeChecks.clear();
  final checks = _rangeChecks.putIfAbsent(
    sql,
    () => [
      for (final m in _smallIntParam.allMatches(sql))
        m.group(2) == '4'
            ? (m.group(1)!, -2147483648, 2147483647)
            : (m.group(1)!, -32768, 32767),
    ],
  );
  for (final (name, min, max) in checks) {
    final value = params[name];
    if (value is int && (value < min || value > max)) {
      throw DbInvalidValue(name);
    }
  }
}

Row? _single(List<Row> rows) {
  if (rows.length > 1) {
    throw StateError('expected at most one row, got ${rows.length}');
  }
  return rows.isEmpty ? null : rows.single;
}

Object _translate(pg.ServerException e) {
  // 22003 numeric value out of range, 22P02 invalid text representation.
  if (e.code == '22003' || e.code == '22P02') return const DbInvalidValue(null);
  final kind = switch (e.code) {
    '23505' => DbConstraintKind.unique,
    '23503' => DbConstraintKind.foreignKey,
    '23514' => DbConstraintKind.check,
    '23502' => DbConstraintKind.notNull,
    _ => null,
  };
  if (kind == null) return e;
  return DbConstraintViolation(kind, constraint: e.constraintName);
}
