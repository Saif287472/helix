import 'dart:async';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../../support/flows.dart';
import '../../support/harness.dart';

/// Short timers so retries and housekeeping show up within a test.
const testEngineConfig = EngineConfig(
  deviceName: 'Test device',
  platform: DevicePlatform.cli,
  outboxBackoff: Backoff(
    initial: Duration(milliseconds: 40),
    max: Duration(milliseconds: 400),
  ),
  inboundRetry: Backoff(
    initial: Duration(milliseconds: 40),
    max: Duration(milliseconds: 200),
  ),
  maintenanceInterval: Duration(minutes: 30),
);

/// One engine on its own encrypted in-memory database, talking to the
/// in-process server through the real REST and WebSocket clients.
final class EngineUser {
  EngineUser._(this.name, this.db, this.api, this.engine, this.key);

  final String name;
  final HelixDb db;
  final HelixApi api;
  final Engine engine;
  final DatabaseKey key;

  String get account => engine.accountId!;
  String get device => engine.deviceId!;

  Future<void> dispose() async {
    await engine.close();
    await api.close();
    await db.close();
  }
}

/// Builds engines against a [Harness] and cleans them up.
final class EngineWorld {
  EngineWorld(this.h);

  final Harness h;
  final List<EngineUser> _users = [];

  Future<EngineUser> create(
    String name, {
    EngineConfig config = testEngineConfig,
    HelixDb? db,
    DatabaseKey? key,
    bool start = true,
    bool realtime = true,
    Clock clock = DateTime.now,
  }) async {
    final databaseKey = key ?? DatabaseKey.generate();
    final database = db ?? HelixDb.inMemory(key: databaseKey);
    final api = HelixApi(
      baseUrl: h.server.baseUri,
      sessions: DbSessionTokenStore(database),
      clientName: 'engine-test/$name',
    );
    final engine = Engine(
      api: api,
      db: database,
      clock: clock,
      random: SecureCryptoRandom(),
      config: config,
    );
    final user = EngineUser._(name, database, api, engine, databaseKey);
    _users.add(user);
    if (start) await engine.start(realtime: realtime);
    return user;
  }

  /// A registered, running engine for [number] (Helix Global phone flow).
  Future<EngineUser> register(
    String name,
    String number, {
    String? password,
    bool realtime = true,
    EngineConfig config = testEngineConfig,
  }) async {
    final user = await create(name, realtime: realtime, config: config);
    final challenge = await user.engine.account.requestPhoneCode(number);
    final verified = await user.engine.account.verifyPhone(
      challenge.challengeId,
      h.sms.lastCodeFor(number),
    );
    await user.engine.account.register(
      verificationToken: verified.verificationToken,
      phoneNumber: number,
      password: password,
    );
    expect(user.engine.status, EngineStatus.running);
    return user;
  }

  /// Links a second device of [existing] by QR code: the new device shows
  /// the code, [existing] approves it.
  Future<EngineUser> link(
    EngineUser existing,
    String name, {
    bool realtime = true,
  }) async {
    final fresh = await create(name, realtime: realtime);
    final link = await fresh.engine.account.beginLink();
    final done = link.complete();
    await existing.engine.devices.approveLink(link.code);
    await done.timeout(const Duration(seconds: 20));
    expect(fresh.engine.status, EngineStatus.running);
    expect(fresh.account, existing.account);
    return fresh;
  }

  Future<void> dispose() async {
    for (final user in _users.reversed) {
      try {
        await user.dispose();
      } on Object {
        // Already closed by the test.
      }
    }
    _users.clear();
  }
}

/// Waits (up to [timeout]) for [check] to stop throwing.
Future<void> settle(
  Future<void> Function() check, {
  Duration timeout = const Duration(seconds: 15),
}) => eventually(check, timeout: timeout);

/// The direct chat of [user] with [peer], or null.
Future<ConversationRow?> chatWith(EngineUser user, EngineUser peer) =>
    user.db.conversationsDao.byId(directConversationId(peer.account));

/// Messages of the chat, oldest first.
Future<List<MessageRow>> messagesWith(EngineUser user, EngineUser peer) async {
  final page = await user.db.messagesDao.pageOlder(
    directConversationId(peer.account),
    limit: 200,
  );
  return page.messages;
}

/// Waits until [user] has a message with [text] from [peer] and returns it.
Future<MessageRow> waitForText(
  EngineUser user,
  EngineUser peer,
  String text,
) async {
  late MessageRow found;
  await settle(() async {
    final all = await messagesWith(user, peer);
    final match = all.where((m) => m.body == text && m.deletedAt == null);
    expect(match, isNotEmpty, reason: '${user.name} has no "$text"');
    found = match.first;
  });
  return found;
}
