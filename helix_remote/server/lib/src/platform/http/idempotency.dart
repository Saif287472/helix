import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

/// A stored answer for an `Idempotency-Key`: everything the first request
/// returned, headers included, so a replay is what the client saw then.
final class StoredResponse {
  const StoredResponse({
    required this.requestHash,
    required this.status,
    required this.body,
    this.headers = const {},
  });

  final String requestHash;
  final int status;
  final String body;
  final Map<String, String> headers;
}

/// How long one request may hold a key before another may take it.
///
/// A claim is a lease, not a lock: nothing cancels a handler that outruns it,
/// so this only has to outlast the longest honest request (a big upload sealed
/// on a slow line, a federated call waiting for a peer) and stay far under the
/// 24 hours a key is remembered. Its job is the crashed node: a claim left by
/// one must not burn the key until the sweep.
const Duration idempotencyClaimLease = Duration(minutes: 15);

/// What a claim of one key answered.
sealed class IdempotencyClaim {
  const IdempotencyClaim();
}

/// This request holds the key now: run the handler, then `record` or
/// `release` what it returned.
final class ClaimTaken extends IdempotencyClaim {
  const ClaimTaken();
}

/// The answer is stored; replay it and run nothing.
final class ClaimStored extends IdempotencyClaim {
  const ClaimStored(this.response);

  final StoredResponse response;
}

/// Another request claimed the key for this same body and has not answered
/// yet; retrying later gets either its replay or the right to run.
final class ClaimInProgress extends IdempotencyClaim {
  const ClaimInProgress();
}

/// The key already carries a different request, so this one is a mistake, not
/// a retry.
final class ClaimConflict extends IdempotencyClaim {
  const ClaimConflict();
}

/// Claims keys and remembers the answers to mutating requests that carried
/// `Idempotency-Key` (REST_V2.md conventions), for 24 hours.
///
/// The three-step shape is the point: a request claims before its handler
/// runs, so two that overlap cannot both act (AUD-1a-3), and a retry of a
/// request whose answer was lost waits or replays instead of running the
/// side effect a second time (AUD-11a-2).
abstract interface class IdempotencyStore {
  Future<IdempotencyClaim> claim(
    String principal,
    String key,
    String requestHash,
  );

  /// Stores the answer under a claim this request still holds; a claim that
  /// was taken away is left alone, so the winner's answer is what replays.
  Future<void> record(String principal, String key, StoredResponse response);

  /// Drops a claim that produced nothing worth replaying, so a retry runs.
  Future<void> release(String principal, String key, String requestHash);

  Future<int> sweep();
}

String hashRequest(String method, String path, List<int> body) =>
    crypto.sha256.convert([...'$method $path\n'.codeUnits, ...body]).toString();

