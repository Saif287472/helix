import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'fake_server.dart';

/// Deterministic randomness for tests (HMAC-SHA256 counter blocks).
final class SeededRandom implements CryptoRandom {
  SeededRandom(String seed) : _key = utf8.encode('helix.engine.test-rng:$seed');

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

/// A settable clock shared by the engines of one test. Every read moves it
/// on by a millisecond, so messages written one after another have distinct,
/// increasing times (as real ones do).
final class TestClock {
  TestClock([DateTime? start]) : now = start ?? DateTime.utc(2026, 10, 2, 9);

  DateTime now;

  DateTime call() {
    final value = now;
    now = now.add(const Duration(milliseconds: 1));
    return value;
  }

  void advance(Duration d) => now = now.add(d);
}

/// Fast retries for tests.
const fastConfig = EngineConfig(
  deviceName: 'Test device',
  platform: DevicePlatform.cli,
  outboxBackoff: Backoff(
    initial: Duration(seconds: 2),
    max: Duration(minutes: 1),
    jitter: 0,
  ),
  inboundRetry: Backoff(
    initial: Duration(milliseconds: 10),
    max: Duration(milliseconds: 50),
  ),
);

/// One engine on its own in-memory database against a [FakeServer].
final class Peer {
  Peer._(this.name, this.server, this.db, this.api, this.engine);

  final String name;
  final FakeServer server;
  final HelixDb db;
  final HelixApi api;
  final Engine engine;

  String get account => engine.accountId!;
  String get device => engine.deviceId!;

  /// This peer's conversation with [other].
  String chatWith(Peer other) => directConversationId(other.account);

  Future<List<MessageRow>> messages(Peer other) async =>
      (await db.messagesDao.pageOlder(chatWith(other), limit: 500)).messages;

  /// The text of the chat's visible text messages, oldest first.
  Future<List<String?>> texts(Peer other) async => [
    for (final m in await messages(other))
      if (m.deletedAt == null && m.kind == 'text') m.body,
  ];

  /// Fetches everything waiting, processes it and sends what that queued.
  Future<SyncSummary> sync() => engine.syncOnce();

  Future<void> dispose() async {
    await engine.close();
    await api.close();
    await db.close();
  }
}

/// Creates and registers engines against a shared [FakeServer].
final class Peers {
  Peers({TestClock? clock}) : clock = clock ?? TestClock() {
    server = FakeServer(clock: this.clock.call);
  }

  late final FakeServer server;
  final TestClock clock;
  final List<Peer> _all = [];
  int _seed = 0;

  Future<Peer> create(
    String name, {
    EngineConfig config = fastConfig,
    PhoneBook? phoneBook,
    Clock? clock,
    HardWipe? hardWipe,
  }) async {
    final db = HelixDb.inMemory(key: DatabaseKey.generate());
    final api = HelixApi(
      baseUrl: FakeServer.baseUri,
      sessions: DbSessionTokenStore(db),
      httpClient: server.client,
      retry: RetryPolicy.none,
    );
    final engine = Engine(
      api: api,
      db: db,
      clock: clock ?? this.clock.call,
      random: SeededRandom('$name${_seed++}'),
      config: config,
      phoneBook: phoneBook,
      hardWipe: hardWipe,
    );
    final peer = Peer._(name, server, db, api, engine);
    _all.add(peer);
    await engine.start(realtime: false, background: false);
    return peer;
  }

  /// A registered peer. [phone] makes it discoverable.
  Future<Peer> register(
    String name, {
    String? phone,
    EngineConfig config = fastConfig,
    PhoneBook? phoneBook,
    HardWipe? hardWipe,
  }) async {
    final peer = await create(
      name,
      config: config,
      phoneBook: phoneBook,
      hardWipe: hardWipe,
    );
    final challenge = await peer.engine.account.requestPhoneCode(
      phone ?? '+8801700000000',
    );
    final verified = await peer.engine.account.verifyPhone(
      challenge.challengeId,
      '123456',
    );
    await peer.engine.account.register(
      verificationToken: verified.verificationToken,
      phoneNumber: phone,
    );
    expect(peer.engine.status, EngineStatus.running);
    if (phone != null) server.accounts[peer.account]!.phone = phone;
    return peer;
  }

  /// Links a second device of [existing] (through the fake's link routes).
  Future<Peer> link(Peer existing, String name) async {
    final fresh = await create(name);
    final link = await fresh.engine.account.beginLink();
    final done = link.complete(confirm: (_) async => true);
    await existing.engine.devices.approveLink(link.code);
    await done;
    expect(fresh.account, existing.account);
    return fresh;
  }

  Future<void> dispose() async {
    for (final peer in _all.reversed) {
      try {
        await peer.dispose();
      } on Object {
        // Closed by the test.
      }
    }
  }
}

/// A phone book from a fixed list.
final class FakePhoneBook implements PhoneBook {
  FakePhoneBook(this.contacts);

  final List<PhoneBookEntry> contacts;
  final Map<String, String> saved = {};

  @override
  Future<List<PhoneBookEntry>> entries() async => contacts;

  @override
  Future<bool> saveName(String number, String name) async {
    saved[number] = name;
    return true;
  }
}
