import 'package:crypto/crypto.dart' as crypto;
import 'package:helix_remote_server/src/platform/db/db.dart';

/// A stored response for an `Idempotency-Key`.
final class StoredResponse {
  const StoredResponse({
    required this.requestHash,
    required this.status,
    required this.body,
  });

  final String requestHash;
  final int status;
  final String body;
}

/// Records responses to mutating requests that carried `Idempotency-Key`
/// (REST_V2.md conventions), for 24 hours.
abstract interface class IdempotencyStore {
  Future<StoredResponse?> find(String principal, String key);

  Future<void> save(String principal, String key, StoredResponse response);

  Future<int> sweep();
}

String hashRequest(String method, String path, List<int> body) =>
    crypto.sha256.convert([...'$method $path\n'.codeUnits, ...body]).toString();

final class PostgresIdempotencyStore implements IdempotencyStore {
  PostgresIdempotencyStore(this._db, String platformSchema)
    : _table = '$platformSchema.idempotency';

  final Db _db;
  final String _table;

  @override
  Future<StoredResponse?> find(String principal, String key) async {
    final row = await _db.queryOne(
      '''SELECT request_hash, status, response FROM $_table
         WHERE principal = @p:text AND key = @k:text
           AND created_at > now() - interval '24 hours\'''',
      {'p': principal, 'k': key},
    );
    if (row == null) return null;
    return StoredResponse(
      requestHash: row.string('request_hash'),
      status: row.integer('status'),
      body: row.string('response'),
    );
  }

  @override
  Future<void> save(
    String principal,
    String key,
    StoredResponse response,
  ) async {
    await _db.execute(
      '''INSERT INTO $_table (principal, key, request_hash, status, response)
         VALUES (@p:text, @k:text, @h:text, @s:int4, @r:text)
         ON CONFLICT (principal, key) DO NOTHING''',
      {
        'p': principal,
        'k': key,
        'h': response.requestHash,
        's': response.status,
        'r': response.body,
      },
    );
  }

  @override
  Future<int> sweep() => _db.execute(
    "DELETE FROM $_table WHERE created_at < now() - interval '24 hours'",
  );
}

final class InMemoryIdempotencyStore implements IdempotencyStore {
  final Map<String, StoredResponse> _entries = {};

  @override
  Future<StoredResponse?> find(String principal, String key) async =>
      _entries['$principal\n$key'];

  @override
  Future<void> save(
    String principal,
    String key,
    StoredResponse response,
  ) async {
    _entries.putIfAbsent('$principal\n$key', () => response);
  }

  @override
  Future<int> sweep() async => 0;
}