/// Sealed bodies are stored as `e2:<kid>:<aes-gcm>` over the response headers
/// and body together (S7 #16, and AUD-1a-4): some answers carry a secret
/// exactly once (invite links, recovery codes), the headers a replay must keep
/// are as private as the body, and one envelope over both cannot be moved
/// between rows or reordered inside one.
///
/// The key is `HMAC-SHA256(jwt_key, "helix.v2.idempotency")` and the
/// associated data is the principal, key and request hash, so a row cannot be
/// replayed for another request. Rows sealed under a JWT key that was since
/// removed no longer open; the request then runs again.
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

  static const _prefix = 'e2';

  /// The envelope before headers were kept: body only. Rows written under it
  /// still open, so a request in flight across the deploy replays rather than
  /// running twice.
  static const _bodyOnlyPrefix = 'e1';

  static final _aead = AesGcm.with256bits();

  final Map<String, SecretKey> _keys;
  final String _activeKid;

  List<int> _aad(String principal, String key, String requestHash) =>
      utf8.encode('$principal\n$key\n$requestHash');

  Future<String> seal(
    String body, {
    required Map<String, String> headers,
    required String principal,
    required String key,
    required String requestHash,
  }) async {
    final payload = jsonEncode({
      'h': {for (final e in headers.entries) e.key.toLowerCase(): e.value},
      'b': body,
    });
    final box = await _aead.encrypt(
      utf8.encode(payload),
      secretKey: _keys[_activeKid]!,
      aad: _aad(principal, key, requestHash),
    );
    return [
      _prefix,
      encodeBytes(utf8.encode(_activeKid)),
      encodeBytes(box.concatenation()),
    ].join(':');
  }

  /// The body and its headers as one record `(body, headers)`, or null if
  /// [sealed] does not open (unknown key, tampered, or a version this build no
  /// longer reads).
  Future<(String, Map<String, String>)?> open(
    String sealed, {
    required String principal,
    required String key,
    required String requestHash,
  }) async {
    final parts = sealed.split(':');
    if (parts.length != 3 ||
        (parts[0] != _prefix && parts[0] != _bodyOnlyPrefix)) {
      return null;
    }
    try {
      final secret = _keys[utf8.decode(decodeBytes(parts[1]))];
      if (secret == null) return null;
      final box = SecretBox.fromConcatenation(
        decodeBytes(parts[2]),
        nonceLength: _aead.nonceLength,
        macLength: _aead.macAlgorithm.macLength,
      );
      final plain = utf8.decode(
        await _aead.decrypt(
          box,
          secretKey: secret,
          aad: _aad(principal, key, requestHash),
        ),
      );
      if (parts[0] == _bodyOnlyPrefix) return (plain, const <String, String>{});
      final decoded = jsonDecode(plain);
      if (decoded is! Map) return null;
      final body = decoded['b'];
      if (body is! String) return null;
      final stored = decoded['h'];
      final headers = <String, String>{
        if (stored is Map)
          for (final e in stored.entries) '${e.key}': '${e.value}',
      };
      return (body, headers);
    } on Object {
      return null;
    }
  }
}

final class PostgresIdempotencyStore implements IdempotencyStore {
  PostgresIdempotencyStore(
    this._db,
    String platformSchema,
    this._sealer, {
    this.lease = idempotencyClaimLease,
  }) : _table = '$platformSchema.idempotency';

  final Db _db;
  final String _table;
  final IdempotencySealer _sealer;

  /// How long an unanswered claim may be stolen; tests shorten it.
  final Duration lease;

  @override
  Future<IdempotencyClaim> claim(
    String principal,
    String key,
    String requestHash,
  ) async {
    // One statement takes the key: insert the claim, or rewrite the row it
    // hits only when that row is a claim nobody renewed or an answer past the
    // retention. No row back means someone else holds it, and the read below
    // says which of the three cases this is.
    final taken = await _db.queryOne(
      '''INSERT INTO $_table AS inc
           (principal, key, request_hash, status, response, state, taken_at)
         VALUES (@p:text, @k:text, @h:text, 0, '', 'pending', now())
         ON CONFLICT (principal, key) DO UPDATE
           SET state = 'pending', taken_at = now(),
               request_hash = EXCLUDED.request_hash, created_at = now()
           WHERE (inc.state = 'pending'
                  AND inc.taken_at
                      < now() - @lease:int4 * interval '1 millisecond')
              OR (inc.state = 'done'
                  AND inc.created_at < now() - interval '24 hours')
         RETURNING 1 AS taken''',
      {'p': principal, 'k': key, 'h': requestHash, 'lease': lease.inMilliseconds},
    );
    if (taken != null) return const ClaimTaken();
    final row = await _db.queryOne(
      '''SELECT state, request_hash, status, response FROM $_table
         WHERE principal = @p:text AND key = @k:text
           AND created_at > now() - interval '24 hours\'''',
      {'p': principal, 'k': key},
    );
    if (row == null) {
      // Swept between these two statements. The next attempt finds no row and
      // claims it for real, so waiting once is cheaper than acting twice.
      return const ClaimInProgress();
    }
    if (row.string('request_hash') != requestHash) return const ClaimConflict();
    if (row.string('state') == 'pending') return const ClaimInProgress();
    final sealed = row.string('response');
    final answer = await _sealer.open(
      sealed,
      principal: principal,
      key: key,
      requestHash: requestHash,
    );
    if (answer == null) {
      // An answer this build can no longer open (a JWT key was removed). The
      // documented answer is to run again, and running again is only honest
      // with a claim, so take the unusable row - by its exact contents, in
      // case another request is taking it too - and become the holder.
      final rewrote = await _db.execute(
        '''UPDATE $_table SET state = 'pending', taken_at = now(),
                                    status = 0, response = ''
           WHERE principal = @p:text AND key = @k:text
             AND state = 'done' AND response = @seen:text''',
        {'p': principal, 'k': key, 'seen': sealed},
      );
      return rewrote == 1 ? const ClaimTaken() : const ClaimInProgress();
    }
    final (body, headers) = answer;
    return ClaimStored(
      StoredResponse(
        requestHash: requestHash,
        status: row.integer('status'),
        body: body,
        headers: headers,
      ),
    );
  }

