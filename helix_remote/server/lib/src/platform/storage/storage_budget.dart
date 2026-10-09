import 'dart:async';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/clock.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

/// The server-wide storage budget (`HELIX_STORAGE_BUDGET_BYTES`). Quotas are
/// per device or per account, so on one disk they multiply; this caps the
/// total. Used bytes are the size of this server's tables (with their
/// indexes and TOAST) plus what modules report (the media objects), measured
/// at most once per [refreshEvery] on each node.
final class StorageBudget {
  StorageBudget(
    this._db, {
    required this.limitBytes,
    required this._clock,
    this.schemaPrefix = '',
    this.refreshEvery = const Duration(minutes: 1),
  });

  final Db _db;
  final Clock _clock;

  /// Only schemas starting with this count (`HELIX_SCHEMA_PREFIX`; empty in
  /// production, where every non-system schema of the database counts).
  final String schemaPrefix;

  /// Null: no budget ([check] never refuses).
  final int? limitBytes;
  final Duration refreshEvery;

  final Map<String, Future<int> Function()> _reporters = {};
  ({DateTime at, int used})? _last;
  Future<int>? _measuring;

  /// Adds the bytes a module stores outside the database (media blobs).
  void report(String name, Future<int> Function() bytes) {
    if (_reporters.containsKey(name)) {
      throw StateError('storage reporter $name twice');
    }
    _reporters[name] = bytes;
  }

  /// This server's tables plus every reported store, measured now. Read
  /// from the catalogue per table, not with `pg_database_size`, which lists
  /// every file of the database and takes seconds where there are many.
  Future<int> measure() async {
    final row = await _db.queryOne(
      'SELECT coalesce(sum(pg_total_relation_size(c.oid)), 0)::int8 AS n '
      'FROM pg_class c JOIN pg_namespace s ON s.oid = c.relnamespace '
      "WHERE c.relkind IN ('r', 'm') "
      "AND s.nspname <> 'information_schema' AND s.nspname NOT LIKE 'pg\\_%' "
      'AND left(s.nspname, length(@p:text)) = @p:text',
      {'p': schemaPrefix},
    );
    var total = row!.integer('n');
    for (final reporter in _reporters.values) {
      total += await reporter();
    }
    return total;
  }

  /// The latest measurement; a new one when it is older than
  /// [refreshEvery]. Concurrent callers share one measurement.
  Future<int> used() async {
    final last = _last;
    if (last != null && _clock.now().difference(last.at) < refreshEvery) {
      return last.used;
    }
    final used = await (_measuring ??= measure().whenComplete(
      () => _measuring = null,
    ));
    _last = (at: _clock.now(), used: used);
    return used;
  }

  /// Waits (at most [limit]) for a measurement in flight, so the database
  /// is not closed under it. Errors are ignored.
  Future<void> settle({Duration limit = const Duration(seconds: 10)}) async {
    final inFlight = _measuring;
    if (inFlight == null) return;
    try {
      await inFlight.timeout(limit);
    } on Object {
      // Closing anyway.
    }
  }

  /// Throws `quota_exceeded` (details `reason: server_storage`) while the
  /// server is at or over its budget. Without a budget, or when the size
  /// cannot be measured, it lets the request through: the budget protects
  /// the disk and must not take the service down by itself.
  Future<void> check() async {
    final limit = limitBytes;
    if (limit == null) return;
    final int current;
    try {
      current = await used();
    } on Object {
      return;
    }
    if (current >= limit) {
      throw const ApiError(
        ErrorCode.quotaExceeded,
        message: 'the server has no storage left',
        details: {'reason': 'server_storage'},
      );
    }
  }
}
