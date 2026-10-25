/// Why a set write never binds a whole id list (AUD-10-1).
library;

/// SQLite binds one host parameter per element when drift renders an
/// `IN (…)` list, and its default build limit is 32,766 parameters per
/// statement — 999 in one compiled with the older default. Past it the
/// statement fails with "too many SQL variables" and its whole transaction
/// rolls back, so a sweep that runs into it never runs again: the ids it was
/// deleting are still there, the next pass throws the same way, and the upkeep
/// that came after it in the same pass is skipped too.
///
/// So no id list is bound in one statement: a big one is split, each part
/// written or read as a statement of its own. 500 leaves room for the other
/// parameters of the same statement even at the 999 limit, and one statement
/// per 500 rows is not what makes a large sweep slow.
const int statementIdLimit = 500;

extension ChunkedIds<T> on List<T> {
  /// This list in runs of at most [statementIdLimit] elements, so each run can
  /// be one statement. Empty in, empty out — a caller that loops over this
  /// therefore never builds `IN ()`, which SQLite rejects outright.
  Iterable<List<T>> chunks() sync* {
    for (var at = 0; at < length; at += statementIdLimit) {
      final end = at + statementIdLimit;
      yield sublist(at, end > length ? length : end);
    }
  }
}