  @override
  Future<void> record(
    String principal,
    String key,
    StoredResponse response,
  ) async {
    await _db.execute(
      '''UPDATE $_table SET state = 'done', status = @s:int4, response = @r:text
         WHERE principal = @p:text AND key = @k:text
           AND state = 'pending' AND request_hash = @h:text''',
      {
        'p': principal,
        'k': key,
        'h': response.requestHash,
        's': response.status,
        'r': await _sealer.seal(
          response.body,
          headers: response.headers,
          principal: principal,
          key: key,
          requestHash: response.requestHash,
        ),
      },
    );
  }

  @override
  Future<void> release(String principal, String key, String requestHash) =>
      _db.execute(
        '''DELETE FROM $_table
       WHERE principal = @p:text AND key = @k:text
         AND state = 'pending' AND request_hash = @h:text''',
        {'p': principal, 'k': key, 'h': requestHash},
      );

  @override
  Future<int> sweep() => _db.execute(
    "DELETE FROM $_table WHERE created_at < now() - interval '24 hours'",
  );
}

final class InMemoryIdempotencyStore implements IdempotencyStore {
  InMemoryIdempotencyStore({this.lease = idempotencyClaimLease});

  /// The same lease the database gives a claim, measured from this process.
  final Duration lease;

  final Map<String, _Entry> _entries = {};

  @override
  Future<IdempotencyClaim> claim(
    String principal,
    String key,
    String requestHash,
  ) async {
    final id = '$principal\n$key';
    final entry = _entries[id];
    if (entry != null && !entry.isStale(lease)) {
      if (entry.requestHash != requestHash) return const ClaimConflict();
      final answer = entry.answer;
      return answer == null ? const ClaimInProgress() : ClaimStored(answer);
    }
    // Taking a stale entry replaces it, as the database's rewrite does, so
    // the claim is measured from now.
    _entries[id] = _Entry(requestHash);
    return const ClaimTaken();
  }

  @override
  Future<void> record(
    String principal,
    String key,
    StoredResponse response,
  ) async {
    // Only the holder of the claim may answer, as in the database.
    final entry = _entries['$principal\n$key'];
    if (entry?.answer == null && entry?.requestHash == response.requestHash) {
      entry!.answer = response;
    }
  }

  @override
  Future<void> release(String principal, String key, String requestHash) async {
    final id = '$principal\n$key';
    final entry = _entries[id];
    if (entry != null &&
        entry.answer == null &&
        entry.requestHash == requestHash) {
      _entries.remove(id);
    }
  }

  @override
  Future<int> sweep() async {
    final expired = [
      for (final e in _entries.entries)
        if (e.value.started.elapsed > _memoryRetention) e.key,
    ];
    for (final id in expired) {
      _entries.remove(id);
    }
    return expired.length;
  }
}

/// How long an in-memory answer is remembered: the database's retention,
/// written down once so both say the same thing about a key.
const _memoryRetention = Duration(hours: 24);

/// One key: who holds the claim, and what they answered (no answer while they
/// are still running).
final class _Entry {
  _Entry(this.requestHash);

  final String requestHash;
  final Stopwatch started = Stopwatch()..start();
  StoredResponse? answer;

  /// An answer past the retention, or a claim past its lease, is free for the
  /// next request to take.
  bool isStale(Duration lease) =>
      started.elapsed > (answer == null ? lease : _memoryRetention);
}
