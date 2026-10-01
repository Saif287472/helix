@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/kernel/presence.dart';
import 'package:helix_remote_server/src/modules/messaging/module.dart';
import 'package:helix_remote_server/src/platform/push/push.dart';
import 'package:test/test.dart';

import '../support/cluster.dart';
import '../support/flows.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';
import '../support/test_socket.dart';

const carolNumber = '+8801711000003';
const adminPassword = 'correct horse battery staple';

/// The first envelope on [socket] that passes [test]; others are skipped.
Future<Envelope> envelopeWhere(
  TestSocket socket,
  bool Function(Envelope e) test,
) async {
  while (true) {
    final envelope = await socket.envelope();
    if (test(envelope)) return envelope;
  }
}

AccountSignalEvent signalOf(Envelope e) =>
    AccountSignalEvent.fromJson(JsonReader(e.data!));

/// Two server nodes on one Postgres schema prefix, with clients spread
/// across them (ARCHITECTURE_V2_PLAN.md §4.6, Phase S7).
void main() {
  group('two nodes', skip: databaseTestSkipReason, () {
    late Cluster c;
    late Node a;
    late Node b;

    setUp(() async {
      c = await Cluster.start(extra: {'HELIX_ADMIN_PASSWORD': adminPassword});
      a = c.a;
      b = c.b;
    });

    tearDown(() async => c.stop());

    Future<int> jobCount(String kind) async => (await a.platform.db.queryOne(
      'SELECT count(*)::int8 AS n FROM ${a.platform.schemas.platform}.jobs '
      'WHERE kind = @k:text',
      {'k': kind},
    ))!.integer('n');

    Future<int> mailboxRows(TestDevice d) async =>
        (await b.platform.db.queryOne(
          'SELECT count(*)::int8 AS n FROM '
          '${b.platform.schemas.of('messaging')}.mailbox '
          'WHERE device_id = @d:uuid',
          {'d': d.id},
        ))!.integer('n');

    Future<void> setPushToken(TestDevice d, String token) async {
      final r = await a.api.call(
        Routes.setPushToken,
        bearer: d.bearer,
        body: PushTokenRequest(token: token).toJson(),
      );
      expect(r.status, 204, reason: '$r');
    }

    Future<String> adminToken(Node on) async => AdminSession.fromJson(
      (await on.api.call(
        Routes.adminSignIn,
        body: const AdminPasswordRequest(password: adminPassword).toJson(),
      )).json,
    ).token;

    group('messages', () {
      late TestDevice a1;
      late TestDevice a2;
      late TestDevice b1;
      late TestDevice b2;

      setUp(() async {
        a1 = await c.h.registerGlobal(aliceNumber);
        a2 = await secondDevice(c.h, a1, aliceNumber);
        b1 = await c.h.registerGlobal(bobNumber);
        b2 = await secondDevice(c.h, b1, bobNumber);
        for (final d in [a1, a2, b1, b2]) {
          await a.clear(d);
        }
      });

      test(
        'a send through either node arrives live on sockets on both nodes',
        () async {
          final onA = await a.online(b1);
          final onB = await b.online(b2);
          final ownCopy = await b.online(a2);

          final viaA = Uuid.v7();
          final first = await a.send(a1, {
            b1.accountId: [b1.id, b2.id],
            a1.accountId: [a2.id],
          }, id: viaA);
          expect(first.status, 200, reason: '$first');
          expect((await onA.envelope()).id, viaA);
          expect(
            (await onB.envelope()).id,
            viaA,
            reason: 'woken on node B by a send committed on node A',
          );
          final copy = await ownCopy.envelope();
          expect(copy.id, viaA);
          expect(copy.from!.device, a1.id);

          final viaB = Uuid.v7();
          expect(
            (await b.send(a1, {
              b1.accountId: [b1.id, b2.id],
              a1.accountId: [a2.id],
            }, id: viaB)).status,
            200,
          );
          expect((await onA.envelope()).id, viaB);
          expect((await onB.envelope()).id, viaB);
          expect((await ownCopy.envelope()).id, viaB);

          for (final s in [onA, onB, ownCopy]) {
            await s.close();
          }
        },
      );

      test(
        'an offline device reconnects to the other node and gets the replay',
        () async {
          final first = await a.online(b1);
          final id1 = Uuid.v7();
          await a.send(a1, {
            b1.accountId: [b1.id, b2.id],
            a1.accountId: [a2.id],
          }, id: id1);
          final live = await first.envelope();
          expect(live.id, id1);
          first.ack(live.seq!);
          await eventually(
            () async => expect(
              (await b.mailbox(b1)).envelopes.map((e) => e.id),
              isNot(contains(id1)),
            ),
          );
          await first.close();

          final id2 = Uuid.v7();
          final id3 = Uuid.v7();
          await a.send(a1, {
            b1.accountId: [b1.id, b2.id],
            a1.accountId: [a2.id],
          }, id: id2);
          await b.send(a1, {
            b1.accountId: [b1.id, b2.id],
            a1.accountId: [a2.id],
          }, id: id3);

          final again = await TestSocket.connect(b.server.baseUri, b1.bearer);
          final hello = await again.hello();
          final replay = [await again.envelope(), await again.envelope()];
          expect(replay.map((e) => e.id), [id2, id3]);
          expect(hello.lastSeq, replay.last.seq);
          expect(replay.first.seq, greaterThan(live.seq!));
          again.ack(replay.last.seq!);
          await eventually(
            () async => expect((await a.mailbox(b1)).envelopes, isEmpty),
          );
          await again.close();
        },
      );

      test('acks through either node delete for both', () async {
        await a.send(a1, {
          b1.accountId: [b1.id, b2.id],
          a1.accountId: [a2.id],
        });
        await b.send(a1, {
          b1.accountId: [b1.id, b2.id],
          a1.accountId: [a2.id],
        });
        final stored = (await b.mailbox(b1)).envelopes;
        expect(stored, hasLength(2));

        final acked = await a.ack(b1, stored.first.seq!);
        expect(AckResponse.fromJson(acked.json).deleted, 1);
        expect((await b.mailbox(b1)).envelopes.map((e) => e.seq), [
          stored.last.seq,
        ]);

        final socket = await b.online(b1);
        final rest = await socket.envelope();
        expect(rest.seq, stored.last.seq, reason: 'acked rows never replay');
        expect(await socket.silent(), isTrue);
        socket.ack(rest.seq!);
        await eventually(
          () async => expect((await a.mailbox(b1)).envelopes, isEmpty),
        );
        await socket.close();
      });

      test('a resend through the other node is not duplicated', () async {
        final socket = await b.online(b1);
        final id = Uuid.v7();
        final to = {
          b1.accountId: [b1.id, b2.id],
          a1.accountId: [a2.id],
        };
        final sent = await a.send(a1, to, id: id);
        expect(SendMessageResponse.fromJson(sent.json).replayed, isFalse);
        final resent = await b.send(a1, to, id: id);
        expect(resent.status, 200);
        expect(SendMessageResponse.fromJson(resent.json).replayed, isTrue);
        expect((await socket.envelope()).id, id);
        expect(await socket.silent(), isTrue, reason: 'delivered once');

        // The Idempotency-Key store is shared too.
        final keyed = Uuid.v7();
        final headers = {HelixHeaders.idempotencyKey: 'key-${Uuid.v7()}'};
        final original = await a.send(a1, to, id: keyed, headers: headers);
        final replay = await b.send(a1, to, id: keyed, headers: headers);
        expect(replay.status, original.status);
        expect(replay.headers['idempotent-replay'], 'true');
        expect(replay.body, original.body);
        expect((await socket.envelope()).id, keyed);
        expect(await socket.silent(), isTrue);
        expect(
          (await a.mailbox(b1)).envelopes.where((e) => e.id == keyed),
          hasLength(1),
        );
        await socket.close();
      });

      test(
        'stale device lists are detected whichever node serves the send',
        () async {
          final b3 = await secondDevice(c.h, b1, bobNumber);
          for (final node in c.nodes) {
            final stale = await node.send(a1, {
              b1.accountId: [b1.id, b2.id],
              a1.accountId: [a2.id],
            });
            expect(stale.status, 409, reason: 'node ${node.label}');
            final details = StaleDevices.fromJson(
              stale.json.object('error').object('details'),
            );
            expect(details.accounts.single.missing, [b3.id]);
          }
          await a.api.call(
            Routes.revokeDevice,
            params: {'device_id': b2.id},
            bearer: b1.bearer,
          );
          final extra = await b.send(a1, {
            b1.accountId: [b1.id, b2.id, b3.id],
            a1.accountId: [a2.id],
          });
          expect(
            StaleDevices.fromJson(
              extra.json.object('error').object('details'),
            ).accounts.single.extra,
            [b2.id],
          );
          expect(
            (await b.send(a1, {
              b1.accountId: [b1.id, b3.id],
              a1.accountId: [a2.id],
            })).status,
            200,
          );
        },
      );
    });

    group('calls', () {
      late TestDevice alice;
      late TestDevice bob1;
      late TestDevice bob2;
      late TestDevice bob3;

      setUp(() async {
        alice = await c.h.registerGlobal(aliceNumber);
        bob1 = await c.h.registerGlobal(bobNumber);
        bob2 = await secondDevice(c.h, bob1, bobNumber);
        bob3 = await secondDevice(c.h, bob1, bobNumber);
        await setPushToken(bob3, 'bob3-push');
        for (final d in [alice, bob1, bob2, bob3]) {
          await a.clear(d);
        }
      });

      Future<TestResponse> signal(
        Node via,
        TestDevice from,
        String callId,
        CallSignalKind kind,
        Map<String, List<String>> to,
      ) => via.api.call(
        Routes.sendCallSignal,
        params: {'call_id': callId},
        bearer: from.bearer,
        body: CallSignalRequest(
          kind: kind,
          recipients: [
            for (final e in to.entries)
              Recipient(
                account: e.key,
                devices: [
                  for (final d in e.value)
                    DevicePayload(device: d, payload: bytes(120, d.hashCode)),
                ],
              ),
          ],
        ).toJson(),
      );

      Future<List<PendingCall>> pending(Node via, TestDevice d) async =>
          PendingCallList.fromJson(
            (await via.api.call(Routes.pendingCalls, bearer: d.bearer)).json,
          ).calls;

      test(
        'an offer through node A rings devices on both nodes; the offline one '
        'pends, is pushed once and fetches it through node B',
        () async {
          final ringA = await a.online(bob1);
          final ringB = await b.online(bob2);
          final callId = 'call-${Uuid.v7()}';
          final r = await signal(a, alice, callId, CallSignalKind.offer, {
            bob1.accountId: [bob1.id, bob2.id, bob3.id],
          });
          expect(r.status, 200, reason: '$r');
          final response = CallSignalResponse.fromJson(r.json);
          expect(response.delivered, unorderedEquals([bob1.id, bob2.id]));
          expect(response.pending, [bob3.id]);

          for (final (socket, device) in [(ringA, bob1), (ringB, bob2)]) {
            final offer = await socket.envelope();
            expect(offer.kind, EnvelopeKind.callSignal);
            expect(offer.callId, callId);
            expect(offer.data, {'kind': 'offer'});
            expect(offer.payload, bytes(120, device.id.hashCode));
          }

          final waiting = await pending(b, bob3);
          expect(waiting.single.callId, callId);
          expect(waiting.single.from.device, alice.id);
          expect(waiting.single.payload, bytes(120, bob3.id.hashCode));

          await c.tickJobs();
          await eventually(
            () async => expect(
              c.pushes.where((p) => p.reason == PushReason.call),
              hasLength(1),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 500));
          final calls = c.pushes.where((p) => p.reason == PushReason.call);
          expect(calls.single.token, 'bob3-push');
          expect(calls.single.callId, callId);
          await ringA.close();
          await ringB.close();
        },
      );

      test(
        'answering on node B stops the devices ringing on node A; answers and '
        'hang-ups cross nodes',
        () async {
          final caller = await a.online(alice);
          final ringA = await a.online(bob1);
          final answerer = await b.online(bob2);
          final callId = 'call-${Uuid.v7()}';
          await signal(a, alice, callId, CallSignalKind.offer, {
            bob1.accountId: [bob1.id, bob2.id, bob3.id],
          });
          expect((await ringA.envelope()).data, {'kind': 'offer'});
          expect((await answerer.envelope()).data, {'kind': 'offer'});

          expect(
            (await b.api.call(
              Routes.setCallState,
              params: {'call_id': callId},
              bearer: bob2.bearer,
              body: const CallStateRequest(state: CallState.answered).toJson(),
            )).status,
            204,
          );
          final stop = await ringA.envelope();
          expect(stop.callId, callId);
          expect(stop.data, {'kind': 'end', 'state': 'answered'});
          expect(stop.from!.device, bob2.id);
          expect(await answerer.silent(), isTrue, reason: 'not told itself');
          expect(await pending(a, bob3), isEmpty);
          await c.tickJobs();
          await eventually(
            () async => expect(
              c.pushes.where((p) => p.reason == PushReason.callEnded),
              hasLength(1),
            ),
          );

          final answer = await signal(b, bob2, callId, CallSignalKind.update, {
            alice.accountId: [alice.id],
          });
          expect(CallSignalResponse.fromJson(answer.json).delivered, [
            alice.id,
          ]);
          final update = await caller.envelope();
          expect(update.data, {'kind': 'update'});
          expect(update.from!.device, bob2.id);

          final hangUp = await signal(a, alice, callId, CallSignalKind.end, {
            bob1.accountId: [bob2.id],
          });
          expect(CallSignalResponse.fromJson(hangUp.json).delivered, [bob2.id]);
          final end = await answerer.envelope();
          expect(end.callId, callId);
          expect(end.data, {'kind': 'end'});

          await Future<void>.delayed(const Duration(milliseconds: 500));
          await c.tickJobs();
          expect(
            c.pushes.map((p) => p.reason),
            unorderedEquals([PushReason.call, PushReason.callEnded]),
            reason: 'each push job ran on exactly one node',
          );
          for (final s in [caller, ringA, answerer]) {
            await s.close();
          }
        },
      );
    });

    group('revocation', () {
      late TestDevice alice;
      late TestDevice bob1;
      late TestDevice bob2;

      setUp(() async {
        alice = await c.h.registerGlobal(aliceNumber);
        bob1 = await c.h.registerGlobal(bobNumber);
        bob2 = await secondDevice(c.h, bob1, bobNumber);
        for (final d in [alice, bob1, bob2]) {
          await a.clear(d);
        }
      });

      test(
        'revoking through node A closes the socket on node B (4003), cuts its '
        'tokens there and stops its deliveries',
        () async {
          final keeper = await a.online(bob1);
          final victim = await b.online(bob2);
          await a.send(alice, {
            bob1.accountId: [bob1.id, bob2.id],
          });
          await victim.envelope();
          await keeper.envelope();

          expect(
            (await a.api.call(
              Routes.revokeDevice,
              params: {'device_id': bob2.id},
              bearer: bob1.bearer,
            )).status,
            204,
          );
          expect(await victim.closed, RealtimeCloseCode.deviceRevoked);

          expect(
            (await b.api.call(Routes.account, bearer: bob2.bearer)).status,
            401,
            reason: 'the access token is dead on the other node at once',
          );
          final refresh = await b.api.call(
            Routes.refreshSession,
            body: RefreshRequest(
              refreshToken: bob2.session!.refreshToken,
            ).toJson(),
          );
          expect(refresh.status, 401);
          await expectLater(
            TestSocket.connect(b.server.baseUri, bob2.bearer),
            throwsA(isA<WebSocketException>()),
          );

          final told = await envelopeWhere(
            keeper,
            (e) => e.kind == EnvelopeKind.accountSignal,
          );
          expect(signalOf(told).signal, AccountSignalKind.deviceRevoked);
          expect(signalOf(told).device, bob2.id);

          final stale = await b.send(alice, {
            bob1.accountId: [bob1.id, bob2.id],
          });
          expect(stale.status, 409);
          expect(
            StaleDevices.fromJson(
              stale.json.object('error').object('details'),
            ).accounts.single.extra,
            [bob2.id],
          );
          final id = Uuid.v7();
          expect(
            (await b.send(alice, {
              bob1.accountId: [bob1.id],
            }, id: id)).status,
            200,
          );
          expect(
            (await envelopeWhere(
              keeper,
              (e) => e.kind == EnvelopeKind.message,
            )).id,
            id,
          );
          expect(await mailboxRows(bob2), 0, reason: 'nothing kept for it');
          await keeper.close();
        },
      );

      test('revoking the other devices through node B closes sockets on both '
          'nodes', () async {
        final bob3 = await secondDevice(c.h, bob1, bobNumber);
        final onA = await a.online(bob2);
        final onB = await b.online(bob3);
        final revoked = await b.api.call(
          Routes.revokeOtherDevices,
          bearer: bob1.bearer,
        );
        expect(RevokeOthersResponse.fromJson(revoked.json).revoked, 2);
        expect(await onA.closed, RealtimeCloseCode.deviceRevoked);
        expect(await onB.closed, RealtimeCloseCode.deviceRevoked);
        expect(
          (await b.api.call(Routes.account, bearer: bob2.bearer)).status,
          401,
        );
        expect(
          (await a.api.call(Routes.account, bearer: bob3.bearer)).status,
          401,
        );
        for (final node in c.nodes) {
          expect(
            (await node.api.call(Routes.account, bearer: bob1.bearer)).status,
            200,
          );
        }
      });

      test(
        'sign-out and refresh-token reuse cut sessions on the other node',
        () async {
          expect(
            (await a.api.call(Routes.signOut, bearer: bob2.bearer)).status,
            204,
          );
          expect(
            (await b.api.call(Routes.account, bearer: bob2.bearer)).status,
            401,
          );
          expect(
            (await b.api.call(
              Routes.refreshSession,
              body: RefreshRequest(
                refreshToken: bob2.session!.refreshToken,
              ).toJson(),
            )).status,
            401,
          );

          final stolen = bob1.session!.refreshToken;
          final rotated = await a.api.call(
            Routes.refreshSession,
            body: RefreshRequest(refreshToken: stolen).toJson(),
          );
          expect(rotated.status, 200);
          final current = Session.fromJson(rotated.json);
          final reuse = await b.api.call(
            Routes.refreshSession,
            body: RefreshRequest(refreshToken: stolen).toJson(),
          );
          expect(reuse.status, 401);
          expect(
            (await a.api.call(
              Routes.account,
              bearer: current.accessToken,
            )).status,
            401,
            reason: 'the theft response reaches every node',
          );
          expect(
            (await a.api.call(
              Routes.refreshSession,
              body: RefreshRequest(refreshToken: current.refreshToken).toJson(),
            )).status,
            401,
          );
        },
      );

      test(
        'a password change through node A is announced on node B and applies '
        'there',
        () async {
          final other = await b.online(bob2);
          final changed = await a.api.call(
            Routes.setPassword,
            bearer: bob1.bearer,
            body: SetPasswordRequest(
              currentAuthKey: bytes(32, 9),
              password: PasswordSetup(
                kdf: const KdfParams(),
                salt: bytes(16, 2),
                authKey: bytes(32, 11),
                wrappedIdentityKey: WrappedKey(
                  nonce: bytes(12),
                  ciphertext: bytes(48),
                ),
              ),
            ).toJson(),
          );
          expect(changed.status, 204, reason: '$changed');
          final told = await envelopeWhere(
            other,
            (e) => e.kind == EnvelopeKind.accountSignal,
          );
          expect(signalOf(told).signal, AccountSignalKind.passwordChanged);

          Future<TestResponse> signIn(int keySeed) => b.api.call(
            Routes.passwordSignIn,
            body: PasswordSignInRequest(
              phoneNumber: bobNumber,
              authKey: bytes(32, keySeed),
            ).toJson(),
          );
          expect((await signIn(9)).errorCode, 'invalid_credentials');
          expect((await signIn(11)).status, 200);
          await other.close();
        },
      );

      test(
        'admin suspension through one node applies on the other; a ban closes '
        'sockets on the other node',
        () async {
          final token = await adminToken(a);
          final first = await b.online(alice);
          expect(
            (await a.api.call(
              Routes.adminSuspend,
              params: {'account': alice.accountId},
              bearer: token,
              body: const AdminActionRequest(reason: 'spam').toJson(),
            )).status,
            204,
          );
          // Suspension closes live sockets on the other node too (4004).
          expect(await first.closed, RealtimeCloseCode.suspended);
          expect(
            (await b.api.call(
              Routes.keyStatus,
              bearer: alice.bearer,
            )).errorCode,
            'account_suspended',
          );
          expect(
            (await b.api.call(Routes.account, bearer: alice.bearer)).status,
            200,
            reason: 'suspended accounts can still read',
          );
          expect(
            (await b.send(alice, {
              bob1.accountId: [bob1.id, bob2.id],
            })).errorCode,
            'account_suspended',
          );
          expect(
            (await b.api.call(
              Routes.adminUnsuspend,
              params: {'account': alice.accountId},
              bearer: token,
            )).status,
            204,
          );
          expect(
            (await a.api.call(Routes.keyStatus, bearer: alice.bearer)).status,
            200,
          );
          final socket = await b.online(alice);

          expect(
            (await b.api.call(
              Routes.adminBan,
              params: {'account': alice.accountId},
              bearer: token,
            )).status,
            204,
          );
          expect(await socket.closed, RealtimeCloseCode.deviceRevoked);
          expect(
            (await a.api.call(Routes.account, bearer: alice.bearer)).status,
            401,
          );
          final challenge = await a.api.call(
            Routes.phoneChallenge,
            body: const PhoneChallengeRequest(
              phoneNumber: aliceNumber,
              purpose: PhonePurpose.register,
            ).toJson(),
          );
          expect(challenge.errorCode, 'phone_banned');
        },
      );

      test('an admin password change ends admin sessions on the other node; '
          'maintenance mode reaches every node', () async {
        final first = await adminToken(a);
        final second = await adminToken(b);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final changed = await b.api.call(
          Routes.adminPassword,
          bearer: second,
          body: const ChangeAdminPasswordRequest(
            currentPassword: adminPassword,
            newPassword: 'a brand new password',
          ).toJson(),
        );
        expect(changed.status, 200);
        final fresh = AdminSession.fromJson(changed.json).token;
        expect(
          (await a.api.call(Routes.adminConfig, bearer: first)).status,
          401,
        );
        expect(
          (await a.api.call(Routes.adminConfig, bearer: fresh)).status,
          200,
        );

        await a.api.call(
          Routes.adminSetConfig,
          bearer: fresh,
          body: const AdminConfigPatch(maintenance: true).toJson(),
        );
        await eventually(
          () async => expect(
            (await b.api.call(Routes.keyStatus, bearer: alice.bearer)).status,
            503,
          ),
        );
        await b.api.call(
          Routes.adminSetConfig,
          bearer: fresh,
          body: const AdminConfigPatch(maintenance: false).toJson(),
        );
        await eventually(
          () async => expect(
            (await a.api.call(Routes.keyStatus, bearer: alice.bearer)).status,
            200,
          ),
        );
      });
    });

    group('supersede', () {
      test(
        'the same device connecting to node B supersedes its socket on node A '
        '(4008), and back',
        () async {
          final alice = await c.h.registerGlobal(aliceNumber);
          final bob = await c.h.registerGlobal(bobNumber);
          Future<String?> holder() =>
              a.platform.ephemeral.get(Presence.routeKey(bob.id));

          final first = await a.online(bob);
          expect(await holder(), startsWith('${a.nodeId}|'));
          final second = await b.online(bob);
          expect(await first.closed, RealtimeCloseCode.superseded);
          expect(
            await holder(),
            startsWith('${b.nodeId}|'),
            reason: 'the old node does not clear the new route',
          );
          final id = Uuid.v7();
          await a.send(alice, {
            bob.accountId: [bob.id],
          }, id: id);
          expect((await second.envelope()).id, id);

          final third = await a.online(bob);
          expect(await second.closed, RealtimeCloseCode.superseded);
          expect(await holder(), startsWith('${a.nodeId}|'));
          final replay = await third.envelope();
          expect(replay.id, id, reason: 'un-acked, so replayed');
          await third.close();
        },
      );
    });

    group('groups', () {
      test('a group send through node A reaches members on node B', () async {
        final alice = await c.h.registerGlobal(aliceNumber);
        final bob = await c.h.registerGlobal(bobNumber);
        final carol = await c.h.registerGlobal(carolNumber);
        final bobOnB = await b.online(bob);
        final carolOnA = await a.online(carol);

        final created = await a.api.call(
          Routes.createGroup,
          bearer: alice.bearer,
          body: CreateGroupRequest(
            groupId: Uuid.v7(),
            encryptedState: bytes(40),
            members: [bob.accountId, carol.accountId],
          ).toJson(),
        );
        expect(created.status, 201, reason: created.body);
        final group = Group.fromJson(created.json);
        for (final s in [bobOnB, carolOnA]) {
          final roster = await envelopeWhere(
            s,
            (e) => e.kind == EnvelopeKind.rosterChange,
          );
          expect(roster.groupId, group.groupId);
        }

        final id = Uuid.v7();
        final sent = await a.api.call(
          Routes.sendGroupMessage,
          params: {'group_id': group.groupId},
          bearer: alice.bearer,
          body: GroupMessageRequest(
            id: id,
            payload: bytes(200, 5),
            devicesDigest: membersDigest({
              alice.accountId: <String>[],
              bob.accountId: [bob.id],
              carol.accountId: [carol.id],
            }),
            distributions: [
              for (final d in [bob, carol])
                Recipient(
                  account: d.accountId,
                  devices: [DevicePayload(device: d.id, payload: bytes(90))],
                ),
            ],
          ).toJson(),
        );
        expect(sent.status, 200, reason: sent.body);
        for (final s in [bobOnB, carolOnA]) {
          final distribution = await s.envelope();
          expect(distribution.kind, EnvelopeKind.message);
          final message = await s.envelope();
          expect(message.kind, EnvelopeKind.groupMessage);
          expect(message.id, id);
          expect(message.groupId, group.groupId);
          expect(message.payload, bytes(200, 5));
        }
        await bobOnB.close();
        await carolOnA.close();
      });
    });

    group('jobs', () {
      test('push wake-ups run exactly once across both nodes', () async {
        final alice = await c.h.registerGlobal(aliceNumber);
        final recipients = [
          for (var i = 0; i < 6; i++)
            await c.h.registerGlobal(
              '+88017110001${i.toString().padLeft(2, '0')}',
            ),
        ];
        for (final (i, d) in recipients.indexed) {
          await setPushToken(d, 'token-$i');
        }
        final sent = await a.send(alice, {
          for (final d in recipients) d.accountId: [d.id],
        });
        expect(sent.status, 200, reason: '$sent');
        // Both live runners were woken by the commit; race them some more.
        await c.tickJobs();
        await eventually(
          () async => expect(c.pushes, hasLength(recipients.length)),
        );
        await Future<void>.delayed(const Duration(seconds: 3));
        await c.tickJobs();
        expect(
          c.pushes.map((p) => p.token),
          unorderedEquals([for (var i = 0; i < 6; i++) 'token-$i']),
          reason: 'one push per device, whichever node ran it',
        );
        expect(c.pushes.every((p) => p.reason == PushReason.message), isTrue);
        expect(await jobCount(MessagingModule.pushJob), 0);
      });

      test('a device online on the other node is not pushed', () async {
        final alice = await c.h.registerGlobal(aliceNumber);
        final bob = await c.h.registerGlobal(bobNumber);
        await setPushToken(bob, 'bob-push');
        final socket = await b.online(bob);
        await a.send(alice, {
          bob.accountId: [bob.id],
        });
        expect(
          await jobCount(MessagingModule.pushJob),
          0,
          reason: 'node A sees the route node B holds',
        );
        await socket.envelope();
        await socket.close();
        await eventually(
          () async => expect(
            await Presence.isOnline(a.platform.ephemeral, bob.id),
            isFalse,
          ),
        );
        await a.send(alice, {
          bob.accountId: [bob.id],
        });
        await c.tickJobs();
        await eventually(
          () async =>
              expect(c.pushes.map((p) => p.token).toList(), ['bob-push']),
        );
      });

      test('periodic jobs run once across both nodes', () async {
        final ran = await Future.wait([
          a.platform.periodic.tick(),
          b.platform.periodic.tick(),
        ]);
        final all = [...ran[0], ...ran[1]];
        expect(all.toSet(), hasLength(all.length), reason: 'never twice');
        expect(all, contains('messaging.expire'));
        final again = await Future.wait([
          a.platform.periodic.tick(),
          b.platform.periodic.tick(),
        ]);
        expect([...again[0], ...again[1]], isEmpty, reason: 'not yet due');
      });
    });
  });
}
