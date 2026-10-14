import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../support/flows.dart';
import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';
import '../support/test_socket.dart';

/// A database restored from a backup gives out `seq`s again from below the
/// cursors phones already hold (review H-01, batch 9; REALTIME_V2.md,
/// "Restored server"). Simulated by moving `device_seq.last_seq` back.
void main() {
  group('a server restored from a backup', skip: databaseTestSkipReason, () {
    late Harness h;
    late TestDevice alice;
    late TestDevice bob;

    setUp(() async {
      h = await Harness.start();
      alice = await h.registerGlobal(aliceNumber);
      bob = await h.registerGlobal(bobNumber);
    });

    tearDown(() async => h.stop());

    Future<void> toBob() async {
      final r = await send(h, alice, {
        bob.accountId: [bob.id],
      });
      expect(r.status, 200, reason: r.body);
    }

    Future<int> ack(int seq) async => AckResponse.fromJson(
      (await h.api.call(
        Routes.ackMailbox,
        bearer: bob.bearer,
        body: AckRequest(seq: seq).toJson(),
      )).json,
    ).deleted;

    /// Bob receives and acks five envelopes (his cursor is then 5), then the
    /// database goes back to when only [head] had been given to him.
    Future<void> receiveFiveThenRestoreTo(int head) async {
      for (var i = 0; i < 5; i++) {
        await toBob();
      }
      final page = await mailbox(h, bob);
      expect(page.envelopes.last.seq, 5);
      expect(page.seqHead, 5);
      expect(await ack(5), 5);
      await h.env.platform.db.execute(
        'UPDATE ${h.env.platform.schemas.of('messaging')}.device_seq '
        'SET last_seq = @h:int8 WHERE device_id = @d:uuid',
        {'h': head, 'd': bob.id},
      );
    }

    test(
      'the mailbox replays from the start and says where the head is',
      () async {
        await receiveFiveThenRestoreTo(2);
        await toBob();
        final page = await mailbox(h, bob, after: 5);
        expect(page.seqHead, 3);
        expect(
          page.envelopes.map((e) => e.seq),
          [3],
          reason: 'from the cursor, seq 3 would never be seen',
        );
        final normal = await mailbox(h, bob, after: 2);
        expect(normal.envelopes.map((e) => e.seq), [3]);
      },
    );

    test('an ack above the head deletes nothing', () async {
      await receiveFiveThenRestoreTo(2);
      await toBob();
      expect(
        await ack(5),
        0,
        reason: 'seq 5 was never given after the restore',
      );
      expect((await mailbox(h, bob)).envelopes.map((e) => e.seq), [3]);
      expect(await ack(3), 1);
    });

    test(
      'the socket replays from the start, and hello carries the head',
      () async {
        await receiveFiveThenRestoreTo(2);
        await toBob();
        final socket = await TestSocket.connect(
          h.server.baseUri,
          bob.bearer,
          after: 5,
        );
        final hello = await socket.hello();
        expect(hello.seqHead, 3);
        expect((await socket.envelope()).seq, 3);
        socket.ack(5);
        await socket.close();
        expect(
          (await mailbox(h, bob)).envelopes.map((e) => e.seq),
          [3],
          reason: 'the stale ack the old app sends after hello deletes nothing',
        );
      },
    );
  });
}
