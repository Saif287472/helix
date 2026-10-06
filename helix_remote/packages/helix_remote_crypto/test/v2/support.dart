import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

/// Deterministic randomness for vectors and reproducible tests:
/// `HMAC-SHA256(seed, u64(counter))` blocks. Tests only.
final class SeededRandom implements CryptoRandom {
  SeededRandom(String seed) : _key = utf8.encode('helix.v2.test-rng:$seed');

  final List<int> _key;
  int _counter = 0;
  final List<int> _pool = [];

  @override
  Uint8List nextBytes(int length) {
    while (_pool.length < length) {
      final block = Uint8List(8)..buffer.asByteData().setUint64(0, _counter++);
      _pool.addAll(hashes.Hmac(hashes.sha256, _key).convert(block).bytes);
    }
    final out = Uint8List.fromList(_pool.sublist(0, length));
    _pool.removeRange(0, length);
    return out;
  }
}

/// A settable clock.
final class TestClock {
  TestClock([DateTime? start]) : now = start ?? DateTime.utc(2026, 10, 1, 12);

  DateTime now;

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}

const accountA = '0192a4f0-0000-7000-8000-00000000000a';
const accountB = '0192a4f0-0000-7000-8000-00000000000b';
const accountC = '0192a4f0-0000-7000-8000-00000000000c';
const deviceA1 = '0192a4f0-0000-7000-8000-0000000000a1';
const deviceA2 = '0192a4f0-0000-7000-8000-0000000000a2';
const deviceB1 = '0192a4f0-0000-7000-8000-0000000000b1';
const deviceC1 = '0192a4f0-0000-7000-8000-0000000000c1';
const groupG = '0192a4f0-0000-7000-8000-0000000000ee';

final class MemorySessionStore implements PairwiseSessionStore {
  final Map<DeviceAddress, Uint8List> rows = {};

  @override
  Future<DeviceSessions?> load(DeviceAddress remote) async {
    final row = rows[remote];
    // Round-trip through bytes, as the database would.
    return row == null ? null : DeviceSessions.decode(row);
  }

  void save(DeviceSessions sessions) =>
      rows[sessions.remote] = sessions.encode();
}

final class MemoryPrekeyStore implements LocalPrekeyStore {
  final Map<int, SignedPrekeyRecord> signed = {};
  final Map<int, OneTimePrekeyRecord> oneTime = {};

  @override
  Future<SignedPrekeyRecord?> signedPrekey(int id) async => signed[id];

  @override
  Future<OneTimePrekeyRecord?> oneTimePrekey(int id) async => oneTime[id];
}

final class MemoryIdentityResolver implements DeviceIdentityResolver {
  final Map<DeviceAddress, DeviceIdentity> known = {};

  @override
  Future<DeviceIdentity?> resolve(DeviceAddress device) async => known[device];
}

/// An account: its AIK and an id.
final class TestAccount {
  TestAccount._(this.id, this.aik);

  static Future<TestAccount> create(String id, CryptoRandom random) async =>
      TestAccount._(id, await Ed25519KeyPair.generate(random));

  final String id;
  final Ed25519KeyPair aik;
}

/// A device with its keys, prekeys, stores and a session manager.
final class TestDevice {
  TestDevice._(this.account, this.keys, this.random, this.clock);

  static Future<TestDevice> create(
    TestAccount account,
    String deviceId,
    CryptoRandom random,
    TestClock clock, {
    int oneTimePrekeys = 5,
  }) async {
    final keys = await LocalDeviceKeys.create(
      accountIdentityKey: account.aik,
      address: DeviceAddress(account.id, deviceId),
      createdAt: clock.now,
      random: random,
    );
    final device = TestDevice._(account, keys, random, clock);
    final generator = PrekeyGenerator(random: random);
    final spk = await generator.signedPrekey(
      id: 1,
      deviceSigningKey: keys.signingKey,
      createdAt: clock.now,
    );
    device.prekeys.signed[spk.id] = spk;
    for (final opk in await generator.oneTimePrekeys(
      afterId: 0,
      count: oneTimePrekeys,
    )) {
      device.prekeys.oneTime[opk.id] = opk;
    }
    return device;
  }

