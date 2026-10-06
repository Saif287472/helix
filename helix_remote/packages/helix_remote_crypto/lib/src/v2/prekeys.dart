import 'dart:math';
import 'dart:typed_data';

import 'package:helix_remote_crypto/src/v2/codec.dart';
import 'package:helix_remote_crypto/src/v2/primitives.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Signed and one-time prekeys (CRYPTO_V2.md §3): records, generation, and
/// the replenishment and rotation policy as pure functions.

/// A signed prekey this device issued. The private key is kept until
/// [PrekeyPolicy.signedPrekeyRetention] after its successor was created.
final class SignedPrekeyRecord {
  const SignedPrekeyRecord({
    required this.id,
    required this.keyPair,
    required this.signature,
    required this.createdAt,
  });

  final int id;
  final X25519KeyPair keyPair;

  /// `Ed25519(DSK, "helix.v2.spk" ‖ u32(id) ‖ SPK_pub)`.
  final Uint8List signature;
  final DateTime createdAt;

  SignedPrekey toWire() =>
      SignedPrekey(id: id, publicKey: keyPair.publicKey, signature: signature);

  JsonMap toJson() => {
    'v': 1,
    'id': id,
    'priv': encodeBytes(keyPair.privateKey),
    'pub': encodeBytes(keyPair.publicKey),
    'sig': encodeBytes(signature),
    'created_at': toWireTime(createdAt),
  };

  factory SignedPrekeyRecord.fromJson(JsonReader json) =>
      readState('signed prekey', () {
        requireVersion(json, 1, 'signed prekey');
        return SignedPrekeyRecord(
          id: json.integer('id'),
          keyPair: X25519KeyPair.restore(json.bytes('priv'), json.bytes('pub')),
          signature: json.bytes('sig'),
          createdAt: json.time('created_at'),
        );
      });

  @override
  String toString() => 'SignedPrekeyRecord($id, <redacted>)';
}

/// A one-time prekey this device issued; deleted after its first use.
final class OneTimePrekeyRecord {
  const OneTimePrekeyRecord({required this.id, required this.keyPair});

  final int id;
  final X25519KeyPair keyPair;

  OneTimePrekey toWire() => OneTimePrekey(id: id, publicKey: keyPair.publicKey);

  JsonMap toJson() => {
    'v': 1,
    'id': id,
    'priv': encodeBytes(keyPair.privateKey),
    'pub': encodeBytes(keyPair.publicKey),
  };

  factory OneTimePrekeyRecord.fromJson(JsonReader json) =>
      readState('one-time prekey', () {
        requireVersion(json, 1, 'one-time prekey');
        return OneTimePrekeyRecord(
          id: json.integer('id'),
          keyPair: X25519KeyPair.restore(json.bytes('priv'), json.bytes('pub')),
        );
      });

  @override
  String toString() => 'OneTimePrekeyRecord($id, <redacted>)';
}

/// Numbers from CRYPTO_V2.md §3 and the keys REST rules.
abstract final class PrekeyPolicy {
  /// Published at registration and device linking.
  static const initialOneTimePrekeys = 100;

  /// Below this the server sends `prekeys_low` and the device tops up.
  static const lowWatermark = KeyStatus.lowWatermark;

  /// One top-up.
  static const replenishBatch = 100;

  /// The server stores at most this many per device.
  static const maxStoredOneTimePrekeys = 1000;

  /// Per `POST /v1/keys/one-time-prekeys`.
  static const maxPerRequest = AddOneTimePrekeysRequest.maxBatch;

  static const signedPrekeyRotation = Duration(days: 7);

  /// How long a replaced SPK's private key is kept for in-flight prekey
  /// messages.
  static const signedPrekeyRetention = Duration(days: 30);

  /// Prekey ids are kept in 1..[maxPrekeyId] and wrap around.
  static const maxPrekeyId = 0xffffff;

  /// How many one-time prekeys to upload when the server reports
  /// [remaining]: none at or above the watermark, otherwise one batch,
  /// capped by what the server will store.
  static int oneTimePrekeysToUpload(int remaining) {
    if (remaining >= lowWatermark) return 0;
    return max(
      0,
      min(replenishBatch, maxStoredOneTimePrekeys - max(remaining, 0)),
    );
  }

  /// Whether the current SPK (created at [currentCreatedAt]) is due for
  /// rotation.
  static bool signedPrekeyDue(DateTime currentCreatedAt, DateTime now) =>
      !now.isBefore(currentCreatedAt.add(signedPrekeyRotation));

  /// SPK ids whose private keys may be deleted now. Each record is retired
  /// when its successor (the next newer record) was created; the newest
  /// record is current and never deleted.
  static List<int> expiredSignedPrekeys(
    Iterable<SignedPrekeyRecord> records,
    DateTime now,
  ) {
    final sorted = records.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return [
      for (var i = 0; i + 1 < sorted.length; i++)
        if (!now.isBefore(sorted[i + 1].createdAt.add(signedPrekeyRetention)))
          sorted[i].id,
    ];
  }

  /// The id after [id], wrapping within 1..[maxPrekeyId].
  static int nextId(int id) => id >= maxPrekeyId || id < 1 ? 1 : id + 1;
}

/// Creates prekeys from injected randomness.
final class PrekeyGenerator {
  PrekeyGenerator({required this.random});

  final CryptoRandom random;

  Future<SignedPrekeyRecord> signedPrekey({
    required int id,
    required Ed25519KeyPair deviceSigningKey,
    required DateTime createdAt,
  }) async {
    _checkId(id);
    final pair = await X25519KeyPair.generate(random);
    final signature = await deviceSigningKey.sign(
      signedPrekeySignatureBody(id, pair.publicKey),
    );
    return SignedPrekeyRecord(
      id: id,
      keyPair: pair,
      signature: signature,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        createdAt.millisecondsSinceEpoch,
        isUtc: true,
      ),
    );
  }

  /// [count] keys with ids following [afterId] (wrapping).
  Future<List<OneTimePrekeyRecord>> oneTimePrekeys({
    required int afterId,
    required int count,
  }) async {
    if (count < 0 || count > PrekeyPolicy.maxStoredOneTimePrekeys) {
      throw ArgumentError.value(count, 'count');
    }
    final out = <OneTimePrekeyRecord>[];
    var id = afterId;
    for (var i = 0; i < count; i++) {
      id = PrekeyPolicy.nextId(id);
      out.add(
        OneTimePrekeyRecord(
          id: id,
          keyPair: await X25519KeyPair.generate(random),
        ),
      );
    }
    return out;
  }

  static void _checkId(int id) {
    if (id < 1 || id > PrekeyPolicy.maxPrekeyId) {
      throw ArgumentError.value(id, 'id', 'prekey ids are 1..2^24-1');
    }
  }
}

/// Read access to this device's prekey private keys. `helix_remote_db`
/// implements it; consuming a one-time prekey is a write the caller commits
/// together with the new session (see `PairwiseDecryptResult`).
abstract interface class LocalPrekeyStore {
  Future<SignedPrekeyRecord?> signedPrekey(int id);

  Future<OneTimePrekeyRecord?> oneTimePrekey(int id);
}
