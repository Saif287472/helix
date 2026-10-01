import 'dart:async';

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

  final pg.Pool<void> _pool;
  final String _url;
  Future<pg.Connection>? _listener;
  final Set<String> _listening = {};

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
    var attempt = 0;
    while (true) {
      final pending = <Future<void> Function()>[];
      try {
        final result = await _pool.runTx((session) async {
          return body(_PgTx(session, pending));
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
    final connection = await _listenerConnection();
    if (_listening.add(channel)) {
      await connection.execute('LISTEN "$channel"');
    }
    return connection.channels.all
        .where((n) => n.channel == channel)
        .map((n) => n.payload);
  }

  Future<pg.Connection> _listenerConnection() =>
      _listener ??= pg.Connection.openFromUrl(_url);

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
    final listener = _listener;
    if (listener != null) await (await listener).close();
    await _pool.close();
  }
}

final class _PgTx implements Tx {
  _PgTx(this._session, this._afterCommit);

  final pg.TxSession _session;
  final List<Future<void> Function()> _afterCommit;

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

Row? _single(List<Row> rows) {
  if (rows.length > 1) {
    throw StateError('expected at most one row, got ${rows.length}');
  }
  return rows.isEmpty ? null : rows.single;
}

Object _translate(pg.ServerException e) {
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
