import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/crypto/db_stores.dart';
import 'package:helix_remote_engine/src/settings_keys.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The prekeys a new device publishes (CRYPTO_V2.md §3): one signed prekey
/// and [PrekeyPolicy.initialOneTimePrekeys] one-time prekeys.
final class InitialPrekeys {
  const InitialPrekeys({required this.signed, required this.oneTime});

  final SignedPrekeyRecord signed;
  final List<OneTimePrekeyRecord> oneTime;

  PrekeyUpload toUpload() => PrekeyUpload(
    signedPrekey: signed.toWire(),
    oneTimePrekeys: [for (final k in oneTime) k.toWire()],
  );

  /// The rows to store, and the counters that keep ids from being reused.
  List<PrekeysCompanion> rows(DateTime now) => [
    DbPrekeyStore.signedRow(signed),
    for (final k in oneTime) DbPrekeyStore.oneTimeRow(k, now),
  ];

  int get lastOneTimeId => oneTime.isEmpty ? 0 : oneTime.last.id;
}

/// Prekey upkeep for the signed-in device (CRYPTO_V2.md §3):
///
/// - **Replenishment.** When the server reports fewer than
///   [KeyStatus.lowWatermark] one-time prekeys (the `prekeys_low` envelope,
///   or the periodic status check), a batch of [PrekeyPolicy.replenishBatch]
///   is generated, stored locally FIRST and then uploaded: a key a peer
///   might receive is always one this device can answer.
/// - **Rotation.** The signed prekey is replaced every 7 days; the old
///   private key is kept 30 days for messages already in flight, then
///   deleted. A signed prekey the server does not advertise yet (an upload
///   that failed) is uploaded again.
///
/// Ids come from counters in the settings table so a prekey id is never
/// reused, even after its key was consumed and deleted.
final class KeyMaintenance {
  KeyMaintenance(this._ctx);

  final EngineContext _ctx;

  HelixDb get _db => _ctx.db;

  /// The initial prekeys for a device with signing key [signingKey]:
  /// signed prekey id 1, one-time ids 1..100.
  static Future<InitialPrekeys> initial({
    required Ed25519KeyPair signingKey,
    required CryptoRandom random,
    required DateTime now,
    int oneTimeCount = PrekeyPolicy.initialOneTimePrekeys,
  }) async {
    final generator = PrekeyGenerator(random: random);
    return InitialPrekeys(
      signed: await generator.signedPrekey(
        id: 1,
        deviceSigningKey: signingKey,
        createdAt: now,
      ),
      oneTime: await generator.oneTimePrekeys(afterId: 0, count: oneTimeCount),
    );
  }

  /// One maintenance pass: status check, signed-prekey rotation and
  /// replenishment, cleanup of old private keys. Network errors propagate;
  /// the caller retries on its next tick.
  Future<void> run() async {
    final status = await _ctx.api.keys.status();
    await _syncSignedPrekey(status);
    await replenish(status.oneTimeRemaining);
    final records = [
      for (final row in await _db.cryptoDao.prekeysOf(PrekeyKind.signed))
        DbPrekeyStore.signedRecord(row),
    ];
    for (final id in PrekeyPolicy.expiredSignedPrekeys(records, _ctx.now())) {
      await _db.cryptoDao.deletePrekey(PrekeyKind.signed, id);
    }
    await _db.settingsDao.set(
      EngineState.lastPrekeyCheck,
      _ctx.now().millisecondsSinceEpoch,
      now: _ctx.now(),
    );
  }

  /// Uploads a batch when [remaining] (as the server reports it) is below
  /// the watermark. Returns how many were uploaded.
  Future<int> replenish(int remaining) async {
    var wanted = PrekeyPolicy.oneTimePrekeysToUpload(remaining);
    var uploaded = 0;
    final generator = PrekeyGenerator(random: _ctx.random);
    while (wanted > 0) {
      final batch = wanted > PrekeyPolicy.maxPerRequest
          ? PrekeyPolicy.maxPerRequest
          : wanted;
      final counter = await _db.settingsDao.get(
        EngineState.oneTimePrekeyCounter,
      );
      final keys = await generator.oneTimePrekeys(
        afterId: counter,
        count: batch,
      );
      final now = _ctx.now();
      await _db.transaction(() async {
        await _db.cryptoDao.savePrekeys([
          for (final k in keys) DbPrekeyStore.oneTimeRow(k, now),
        ]);
        await _db.settingsDao.set(
          EngineState.oneTimePrekeyCounter,
          keys.last.id,
          now: now,
        );
      });
      await _ctx.api.keys.addOneTimePrekeys([for (final k in keys) k.toWire()]);
      uploaded += batch;
      wanted -= batch;
    }
    return uploaded;
  }

  /// Makes the newest local signed prekey the one the server advertises,
  /// creating a new one first when the current one is due for rotation.
  Future<void> _syncSignedPrekey(KeyStatus status) async {
    final now = _ctx.now();
    final rows = await _db.cryptoDao.prekeysOf(PrekeyKind.signed);
    final current = rows.where((r) => r.retiredAt == null).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final newest = current.isEmpty ? null : current.last;
    if (newest == null || PrekeyPolicy.signedPrekeyDue(newest.createdAt, now)) {
      final counter = await _db.settingsDao.get(
        EngineState.signedPrekeyCounter,
      );
      final id = PrekeyPolicy.nextId(counter);
      final fresh = await PrekeyGenerator(random: _ctx.random).signedPrekey(
        id: id,
        deviceSigningKey: _ctx.identity.keys.signingKey,
        createdAt: now,
      );
      await _db.transaction(() async {
        await _db.cryptoDao.savePrekeys([DbPrekeyStore.signedRow(fresh)]);
        await _db.settingsDao.set(
          EngineState.signedPrekeyCounter,
          id,
          now: now,
        );
      });
      await _ctx.api.keys.setSignedPrekey(fresh.toWire());
      // The old one stays usable for 30 days, then run() deletes it.
      for (final old in current) {
        await _db.cryptoDao.retireSignedPrekey(old.keyId, now);
      }
      return;
    }
    if (status.signedPrekeyId != newest.keyId) {
      await _ctx.api.keys.setSignedPrekey(
        DbPrekeyStore.signedRecord(newest).toWire(),
      );
    }
  }
}