  final TestAccount account;
  final LocalDeviceKeys keys;
  final CryptoRandom random;
  final TestClock clock;
  final MemorySessionStore sessions = MemorySessionStore();
  final MemoryPrekeyStore prekeys = MemoryPrekeyStore();
  final MemoryIdentityResolver identities = MemoryIdentityResolver();

  DeviceAddress get address => keys.address;

  late final DeviceSessionManager manager = DeviceSessionManager(
    local: keys,
    sessions: sessions,
    prekeys: prekeys,
    identities: identities,
    random: random,
    clock: clock.call,
  );

  /// What `GET /v1/keys/{account}` would return for this device, consuming
  /// the lowest one-time prekey unless [withOneTime] is false.
  DeviceBundle bundle({bool withOneTime = true}) {
    final spk = prekeys.signed.values.reduce((a, b) => a.id > b.id ? a : b);
    final ids = prekeys.oneTime.keys.toList()..sort();
    return DeviceBundle(
      deviceId: address.device,
      identityKey: keys.identityKey.publicKey,
      signingKey: keys.signingKey.publicKey,
      certificate: keys.certificate,
      signedPrekey: spk.toWire(),
      oneTimePrekey: withOneTime && ids.isNotEmpty
          ? prekeys.oneTime[ids.first]!.toWire()
          : null,
    );
  }

  Future<VerifiedPrekeyBundle> verifiedBundle({bool withOneTime = true}) =>
      VerifiedPrekeyBundle.verify(
        account: account.id,
        accountIdentityKey: account.aik.publicKey,
        bundle: bundle(withOneTime: withOneTime),
      );

  /// Lets this device accept prekey messages from [other].
  void trust(TestDevice other) =>
      identities.known[other.address] = other.keys.identity;

  Future<void> startSessionWith(
    TestDevice other, {
    bool withOneTime = true,
  }) async {
    sessions.save(
      await manager.startSession(
        await other.verifiedBundle(withOneTime: withOneTime),
      ),
    );
  }

  /// Encrypts and commits; returns the wire bytes.
  Future<Uint8List> send(TestDevice to, String text) async {
    final out = await manager.encrypt(to.address, utf8.encode(text));
    sessions.save(out.sessions);
    return out.payload.encode();
  }

  /// Decrypts and commits; returns the text.
  Future<String> receive(TestDevice from, List<int> wire) async {
    final out = await manager.decrypt(
      sender: from.address,
      payload: SealedPayload.decode(wire),
    );
    sessions.save(out.sessions);
    if (out.consumedOneTimePrekeyId != null) {
      prekeys.oneTime.remove(out.consumedOneTimePrekeyId);
    }
    return utf8.decode(out.content);
  }
}

/// Golden vectors: compares [actual] with `test/v2/vectors/<name>.json`, or
/// rewrites it when `HELIX_UPDATE_VECTORS=1`.
void expectVector(String name, Map<String, Object?> actual) {
  final file = File('test/v2/vectors/$name.json');
  final text = '${const JsonEncoder.withIndent('  ').convert(actual)}\n';
  if (Platform.environment['HELIX_UPDATE_VECTORS'] == '1') {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
    return;
  }
  expect(
    file.existsSync(),
    isTrue,
    reason: 'missing vector $name; run with HELIX_UPDATE_VECTORS=1',
  );
  expect(
    text,
    file.readAsStringSync().replaceAll('\r\n', '\n'),
    reason: 'vector $name changed; regenerate deliberately and review',
  );
}

Map<String, Object?> readVector(String name) =>
    jsonDecode(File('test/v2/vectors/$name.json').readAsStringSync())
        as Map<String, Object?>;

String hex(List<int> bytes) =>
    [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

Uint8List unhex(String text) => Uint8List.fromList([
  for (var i = 0; i < text.length; i += 2)
    int.parse(text.substring(i, i + 2), radix: 16),
]);
