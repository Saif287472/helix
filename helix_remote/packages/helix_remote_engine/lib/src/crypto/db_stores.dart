import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// [PairwiseSessionStore] over the `sessions` table. A [DeviceSessions]
/// record maps onto the six slots: slot 0 holds the active session and the
/// retired base keys, slots 1-5 the previous sessions, each as UTF-8 JSON
/// (`PairwiseSession.toJson`). Reads only through the crypto interface; the
/// engine commits what the crypto layer returns, inside its own
/// transactions ([save]).
final class DbSessionStore implements PairwiseSessionStore {
  DbSessionStore(this._db);

  final HelixDb _db;

  @override
  Future<DeviceSessions?> load(DeviceAddress remote) async {
    final rows = await _db.cryptoDao.sessionsWith(
      remote.account,
      remote.device,
    );
    if (rows.isEmpty) return null;
    return decode(remote, [for (final row in rows) row.state]);
  }

  /// Writes [sessions] (call inside the transaction of the message's effect).
  Future<void> save(DeviceSessions sessions, {required DateTime now}) {
    final remote = sessions.remote;
    if (sessions.isEmpty && sessions.retiredBaseKeys.isEmpty) {
      return _db.cryptoDao.deleteSessions(
        remote.account,
        device: remote.device,
      );
    }
    return _db.cryptoDao.saveSessions(
      remote.account,
      remote.device,
      encode(sessions),
      now: now,
    );
  }

  /// Slot 0 first, then the previous sessions.
  static List<Uint8List> encode(DeviceSessions sessions) => [
    _bytes({
      'v': 1,
      'retired': [for (final k in sessions.retiredBaseKeys) encodeBytes(k)],
      'active': ?sessions.active?.toJson(),
    }),
    for (final previous in sessions.previous) _bytes(previous.toJson()),
  ];

  static DeviceSessions decode(DeviceAddress remote, List<Uint8List> slots) {
    JsonReader read(Uint8List bytes) => JsonReader.decode(utf8.decode(bytes));
    final head = read(slots.first);
    if (head.integer('v') != 1) {
      throw const MalformedCryptoInputException('unsupported session slot');
    }
    return DeviceSessions(
      remote: remote,
      active: head.has('active')
          ? PairwiseSession.fromJson(head.object('active'))
          : null,
      previous: [
        for (final bytes in slots.skip(1))
          PairwiseSession.fromJson(read(bytes)),
      ],
      retiredBaseKeys: [
        for (final k in head.optStrings('retired')) decodeBytes(k),
      ],
    );
  }

  static Uint8List _bytes(JsonMap json) =>
      Uint8List.fromList(utf8.encode(jsonEncode(json)));
}

/// [LocalPrekeyStore] over the `prekeys` table. A retired signed prekey
/// still answers until it is deleted (30 days, CRYPTO_V2.md §3).
final class DbPrekeyStore implements LocalPrekeyStore {
  DbPrekeyStore(this._db);

  final HelixDb _db;

  @override
  Future<SignedPrekeyRecord?> signedPrekey(int id) async {
    final row = await _db.cryptoDao.prekey(PrekeyKind.signed, id);
    return row == null ? null : signedRecord(row);
  }

  @override
  Future<OneTimePrekeyRecord?> oneTimePrekey(int id) async {
    final row = await _db.cryptoDao.prekey(PrekeyKind.oneTime, id);
    return row == null
        ? null
        : OneTimePrekeyRecord(
            id: row.keyId,
            keyPair: X25519KeyPair.restore(row.privateKey, row.publicKey),
          );
  }

  static SignedPrekeyRecord signedRecord(PrekeyRow row) => SignedPrekeyRecord(
    id: row.keyId,
    keyPair: X25519KeyPair.restore(row.privateKey, row.publicKey),
    signature: row.signature!,
    createdAt: row.createdAt,
  );

  static PrekeysCompanion signedRow(SignedPrekeyRecord key) =>
      PrekeysCompanion.insert(
        kind: PrekeyKind.signed,
        keyId: key.id,
        publicKey: key.keyPair.publicKey,
        privateKey: key.keyPair.privateKey,
        signature: Value(key.signature),
        createdAt: key.createdAt,
      );

  static PrekeysCompanion oneTimeRow(OneTimePrekeyRecord key, DateTime now) =>
      PrekeysCompanion.insert(
        kind: PrekeyKind.oneTime,
        keyId: key.id,
        publicKey: key.keyPair.publicKey,
        privateKey: key.keyPair.privateKey,
        createdAt: now,
      );
}
