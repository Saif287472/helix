import 'dart:async';

/// Runs actions one at a time per key. The engine serialises everything that
/// reads and then writes the ratchet state of one remote device with it
/// (CRYPTO_V2.md §14): without it two sends, or a send and a decrypt, could
/// both start from the same committed state and reuse a message key.
final class KeyedLock<K extends Comparable<K>> {
  final Map<K, Future<void>> _tails = {};

  /// Waits for earlier actions on [key], then runs [action].
  Future<T> run<T>(K key, Future<T> Function() action) async {
    final previous = _tails[key] ?? Future<void>.value();
    final done = Completer<void>();
    final tail = previous.then((_) => done.future);
    _tails[key] = tail;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
      if (identical(_tails[key], tail)) _tails.remove(key);
    }
  }

  /// Runs [action] holding every key in [keys]. Keys are taken in sorted
  /// order, so two callers with overlapping sets cannot deadlock.
  Future<T> runAll<T>(Iterable<K> keys, Future<T> Function() action) {
    final sorted = keys.toSet().toList()..sort();
    Future<T> take(int index) => index == sorted.length
        ? action()
        : run(sorted[index], () => take(index + 1));
    return take(0);
  }

  /// True while some action holds or waits for [key] (tests).
  bool isBusy(K key) => _tails.containsKey(key);
}
