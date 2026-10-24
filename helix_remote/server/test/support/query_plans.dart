import 'dart:convert';

import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:test/test.dart';

/// The machinery behind the `EXPLAIN` guardrail (AUD-1b-3, audit proposal P3):
/// record the statements a hot path actually executed, then fail on a
/// `Seq Scan` in their plans.
///
/// `test/platform/query_plans_test.dart` is the first user, for the paths the
/// plan of record names. Later batches add their own path to that file rather
/// than writing their own recorder, so a query that gains a predicate or loses
/// an index is caught in one place.

/// A statement one of the hot paths ran, with the parameters it ran it with:
/// the plan is taken of exactly this text, with exactly these values, because
/// the planner reads the values to decide between an index and a scan.
typedef Statement = ({String sql, Map<String, Object?> params});

/// Wraps a session and records every statement that goes through it. SQL
/// copied into a test goes stale the first time the real query changes, and
/// the guardrail then checks something nobody runs.
final class Recording implements Tx {
  Recording(this._inner, this.log);

  final SqlSession _inner;
  final List<Statement> log;

  void _note(String sql, Map<String, Object?> params) =>
      log.add((sql: sql, params: params));

  @override
  Future<List<Row>> query(
    String sql, [
    Map<String, Object?> params = const {},
  ]) {
    _note(sql, params);
    return _inner.query(sql, params);
  }

  @override
  Future<Row?> queryOne(String sql, [Map<String, Object?> params = const {}]) {
    _note(sql, params);
    return _inner.queryOne(sql, params);
  }

  @override
  Future<int> execute(String sql, [Map<String, Object?> params = const {}]) {
    _note(sql, params);
    return _inner.execute(sql, params);
  }

  /// Stores never schedule after-commit work, so this only runs when the
  /// session wrapped is a real transaction.
  @override
  void afterCommit(Future<void> Function() action) =>
      (_inner as Tx).afterCommit(action);
}

/// The relations a plan walks with a sequential scan, from the JSON
/// `EXPLAIN (FORMAT JSON)` returns (a list holding one `Plan` tree).
Set<String> sequentialScans(Object? explainJson) {
  final found = <String>{};
  void walk(Map<String, Object?> node) {
    if (node['Node Type'] == 'Seq Scan') {
      found.add(node['Relation Name'] as String? ?? '(no name)');
    }
    final children = node['Plans'];
    if (children is List) {
      for (final child in children) {
        walk((child as Map).cast<String, Object?>());
      }
    }
  }

  if (explainJson is List) {
    for (final entry in explainJson) {
      final plan = (entry as Map)['Plan'];
      if (plan is Map) walk(plan.cast<String, Object?>());
    }
  }
  return found;
}

/// SQL as one line, short enough to read in a failure message.
String oneLine(String sql) {
  final flat = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= 180 ? flat : '${flat.substring(0, 180)}...';
}

/// One message per statement whose plan walks a table sequentially.
Future<List<String>> planProblems(Db db, Iterable<Statement> statements) async {
  final problems = <String>[];
  for (final s in statements) {
    final rows = await db.query('EXPLAIN (FORMAT JSON) ${s.sql}', s.params);
    // The driver decodes the `json` column; a plain text plan is a string.
    final plan = rows.single['QUERY PLAN'];
    final scanned = sequentialScans(plan is String ? jsonDecode(plan) : plan);
    if (scanned.isNotEmpty) {
      problems.add('Seq Scan on ${scanned.join(', ')} in: ${oneLine(s.sql)}');
    }
  }
  return problems;
}

/// The guardrail: [log] must hold the statements the path ran, and each of
/// their plans must reach its rows through an index.
Future<void> expectIndexed(Db db, List<Statement> log) async {
  expect(
    log,
    isNotEmpty,
    reason:
        'the path ran no SQL: it was renamed or removed, '
        'so this guard is checking nothing',
  );
  final problems = await planProblems(db, log);
  expect(problems, isEmpty, reason: problems.join('\n'));
}
