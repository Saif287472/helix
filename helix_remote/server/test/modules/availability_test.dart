import 'dart:async';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/groups/module.dart';
import 'package:helix_remote_server/src/modules/identity/config.dart';
import 'package:helix_remote_server/src/modules/messaging/api.dart';
import 'package:helix_remote_server/src/modules/messaging/data/mailbox_store.dart';
import 'package:helix_remote_server/src/modules/messaging/module.dart';
import 'package:helix_remote_server/src/platform/config/server_config.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:test/test.dart';

import '../support/flows.dart';
import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';
import '../support/test_platform.dart';

const carolNumber = '+8801711000003';

/// Delivery stays available when one device, member or disk misbehaves
/// (review 2026-10-09, batch 2: A-01, A-02, A-03, A-09).
void main() {
  group('HELIX_DEVICE_INACTIVE_DAYS', () {
    IdentityConfig identityConfig(String? days) => IdentityConfig.from(
      ServerConfig.fromEnv({
        'HELIX_DATABASE_URL': 'postgresql://u:p@localhost/db',
        'HELIX_JWT_KEYS': '{"test":"$testJwtKey"}',
        'HELIX_PHONE_PEPPER': testPepper,
        'HELIX_DEVICE_INACTIVE_DAYS': ?days,
      }),
    );

    test('off unless set; 14 days at least', () {
      expect(identityConfig(null).inactiveDeviceDays, 0);
      expect(identityConfig('0').inactiveDeviceDays, 0);
      expect(identityConfig('30').inactiveDeviceDays, 30);
      for (final bad in ['5', '13', 'soon', '4000']) {
        expect(
          () => identityConfig(bad),
          throwsA(isA<ConfigError>()),
          reason: bad,
        );
      }
    });
  });

  group('availability', skip: databaseTestSkipReason, () {
    late Harness h;

    tearDown(() async => h.stop());

    String table(String module, String name) =>
        '${h.env.platform.schemas.of(module)}.$name';

    Future<List<int>> seqs(TestDevice d) async => [
      for (final e in (await mailbox(h, d)).envelopes)
        if (e.kind == EnvelopeKind.message) e.seq!,
    ];

    Future<int> pending(
      String deviceId,
    ) async => (await h.env.platform.db.queryOne(
      'SELECT pending FROM ${table('messaging', 'device_seq')} WHERE device_id = @d:uuid',
      {'d': deviceId},
    ))!.integer('pending');

    Future<int> rows(
      String deviceId,
    ) async => (await h.env.platform.db.queryOne(
      'SELECT count(*)::int8 AS n FROM ${table('messaging', 'mailbox')} WHERE device_id = @d:uuid',
      {'d': deviceId},
    ))!.integer('n');

    group('mailbox quota (A-01)', () {
      test(
        'a device over its quota loses its oldest envelopes; sends to it keep working',
        () async {
          h = await Harness.start();
          final alice = await h.registerGlobal(aliceNumber);
          final bob = await h.registerGlobal(bobNumber);
          for (var i = 0; i < 3; i++) {
            expect(
              (await send(h, alice, {
                bob.accountId: [bob.id],
              })).status,
              200,
            );
          }
          expect(await seqs(bob), [1, 2, 3]);
          // Bob's device has stopped collecting: it is at its quota.
          await h.env.platform.db.execute(
            'UPDATE ${table('messaging', 'device_seq')} SET pending = @n:int4 WHERE device_id = @d:uuid',
            {'d': bob.id, 'n': MailboxStore.quota},
          );

          final r = await send(h, alice, {
            bob.accountId: [bob.id],
          });
          expect(r.status, 200, reason: 'a full mailbox never fails the send');
          expect(await seqs(bob), [2, 3, 4], reason: 'the oldest one went');
          expect(await pending(bob.id), MailboxStore.quota);

          expect(
            (await send(h, alice, {
              bob.accountId: [bob.id],
            })).status,
            200,
          );
          expect(await seqs(bob), [3, 4, 5]);
          expect(
            h.env.platform.metrics.render(),
            contains('helix_mailbox_trimmed_total 2'),
          );
        },
      );
    });

    group('deliveries and revokes (A-09)', () {
      late TestDevice bob;
      late TestDevice bob2;

      setUp(() async {
        h = await Harness.start();
        bob = await h.registerGlobal(bobNumber);
        bob2 = await secondDevice(h, bob, bobNumber);
      });

      test(
        'a revoked device gets no rows, even from a send already checked',
        () async {
          expect(
            (await h.api.call(
              Routes.revokeDevice,
              params: {'device_id': bob2.id},
              bearer: bob.bearer,
            )).status,
            204,
          );
          // As if the device list was checked before the revoke.
          await h.env.platform.db.tx(
            (tx) => h.messaging.api.deliver(tx, {
              bob.id: bytes(10),
              bob2.id: bytes(10),
            }, const Delivery(kind: EnvelopeKind.message)),
          );
          expect(await rows(bob2.id), 0);
          expect(await rows(bob.id), greaterThan(0));
        },
      );

      test(
        'a revoke waits for a delivery in flight, then purges what it stored',
        () async {
          final hold = Completer<void>();
          final stored = Completer<void>();
          final delivery = h.env.platform.db.tx((tx) async {
            await h.messaging.api.deliver(tx, {
              bob2.id: bytes(10),
            }, const Delivery(kind: EnvelopeKind.message));
            stored.complete();
            await hold.future;
          });
          await stored.future;
          var revoked = false;
          final revoke = h.api
              .call(
                Routes.revokeDevice,
                params: {'device_id': bob2.id},
                bearer: bob.bearer,
              )
              .then((r) {
                revoked = true;
                return r;
              });
          await Future<void>.delayed(const Duration(milliseconds: 500));
          expect(revoked, isFalse, reason: 'the revoke waits for the lock');
          hold.complete();
          await delivery;
          expect((await revoke).status, 204);
          expect(await rows(bob2.id), 0, reason: 'its hook purged the rows');
        },
      );
    });

    group('group sends (A-02)', () {
      late TestDevice alice;
      late TestDevice bob;
      late TestDevice carol;

      setUp(() async {
        h = await Harness.start();
        alice = await h.registerGlobal(aliceNumber);
        bob = await h.registerGlobal(bobNumber);
        carol = await h.registerGlobal(carolNumber);
      });

      Future<String> create() async {
        final r = await h.api.call(
          Routes.createGroup,
          bearer: alice.bearer,
          body: CreateGroupRequest(
            groupId: Uuid.v7(),
            encryptedState: bytes(40),
            members: [bob.accountId, carol.accountId],
          ).toJson(),
        );
        expect(r.status, 201, reason: r.body);
        return Group.fromJson(r.json).groupId;
      }

      /// 250 KiB is 16 units per device: 32 for this group of two others.
      const large = 250 * 1024;

      Future<TestResponse> groupSend(
        String groupId, {
        bool ephemeral = false,
        int size = 200,
        bool distribute = false,
      }) => h.api.call(
        Routes.sendGroupMessage,
        params: {'group_id': groupId},
        bearer: alice.bearer,
        body: GroupMessageRequest(
          id: Uuid.v7(),
          payload: bytes(size),
          devicesDigest: membersDigest({
            alice.accountId: <String>[],
            bob.accountId: [bob.id],
            carol.accountId: [carol.id],
          }),
          distributions: [
            if (distribute)
              for (final d in [bob, carol])
                Recipient(
                  account: d.accountId,
                  devices: [DevicePayload(device: d.id, payload: bytes(size))],
                ),
          ],
          ephemeral: ephemeral,
        ).toJson(),
      );

      // Takes every token, from the whole capacity down to single ones.
      Future<void> drain(RateLimitPolicy policy, String key) async {
        final limiter = h.env.platform.rateLimiter;
        for (var cost = policy.capacity; cost >= 1; cost ~/= 2) {
          while ((await limiter.hit(policy, key, cost: cost)).allowed) {}
        }
      }

      // Buckets refill while the test runs: drain right before each try.
      Future<bool> refusedAfterDrain(
        RateLimitPolicy policy,
        String key,
        Future<TestResponse> Function() call,
      ) async {
        for (var i = 0; i < 5; i++) {
          await drain(policy, key);
          if ((await call()).errorCode == 'rate_limited') return true;
        }
        return false;
      }

      Future<double?> tokens(
        RateLimitPolicy policy,
        String key,
      ) async => (await h.env.platform.db.queryOne(
        'SELECT tokens FROM ${h.env.platform.schemas.platform}.rate_buckets '
        'WHERE key = @k:text',
        {'k': '${policy.name}:$key'},
      ))?.float('tokens');

      test('group sends are limited per device', () async {
        final g = await create();
        expect((await groupSend(g)).status, 200);
        expect(
          await refusedAfterDrain(
            GroupsModule.sendPerDevice,
            'device:${alice.id}',
            () => groupSend(g),
          ),
          isTrue,
        );
      });

      test(
        'a spent stored budget refuses group sends; ephemeral sends are free',
        () async {
          final g = await create();
          const budget = MessagingModule.storedPerAccount;
          final key = 'account:${alice.accountId}';
          // 64 units (payload and distributions): 256 ms to refill.
          expect(
            await refusedAfterDrain(
              budget,
              key,
              () => groupSend(g, size: large, distribute: true),
            ),
            isTrue,
          );
          await drain(budget, key);
          expect(
            (await groupSend(g, ephemeral: true, size: large)).status,
            200,
            reason: 'typing indicators store nothing',
          );
          expect(
            (await send(h, bob, {
              alice.accountId: [alice.id],
            })).status,
            200,
            reason: 'other accounts are not affected',
          );
        },
      );

      test(
        'a group send reaches the group budget before the sender pays',
        () async {
          final g = await create();
          const budget = MessagingModule.storedPerAccount;
          // One cheap send first: it creates both buckets, and its group
          // budget hit is the stamp the parked send's is compared to.
          expect((await groupSend(g)).status, 200);
          Future<DateTime>
          groupBudgetHit() async => (await h.env.platform.db.queryOne(
            'SELECT updated_at FROM ${h.env.platform.schemas.platform}.rate_buckets '
            'WHERE key = @k:text',
            {'k': '${GroupsModule.fanOutPerGroup.name}:$g'},
          ))!.time('updated_at');
          final before = await groupBudgetHit();

          final gate = Completer<void>();
          final release = Completer<void>();
          unawaited(
            h.env.platform.db.tx((tx) async {
              // Hold the sender's stored-budget bucket so the send stops at
              // its charge - the statement after the group's.
              final row = await tx.queryOne(
                'SELECT key FROM ${h.env.platform.schemas.platform}.rate_buckets '
                'WHERE key = @k:text FOR UPDATE',
                {'k': '${budget.name}:account:${alice.accountId}'},
              );
              if (row == null) return;
              if (!gate.isCompleted) gate.complete();
              await release.future;
            }),
          );
          await gate.future.timeout(const Duration(seconds: 5));

          final inFlight = groupSend(g, size: large, distribute: true);
          expect(
            await Future.any([
              inFlight.then((_) => false),
              Future.delayed(const Duration(milliseconds: 300), () => true),
            ]),
            isTrue,
            reason: 'the send is stopped at the sender\'s charge',
          );
          // The group's budget was drawn on while the sender had not been
          // charged yet, so a send the group refuses never costs the sender
          // anything to retry (AUD-4b-3).
          await eventually(() async {
            expect((await groupBudgetHit()).isAfter(before), isTrue);
          }, timeout: const Duration(seconds: 5));
          release.complete();
          expect((await inFlight).status, 200);
        },
      );

      test('a direct send draws on the same per-account budget', () async {
        // Read from the bucket: a refusal of a 16-unit send is too quick to
        // observe reliably (it refills in 64 ms).
        expect(
          (await send(h, alice, {
            bob.accountId: [bob.id],
          }, size: large)).status,
          200,
        );
        expect(
          await tokens(
            MessagingModule.storedPerAccount,
            'account:${alice.accountId}',
          ),
          MessagingModule.storedPerAccount.capacity - 16,
        );
      });

      test(
        'a group send is charged by what it stores, to the sender and the group',
        () async {
          final g = await create();
          expect((await groupSend(g, size: large)).status, 200);
          expect(
            await tokens(
              MessagingModule.storedPerAccount,
              'account:${alice.accountId}',
            ),
            MessagingModule.storedPerAccount.capacity - 32,
          );
          expect(
            await tokens(GroupsModule.fanOutPerGroup, g),
            GroupsModule.fanOutPerGroup.capacity - 32,
          );
          final other = await create();
          expect(
            await tokens(GroupsModule.fanOutPerGroup, other),
            isNull,
            reason: 'each group has its own budget',
          );
        },
      );

      test('a member device over its quota does not stop the group', () async {
        final g = await create();
        await h.env.platform.db.execute(
          'UPDATE ${table('messaging', 'device_seq')} SET pending = @n:int4 WHERE device_id = @d:uuid',
          {'d': carol.id, 'n': MailboxStore.quota},
        );
        expect((await groupSend(g)).status, 200);
        expect(await pending(carol.id), MailboxStore.quota);
        expect(
          (await mailbox(
            h,
            carol,
          )).envelopes.where((e) => e.kind == EnvelopeKind.groupMessage),
          hasLength(1),
          reason: 'the newest envelope is kept',
        );
      });
    });

    group('storage budget (A-03)', () {
      test(
        'over the budget, uploads, backups and large sends are refused',
        () async {
          h = await Harness.start(extra: {'HELIX_STORAGE_BUDGET_BYTES': '1'});
          final alice = await h.registerGlobal(aliceNumber);
          final bob = await h.registerGlobal(bobNumber);

          final upload = await h.api.call(
            Routes.createUpload,
            bearer: alice.bearer,
            body: const CreateUploadRequest(
              size: 1000,
              kind: MediaKind.attachment,
            ).toJson(),
          );
          expect(upload.status, 422);
          expect(upload.errorCode, 'quota_exceeded');
          expect(
            upload.json.object('error').object('details').string('reason'),
            'server_storage',
          );
          expect(
            (await h.api.call(
              Routes.putHistoryBackup,
              bearer: alice.bearer,
              body: HistoryBackup(version: 1, data: bytes(10)).toJson(),
            )).errorCode,
            'quota_exceeded',
          );
          expect(
            (await send(h, alice, {
              bob.accountId: [bob.id],
            }, size: storedUnitBytes + 1)).errorCode,
            'quota_exceeded',
          );
          expect(
            (await send(h, alice, {
              bob.accountId: [bob.id],
            })).status,
            200,
            reason: 'short messages still go through',
          );
        },
      );

      test(
        'without a budget nothing is refused; the gauge reports usage',
        () async {
          h = await Harness.start();
          final alice = await h.registerGlobal(aliceNumber);
          final bob = await h.registerGlobal(bobNumber);
          expect(
            (await send(h, alice, {
              bob.accountId: [bob.id],
            }, size: storedUnitBytes * 4)).status,
            200,
          );
          expect(await h.env.platform.storageBudget.used(), greaterThan(0));
        },
      );
    });

    group('inactive devices (A-01)', () {
      Future<void> lastSeen(String deviceId, int daysAgo) =>
          h.env.platform.db.execute(
            'UPDATE ${table('identity', 'devices')} '
            'SET last_seen_on = current_date - @n:int4 WHERE id = @d:uuid',
            {'d': deviceId, 'n': daysAgo},
          );

      Future<String> status(
        String deviceId,
      ) async => (await h.env.platform.db.queryOne(
        'SELECT status FROM ${table('identity', 'devices')} WHERE id = @d:uuid',
        {'d': deviceId},
      ))!.string('status');

      test('off by default', () async {
        h = await Harness.start();
        expect(
          h.identity.periodic.map((j) => j.name),
          isNot(contains('identity.revoke_inactive')),
        );
        final alice = await h.registerGlobal(aliceNumber);
        final old = await secondDevice(h, alice, aliceNumber);
        await lastSeen(old.id, 400);
        expect(await h.identity.inactiveDevices.revoke(), 0);
        expect(await status(old.id), 'active');
      });

      test(
        'revokes devices unused for longer, never an account\'s newest one',
        () async {
          h = await Harness.start(extra: {'HELIX_DEVICE_INACTIVE_DAYS': '30'});
          expect(
            h.identity.periodic.map((j) => j.name),
            contains('identity.revoke_inactive'),
          );
          final alice = await h.registerGlobal(aliceNumber);
          final aliceOld = await secondDevice(h, alice, aliceNumber);
          final bob = await h.registerGlobal(bobNumber);
          final bob2 = await secondDevice(h, bob, bobNumber);
          final carol = await h.registerGlobal(carolNumber);

          await lastSeen(alice.id, 0);
          await lastSeen(aliceOld.id, 31);
          // Bob uses neither device: the newer one stays.
          await lastSeen(bob.id, 90);
          await lastSeen(bob2.id, 60);
          // Carol's only device is never revoked.
          await lastSeen(carol.id, 200);

          expect(await h.identity.inactiveDevices.revoke(), 2);
          expect(await status(alice.id), 'active');
          expect(await status(aliceOld.id), 'revoked');
          expect(await status(bob.id), 'revoked');
          expect(await status(bob2.id), 'active');
          expect(await status(carol.id), 'active');

          // The account hears of it like any other revoke.
          final signals = [
            for (final e in (await mailbox(h, alice)).envelopes)
              if (e.kind == EnvelopeKind.accountSignal)
                AccountSignalEvent.fromJson(JsonReader(e.data!)),
          ];
          expect(
            signals.where(
              (s) =>
                  s.signal == AccountSignalKind.deviceRevoked &&
                  s.device == aliceOld.id,
            ),
            hasLength(1),
          );
          expect(await h.identity.inactiveDevices.revoke(), 0);
        },
      );
    });
  });
}
