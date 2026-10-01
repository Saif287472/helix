import 'dart:convert';
import 'dart:typed_data';

/// SQL access for modules (ADR-025). All of it is async; correctness never
/// depends on running on one isolate or one node.
///
/// SQL uses `package:postgres` named parameters with explicit types, e.g.
/// `WHERE id = @id:uuid AND body = @body:bytea`. Schema names are
/// interpolated from [SchemaNames] (validated identifiers), never from
/// request data.
abstract interface class SqlSession {
  /// Rows of a query.
  Future<List<Row>> query(String sql, [Map<String, Object?> params]);

  /// The single row of a query, or null. Throws if there is more than one.
  Future<Row?> queryOne(String sql, [Map<String, Object?> params]);

  /// Runs a statement and returns the number of affected rows.
  Future<int> execute(String sql, [Map<String, Object?> params]);
}

/// A session inside a transaction. Obtained only from [Db.tx]; passed down
/// explicitly to repositories, which never start transactions themselves.
abstract interface class Tx implements SqlSession {
  /// Runs [action] after a successful commit (publishing bus events,
  /// pushing to sockets). Never runs if the transaction rolls back.
  void afterCommit(Future<void> Function() action);
}

abstract interface class Db implements SqlSession {
  /// Runs [body] in a transaction; commits if it completes, rolls back if it
  /// throws. Transactions do not nest: code that needs one takes a [Tx].
  ///
  /// Serialization failures and deadlocks are retried up to [retries] times,
  /// so [body] must be safe to re-run (no side effects outside the database
  /// except through [Tx.afterCommit]).
  Future<T> tx<T>(Future<T> Function(Tx tx) body, {int retries = 3});

  /// Notifications on [channel]. Completes once `LISTEN` is active on a
  /// dedicated connection, so a `notify` issued afterwards is received.
  /// Channel names are `[a-z0-9_]` identifiers.
  Future<Stream<String>> listen(String channel);

  Future<void> notify(String channel, String payload);

  /// Whether the database answers (`SELECT 1`), for readiness checks.
  Future<bool> ping();

  Future<void> close();
}

/// A result row with typed, column-named getters. A wrong type is a
/// programming error and throws [StateError] naming the column.
final class Row {
  Row(this.values);

  final Map<String, Object?> values;

  Object? operator [](String column) => values[column];

  Never _bad(String column, String expected) => throw StateError(
    'column $column is ${values[column].runtimeType}, expected $expected',
  );

  bool isNull(String column) => values[column] == null;

  String string(String column) {
    final v = values[column];
    return v is String ? v : _bad(column, 'String');
  }

  String? optString(String column) =>
      values[column] == null ? null : string(column);

  int integer(String column) {
    final v = values[column];
    return v is int ? v : _bad(column, 'int');
  }

  int? optInt(String column) => values[column] == null ? null : integer(column);

  double float(String column) {
    final v = values[column];
    return v is num ? v.toDouble() : _bad(column, 'num');
  }

  bool boolean(String column) {
    final v = values[column];
    return v is bool ? v : _bad(column, 'bool');
  }

  Uint8List bytes(String column) {
    final v = values[column];
    if (v is Uint8List) return v;
    if (v is List<int>) return Uint8List.fromList(v);
    return _bad(column, 'bytes');
  }

  Uint8List? optBytes(String column) =>
      values[column] == null ? null : bytes(column);

  DateTime time(String column) {
    final v = values[column];
    return v is DateTime ? v.toUtc() : _bad(column, 'DateTime');
  }

  DateTime? optTime(String column) =>
      values[column] == null ? null : time(column);

  /// A `jsonb` column as a JSON object.
  Map<String, Object?> json(String column) {
    final v = values[column];
    if (v is Map) return v.cast<String, Object?>();
    if (v is String) return (jsonDecode(v) as Map).cast<String, Object?>();
    return _bad(column, 'JSON object');
  }

  List<String> strings(String column) {
    final v = values[column];
    if (v is List) return v.cast<String>();
    return _bad(column, 'List<String>');
  }

  @override
  String toString() => 'Row(${values.keys.join(', ')})';
}

/// Thrown for constraint violations, so callers can map them to API errors
/// without depending on the driver.
final class DbConstraintViolation implements Exception {
  DbConstraintViolation(this.kind, {this.constraint});

  final DbConstraintKind kind;
  final String? constraint;

  @override
  String toString() => 'DbConstraintViolation(${kind.name}, $constraint)';
}

enum DbConstraintKind { unique, foreignKey, check, notNull }
