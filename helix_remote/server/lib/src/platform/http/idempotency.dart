import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
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

/// Seals stored response bodies (S7 #16): some responses carry a secret
/// exactly once (invite links, recovery codes), and the idempotency table
/// must not keep them readable for 24 hours. AES-256-GCM under a key
/// derived from the JWT signing key (`HMAC-SHA256(jwt_key,
/// "helix.v2.idempotency")`), with the principal, key and request hash as
/// associated data so a row cannot be replayed for another request. Rows
/// sealed under a JWT key that was since removed no longer open; the
/// request then runs again.
final class IdempotencySealer {
  IdempotencySealer(Map<String, List<int>> jwtKeys, this._activeKid)
    : _keys = {
        for (final e in jwtKeys.entries)
          e.key: SecretKey(
            crypto.Hmac(
              crypto.sha256,
              e.value,
            ).convert(utf8.encode('helix.v2.idempotency')).bytes,
          ),
      };

  static const _prefix = 'e1';
  static final _aead = AesGcm.with256bits();

  final Map<String, SecretKey> _keys;
  final String _activeKid;

  List<int> _aad(String principal, String key, String requestHash) =>
      utf8.encode('$principal\n$key\n$requestHash');

  Future<String> seal(
    String body, {
    required String principal,
    required String key,
    required String requestHash,
  }) async {
    final box = await _aead.encrypt(
      utf8.encode(body),
      secretKey: _keys[_activeKid]!,
      aad: _aad(principal, key, requestHash),
    );
    return [
      _prefix,
      encodeBytes(utf8.encode(_activeKid)),
      encodeBytes(box.concatenation()),
    ].join(':');
  }

  /// The body, or null if [sealed] does not open (unknown key, tampered).
  Future<String?> open(
    String sealed, {
    required String principal,
    required String key,
    required String requestHash,
  }) async {
    final parts = sealed.split(':');
    if (parts.length != 3 || parts[0] != _prefix) return null;
    try {
      final secret = _keys[utf8.decode(decodeBytes(parts[1]))];
      if (secret == null) return null;
      final box = SecretBox.fromConcatenation(
        decodeBytes(parts[2]),
        nonceLength: _aead.nonceLength,
        macLength: _aead.macAlgorithm.macLength,
      );
      return utf8.decode(
        await _aead.decrypt(
          box,
          secretKey: secret,
          aad: _aad(principal, key, requestHash),
        ),
      );
    } on Object {
      return null;
    }
  }
}

final class PostgresIdempotencyStore implements IdempotencyStore {
  PostgresIdempotencyStore(this._db, String platformSchema, this._sealer)
    : _table = '$platformSchema.idempotency';

  final Db _db;
  final String _table;
  final IdempotencySealer _sealer;

  @override
  Future<StoredResponse?> find(String principal, String key) async {
    final row = await _db.queryOne(
      '''SELECT request_hash, status, response FROM $_table
         WHERE principal = @p:text AND key = @k:text
           AND created_at > now() - interval '24 hours\'''',
      {'p': principal, 'k': key},
    );
    if (row == null) return null;
    final requestHash = row.string('request_hash');
    final body = await _sealer.open(
      row.string('response'),
      principal: principal,
      key: key,
      requestHash: requestHash,
    );
    if (body == null) return null;
    return StoredResponse(
      requestHash: requestHash,
      status: row.integer('status'),
      body: body,
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
        'r': await _sealer.seal(
          response.body,
          principal: principal,
          key: key,
          requestHash: response.requestHash,
        ),
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
