import 'dart:async';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/account/device_service.dart';
import 'package:helix_remote_engine/src/account/key_maintenance.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/crypto/local_identity.dart';
import 'package:helix_remote_engine/src/crypto/peer_directory.dart';
import 'package:helix_remote_engine/src/maintenance.dart';
import 'package:helix_remote_engine/src/settings_keys.dart';
import 'package:test/test.dart';

import 'support/peers.dart';

/// One housekeeping pass gives up on nothing but itself (AUD-10-1).
///
/// A pass sweeps expired messages, then expired deferred actions, then
/// processed-envelope ids past the replay window, then the due crypto and
/// device upkeep, then whatever the other features handed it. All of that used
/// to sit inside a single try, so one duty that threw - a sweep past SQLite's
/// parameter limit, the database closed under it, a table mid-wipe - ended the
/// pass: the duties after it waited for the next tick, and so did the
/// re-arming of the disappearing-message timer, which only ever happened on
/// the last line. A chat whose message was due before the next tick then
/// showed it for the rest of the engine's life, because nothing rearmed the
/// timers again.
///
/// Every duty is guarded on its own now, and the timer is re-armed in a
/// `finally`.
void main() {
  test('a duty that throws does not stop the duties after it', () async {
    final peers = Peers();
    addTearDown(peers.dispose);
    final rig = await _start(peers);
    // An envelope id older than the replay window: `pruneProcessed` drops it.
    await rig.db.inboxDao.markProcessed(
      'env-old',
      seq: 1,
      outcome: EnvelopeOutcome.applied,
      at: peers.clock.now.subtract(const Duration(days: 30)),
    );
    // The duty before it now fails on a table that is not there.
    await rig.db.customStatement('DROP TABLE deferred_actions');

    await rig.maintenance().runOnce();

    expect(
      await rig.db.inboxDao.isProcessed('env-old'),
      isFalse,
      reason: 'the sweep after the failing duty still ran',
    );
  });

  test('a pass whose duty throws still rearms the expiry timer', () async {
    final peers = Peers();
    addTearDown(peers.dispose);
    final rig = await _start(peers);
    final firstPass = Completer<void>();
    final service = rig.maintenance(
      extraWork: [
        () async {
          if (!firstPass.isCompleted) firstPass.complete();
        },
      ],
    );
    // The test clock is set, not elapsed: let it keep up with real time, so a
    // timer armed in fake time can be waited out in real time.
    final ticking = Timer.periodic(
      const Duration(milliseconds: 20),
      (_) => peers.clock.advance(const Duration(milliseconds: 20)),
    );
    addTearDown(ticking.cancel);

    service.start();
    await firstPass.future;
    // The first pass re-arms too; let it find nothing to time.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final chat = (await rig.db.conversationsDao.ensureDirect(
      'bob',
      now: peers.clock.now,
    )).id;
    // Only now are there messages to time: nothing was armed for them, so the
    // one below can only be swept by a timer the next pass re-arms.
    await _addMessage(
      rig.peer,
      chat,
      'later',
      peers.clock.now.add(const Duration(hours: 1)),
    );
    await _addMessage(
      rig.peer,
      chat,
      'due',
      peers.clock.now.add(const Duration(milliseconds: 500)),
    );
    // The next pass fails on its second duty, after the message sweep (which
    // finds nothing due yet) and well before the old last-line re-arm.
    await rig.db.customStatement('DROP TABLE deferred_actions');

    await service.runOnce();

    await _eventually(() async {
      final page = await rig.db.messagesDao.pageOlder(chat, limit: 10);
      expect(page.messages.map((m) => m.messageId), [
        'later',
      ], reason: 'the timer the failing pass re-armed swept the due message');
    });
  });
}

/// A peer whose database these tests drive, with the upkeep checks pinned so
/// only the duties under test run.
final class Rig {
  Rig(this.peer, this.context);

  final Peer peer;
  final EngineContext context;

  HelixDb get db => peer.db;

  MaintenanceService maintenance({
    List<Future<void> Function()> extraWork = const [],
  }) {
    final service = MaintenanceService(
      context,
      KeyMaintenance(context),
      DeviceService(context, PeerDirectory(context)),
      extraWork: extraWork,
    );
    addTearDown(service.stop);
    return service;
  }
}

Future<Rig> _start(Peers peers) async {
  final alice = await peers.register('alice');
  final context = EngineContext(
    api: alice.api,
    db: alice.db,
    clock: peers.clock.call,
    random: SeededRandom('maintenance'),
    config: fastConfig,
  );
  context.setIdentity(await LocalIdentity.load(alice.db));
  final now = peers.clock.now;
  await alice.db.settingsDao.set(
    EngineState.lastPrekeyCheck,
    now.millisecondsSinceEpoch,
    now: now,
  );
  await alice.db.settingsDao.set(
    EngineState.lastOwnDevicesRefresh,
    now.millisecondsSinceEpoch,
    now: now,
  );
  return Rig(alice, context);
}

/// A text message in [chat] that disappears at [expiresAt].
Future<void> _addMessage(
  Peer peer,
  String chat,
  String id,
  DateTime expiresAt,
) => peer.db.messagesDao
    .insertMessage(
      MessagesCompanion.insert(
        messageId: id,
        conversationId: chat,
        sender: peer.account,
        outgoing: true,
        sortKey: SortKey.of(DateTime.utc(2026, 10, 2, 9), id),
        sentAt: DateTime.utc(2026, 10, 2, 9),
        receivedAt: DateTime.utc(2026, 10, 2, 9),
        kind: 'text',
        status: MessageStatus.sent,
        body: Value('gone $id'),
        expiresAt: Value(expiresAt),
      ),
    )
    .then((_) {});

/// Waits for a timer to bring [check] about, rather than driving the clock.
Future<void> _eventually(Future<void> Function() check) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    try {
      await check();
      return;
    } on Object {
      if (DateTime.now().isAfter(deadline)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }
}
