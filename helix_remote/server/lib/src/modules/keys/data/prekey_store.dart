import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

final class PrekeyStore {
  PrekeyStore(this.s);

  final String s;

  Future<void> setSignedPrekey(
    SqlSession db,
    String deviceId,
    SignedPrekey spk,
  ) async {
    await db.execute(
      'INSERT INTO $s.signed_prekeys (device_id, key_id, public_key, signature) '
      'VALUES (@d:uuid, @id:int4, @pk:bytea, @sig:bytea) '
      'ON CONFLICT (device_id) DO UPDATE SET key_id = excluded.key_id, '
      'public_key = excluded.public_key, signature = excluded.signature, updated_at = now()',
      {'d': deviceId, 'id': spk.id, 'pk': spk.publicKey, 'sig': spk.signature},
    );
  }

  Future<SignedPrekey?> signedPrekey(SqlSession db, String deviceId) async {
    final r = await db.queryOne(
      'SELECT key_id, public_key, signature FROM $s.signed_prekeys WHERE device_id = @d:uuid',
      {'d': deviceId},
    );
    if (r == null) return null;
    return SignedPrekey(
      id: r.integer('key_id'),
      publicKey: r.bytes('public_key'),
      signature: r.bytes('signature'),
    );
  }

  /// Adds keys; ids already stored are ignored (uploads are retry-safe).
  Future<void> addOneTime(
    SqlSession db,
    String deviceId,
    List<OneTimePrekey> keys,
  ) async {
    for (final k in keys) {
      await db.execute(
        'INSERT INTO $s.one_time_prekeys (device_id, key_id, public_key) '
        'VALUES (@d:uuid, @id:int4, @pk:bytea) ON CONFLICT DO NOTHING',
        {'d': deviceId, 'id': k.id, 'pk': k.publicKey},
      );
    }
  }

  /// Removes and returns one key. Concurrent fetches never get the same key.
  Future<OneTimePrekey?> takeOneTime(SqlSession db, String deviceId) async {
    final r = await db.queryOne(
      'DELETE FROM $s.one_time_prekeys WHERE (device_id, key_id) = ('
      '  SELECT device_id, key_id FROM $s.one_time_prekeys WHERE device_id = @d:uuid '
      '  ORDER BY key_id LIMIT 1 FOR UPDATE SKIP LOCKED'
      ') RETURNING key_id, public_key',
      {'d': deviceId},
    );
    return r == null
        ? null
        : OneTimePrekey(
            id: r.integer('key_id'),
            publicKey: r.bytes('public_key'),
          );
  }

  Future<int> oneTimeCount(SqlSession db, String deviceId) async {
    final r = await db.queryOne(
      'SELECT count(*) AS n FROM $s.one_time_prekeys WHERE device_id = @d:uuid',
      {'d': deviceId},
    );
    return r!.integer('n');
  }

  Future<KeyStatus> status(SqlSession db, String deviceId) async {
    final spk = await db.queryOne(
      'SELECT key_id, updated_at FROM $s.signed_prekeys WHERE device_id = @d:uuid',
      {'d': deviceId},
    );
    return KeyStatus(
      oneTimeRemaining: await oneTimeCount(db, deviceId),
      signedPrekeyId: spk?.integer('key_id'),
      signedPrekeyUpdatedAt: spk?.time('updated_at'),
    );
  }

  Future<void> purgeDevice(SqlSession db, String deviceId) async {
    await db.execute(
      'DELETE FROM $s.one_time_prekeys WHERE device_id = @d:uuid',
      {'d': deviceId},
    );
    await db.execute(
      'DELETE FROM $s.signed_prekeys WHERE device_id = @d:uuid',
      {'d': deviceId},
    );
  }
}
