import 'package:helix_remote_server/src/platform/clock.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

/// Short-lived shared state with a TTL (ADR-025): sign-in challenges,
/// device-link polls, WebSocket routes, presence, S2S replay keys. Shared by
/// all nodes, so nothing about a request depends on which node handled the
/// previous one.
abstract interface class EphemeralStore {
  Future<void> put(String key, String value, Duration ttl);

  Future<String?> get(String key);

  /// The live values of [keys] that exist, in one round trip.
  Future<Map<String, String>> getAll(Iterable<String> keys);

  /// Stores only if [key] is absent (or expired). True if stored.
  Future<bool> putIfAbsent(String key, String value, Duration ttl);

  /// Returns and deletes in one step (single-use values).
  Future<String?> take(String key);

  /// Stores [value] (with a new TTL) only if [key] currently holds
  /// [expected]. True if stored. A compare-and-set for values that another
  /// node may have replaced (WebSocket routes).
  Future<bool> replace(String key, String expected, String value, Duration ttl);

  Future<void> delete(String key);

  /// Deletes [key] only if it holds [expected]. True if deleted.
  Future<bool> deleteIf(String key, String expected);

  /// Every live entry whose key starts with [prefix].
  Future<Map<String, String>> scan(String prefix, {int limit = 1000});

  /// Removes expired entries; returns how many.
  Future<int> sweep();
}

final class InMemoryEphemeralStore implements EphemeralStore {
  InMemoryEphemeralStore({this._clock = const SystemClock()});

  final Clock _clock;
  final Map<String, (String, DateTime)> _entries = {};

  String? _live(String key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (!entry.$2.isAfter(_clock.now())) {
      _entries.remove(key);
      return null;
    }
    return entry.$1;
  }

  @override
  Future<void> put(String key, String value, Duration ttl) async {
    _entries[key] = (value, _clock.now().add(ttl));
  }

  @override
  Future<String?> get(String key) async => _live(key);

  @override
  Future<Map<String, String>> getAll(Iterable<String> keys) async => {
    for (final key in keys) key: ?_live(key),
  };

  @override
  Future<bool> putIfAbsent(String key, String value, Duration ttl) async {
    if (_live(key) != null) return false;
    _entries[key] = (value, _clock.now().add(ttl));
    return true;
  }

  @override
  Future<String?> take(String key) async {
    final value = _live(key);
    _entries.remove(key);
    return value;
  }

  @override
  Future<bool> replace(
    String key,
    String expected,
    String value,
    Duration ttl,
  ) async {
    if (_live(key) != expected) return false;
    _entries[key] = (value, _clock.now().add(ttl));
    return true;
  }

  @override
  Future<void> delete(String key) async => _entries.remove(key);

  @override
  Future<bool> deleteIf(String key, String expected) async {
    if (_live(key) != expected) return false;
    _entries.remove(key);
    return true;
  }

  @override
  Future<Map<String, String>> scan(String prefix, {int limit = 1000}) async {
    final out = <String, String>{};
    for (final key in _entries.keys.toList()) {
      if (out.length >= limit) break;
      if (!key.startsWith(prefix)) continue;
      final value = _live(key);
      if (value != null) out[key] = value;
    }
    return out;
  }

  @override
  Future<int> sweep() async {
    final now = _clock.now();
    final expired = [
      for (final e in _entries.entries)
        if (!e.value.$2.isAfter(now)) e.key,
    ];
    expired.forEach(_entries.remove);
    return expired.length;
  }
}

/// [EphemeralStore] over an UNLOGGED Postgres table. Expiry is checked on
/// every read; [sweep] (a periodic job) reclaims space.
final class PostgresEphemeralStore implements EphemeralStore {
  PostgresEphemeralStore(this._db, String platformSchema)
    : _table = '$platformSchema.ephemeral';

  final Db _db;
  final String _table;

  int _ms(Duration ttl) => ttl.inMilliseconds;

  @override
  Future<void> put(String key, String value, Duration ttl) async {
    await _db.execute(
      '''INSERT INTO $_table (key, value, expires_at)
         VALUES (@k:text, @v:text, now() + make_interval(secs => @ms:int8 / 1000.0))
         ON CONFLICT (key) DO UPDATE SET value = excluded.value, expires_at = excluded.expires_at''',
      {'k': key, 'v': value, 'ms': _ms(ttl)},
    );
  }

  @override
  Future<String?> get(String key) async {
    final row = await _db.queryOne(
      'SELECT value FROM $_table WHERE key = @k:text AND expires_at > now()',
      {'k': key},
    );
    return row?.string('value');
  }

  @override
  Future<Map<String, String>> getAll(Iterable<String> keys) async {
    final list = keys.toSet().toList();
    if (list.isEmpty) return const {};
    final rows = await _db.query(
      'SELECT key, value FROM $_table WHERE key = ANY(@k:_text) AND expires_at > now()',
      {'k': list},
    );
    return {for (final r in rows) r.string('key'): r.string('value')};
  }

  @override
  Future<bool> putIfAbsent(String key, String value, Duration ttl) async {
    final rows = await _db.query(
      '''INSERT INTO $_table AS e (key, value, expires_at)
         VALUES (@k:text, @v:text, now() + make_interval(secs => @ms:int8 / 1000.0))
         ON CONFLICT (key) DO UPDATE SET value = excluded.value, expires_at = excluded.expires_at
           WHERE e.expires_at <= now()
         RETURNING key''',
      {'k': key, 'v': value, 'ms': _ms(ttl)},
    );
    return rows.isNotEmpty;
  }

  @override
  Future<String?> take(String key) async {
    final row = await _db.queryOne(
      'DELETE FROM $_table WHERE key = @k:text AND expires_at > now() RETURNING value',
      {'k': key},
    );
    return row?.string('value');
  }

  @override
  Future<bool> replace(
    String key,
    String expected,
    String value,
    Duration ttl,
  ) async {
    final rows = await _db.query(
      '''UPDATE $_table SET value = @v:text,
           expires_at = now() + make_interval(secs => @ms:int8 / 1000.0)
         WHERE key = @k:text AND value = @e:text AND expires_at > now()
         RETURNING key''',
      {'k': key, 'e': expected, 'v': value, 'ms': _ms(ttl)},
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> delete(String key) async {
    await _db.execute('DELETE FROM $_table WHERE key = @k:text', {'k': key});
  }

  @override
  Future<bool> deleteIf(String key, String expected) async {
    final rows = await _db.query(
      'DELETE FROM $_table WHERE key = @k:text AND value = @e:text RETURNING key',
      {'k': key, 'e': expected},
    );
    return rows.isNotEmpty;
  }

  @override
  Future<Map<String, String>> scan(String prefix, {int limit = 1000}) async {
    final rows = await _db.query(
      '''SELECT key, value FROM $_table
         WHERE key LIKE @p:text ESCAPE '\\' AND expires_at > now()
         ORDER BY key LIMIT @limit:int4''',
      {'p': '${_escapeLike(prefix)}%', 'limit': limit},
    );
    return {for (final r in rows) r.string('key'): r.string('value')};
  }

  @override
  Future<int> sweep() =>
      _db.execute('DELETE FROM $_table WHERE expires_at <= now()');
}

String _escapeLike(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
