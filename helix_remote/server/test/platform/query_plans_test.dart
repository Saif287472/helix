import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/helix_remote_server.dart';
import 'package:helix_remote_server/src/modules/identity/data/identity_store.dart';
import 'package:helix_remote_server/src/modules/messaging/data/mailbox_store.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/platform_migrations.dart';
import 'package:test/test.dart';

import '../support/harness.dart';
import '../support/query_plans.dart';
import '../support/test_database.dart';
import '../support/test_platform.dart';

/// The plan-of-record rule (ARCHITECTURE_V2_PLAN.md §4.3): "every query in a
/// repository has an index, verified by an `EXPLAIN` test for the hot paths
/// (send, fetch mailbox, ack, auth lookup)". This is that test (AUD-1b-3).
///
/// Each path runs through the real store code on a schema migrated exactly as
/// a node migrates at start and seeded to the sizes production has, and every
/// statement it executed must reach its rows through an index. The seed sizes
/// are part of the test: on a small or empty table Postgres is right to read
/// the whole table, so a guard written against nothing would pass forever. The
/// last case proves the guard bites, by dropping an index and re-planning the
/// same query.
///
/// The platform ephemeral store's prefix scan is deliberately not here: it is
/// a known sequential scan (AUD-1b-4) whose fix is a migration, in B4.
void main() {
  group(
    'hot-path query plans (AUD-1b-3)',
    skip: databaseTestSkipReason,
    // Seeding 20,000 accounts and devices and 100,000 mailbox and send rows,
    // through every module's migrations, is the slow part - not the plans.
    timeout: const Timeout(Duration(minutes: 5)),
    () {
      const accountCount = 20000;
      const mailDeviceCount = 100;
      const mailPerDevice = 500;
      const sendPerDevice = 500;

      // One seeded schema for the whole group.
      late TestPlatform env;
      late Db db;
      late String idn;
      late String msg;
      late List<String> mailDevices;
      late String target;
      late String targetAccount;
      late String existingSend;
      late Uint8List targetPhoneHash;

      setUpAll(() async {
        env = await TestPlatform.open(
          extra: {'HELIX_PHONE_PEPPER': testPepper},
        );
        db = env.platform.db;
        idn = env.platform.schemas.of('identity');
        msg = env.platform.schemas.of('messaging');

        // The same migration sets every node applies at start, so the plans
        // are of the production schema, not of a sketch of it.
        final modules = [
          for (final create in allModules())
            create(env.platform.moduleContext()),
        ];
        await MigrationRunner(db, env.platform.schemas).run([
          platformMigrations,
          for (final m in modules)
            MigrationSet(module: m.name, migrations: m.migrations),
        ]);

        await db.execute(
          'INSERT INTO $idn.accounts (id, identity_key, phone_hash) '
          'SELECT gen_random_uuid(), decode(repeat(\'11\', 32), \'hex\'), '
          'decode(md5(g::text) || md5((g + 1000000)::text), \'hex\') '
          'FROM generate_series(1, @n:int4) g',
          {'n': accountCount},
        );
        await db.execute(
          'INSERT INTO $idn.devices (id, account_id, name, platform, '
          'identity_key, signing_key, certificate, certificate_created_at) '
          'SELECT gen_random_uuid(), a.id, \'phone\', \'android\', '
          'decode(repeat(\'22\', 32), \'hex\'), decode(repeat(\'33\', 32), \'hex\'), '
          'decode(repeat(\'44\', 64), \'hex\'), now() FROM $idn.accounts a',
        );
        await db.execute(
          'INSERT INTO $idn.passwords (account_id, kdf, salt, verifier_salt, '
          'verifier, wrapped_identity_key) SELECT id, \'{}\'::jsonb, '
          'decode(repeat(\'55\', 16), \'hex\'), decode(repeat(\'66\', 16), \'hex\'), '
          'decode(repeat(\'77\', 32), \'hex\'), \'{}\'::jsonb FROM $idn.accounts',
        );
        // The mail the devices hold: 100 devices x 500 envelopes, spread over
        // the 16 hash partitions the way a real fleet spreads it.
        await db.execute(
          'INSERT INTO $msg.mailbox (device_id, seq, id, kind, sender_account, '
          'sender_device, payload, urgent, expires_at) '
          'SELECT d.id, s, gen_random_uuid(), \'message\', d.account_id, d.id, '
          'decode(repeat(\'88\', 32), \'hex\'), false, now() + interval \'1 day\' '
          'FROM (SELECT id, account_id FROM $idn.devices ORDER BY id LIMIT @m:int4) d '
          'CROSS JOIN generate_series(1, @per:int4) s',
          {'m': mailDeviceCount, 'per': mailPerDevice},
        );
        // A sequence row for every device, as production has one for every
        // device that ever got mail. Seeding only the 100 that hold mail would
        // leave the table small enough that reading all of it is the right
        // plan, and the guard below would be proving nothing.
        await db.execute(
          'INSERT INTO $msg.device_seq (device_id, last_seq, pending) '
          'SELECT id, 0, 0 FROM $idn.devices',
        );
        await db.execute(
          'UPDATE $msg.device_seq SET last_seq = @per:int4, pending = @per:int4 '
          'WHERE device_id IN ('
          'SELECT id FROM $idn.devices ORDER BY id LIMIT @m:int4)',
          {'per': mailPerDevice, 'm': mailDeviceCount},
        );
        await db.execute(
          'INSERT INTO $msg.sends (sender_account, sender_device, id, accepted_at) '
          'SELECT d.account_id::text, d.id, gen_random_uuid(), now() '
          'FROM (SELECT id, account_id FROM $idn.devices ORDER BY id LIMIT @m:int4) d '
          'CROSS JOIN generate_series(1, @per:int4) s',
          {'m': mailDeviceCount, 'per': sendPerDevice},
        );

        for (final table in [
          '$idn.accounts',
          '$idn.devices',
          '$idn.passwords',
          '$msg.mailbox',
          '$msg.device_seq',
          '$msg.sends',
        ]) {
          await db.execute('ANALYZE $table');
        }

        mailDevices = [
          for (final r in await db.query(
            'SELECT id FROM $idn.devices ORDER BY id LIMIT @m:int4',
            {'m': mailDeviceCount},
          ))
            r.string('id'),
        ];
        target = mailDevices.first;
        targetAccount = (await db.queryOne(
          'SELECT account_id::text AS a FROM $idn.devices WHERE id = @d:uuid',
          {'d': target},
        ))!.string('a');
        existingSend = (await db.queryOne(
          'SELECT id FROM $msg.sends WHERE sender_account = @a:text '
          'AND sender_device = @d:uuid LIMIT 1',
          {'a': targetAccount, 'd': target},
        ))!.string('id');
        targetPhoneHash = (await db.queryOne(
          'SELECT a.phone_hash FROM $idn.accounts a '
          'JOIN $idn.devices d ON d.account_id = a.id WHERE d.id = @d:uuid',
          {'d': target},
        ))!.bytes('phone_hash');
      });

      tearDownAll(() async => env.dispose());

      test('signing in finds the account by its phone hash', () async {
        final log = <Statement>[];
        final found = await IdentityStore(
          idn,
        ).accountByPhone(Recording(db, log), targetPhoneHash);
        expect(found?.id, targetAccount);
        expect(found!.hasPassword, isTrue);
        await expectIndexed(db, log);
      });

      test(
        'every authenticated request checks the device and its account',
        () async {
          final log = <Statement>[];
          final state = await IdentityStore(
            idn,
          ).authState(Recording(db, log), target);
          expect(state?.active, isTrue);
          await expectIndexed(db, log);
        },
      );

      test(
        'a send checks the replay key, the devices, the sequence and the rows',
        () async {
          final log = <Statement>[];
          final newSendId = (await db.queryOne(
            'SELECT gen_random_uuid() AS id',
          ))!.string('id');
          final store = MailboxStore(msg);
          final identity = IdentityStore(idn);
          final fanOut = mailDevices.take(5).toList();
          await db.tx((tx) async {
            final rec = Recording(tx, log);
            expect(
              await identity.lockActiveDevices(rec, fanOut),
              hasLength(fanOut.length),
            );
            expect(
              await store.recordSend(
                rec,
                newSendId,
                senderAccount: targetAccount,
                senderDevice: target,
              ),
              isNotNull,
            );
            expect(
              await store.acceptedAt(
                rec,
                existingSend,
                senderAccount: targetAccount,
                senderDevice: target,
              ),
              isNotNull,
            );
            final allocated = await store.allocate(rec, fanOut);
            expect(allocated.seqs, hasLength(fanOut.length));
            await store.insert(
              rec,
              seqs: allocated.seqs,
              payloads: {
                for (final d in fanOut) d: Uint8List.fromList([1, 2, 3, 4]),
              },
              id: newSendId,
              kind: EnvelopeKind.message,
              from: EnvelopeSender(account: targetAccount, device: target),
              urgent: false,
            );
          });
          await expectIndexed(db, log);
        },
      );

      test('a device fetches its mail in sequence order', () async {
        final log = <Statement>[];
        final store = MailboxStore(msg);
        final rec = Recording(db, log);
        expect(
          await store.fetch(rec, target, after: 100, limit: 50),
          hasLength(50),
        );
        expect(await store.lastSeq(rec, target), greaterThan(0));
        expect(await store.head(rec, target), greaterThan(0));
        await expectIndexed(db, log);
      });

      test(
        'an ack deletes up to the sequence and settles the pending count',
        () async {
          final log = <Statement>[];
          final deleted = await db.tx(
            (tx) => MailboxStore(msg).ack(Recording(tx, log), target, 150),
          );
          expect(deleted, greaterThan(0));
          await expectIndexed(db, log);
        },
      );

      test(
        'the guard bites: the same query is sequential without its index',
        () async {
          final log = <Statement>[];
          await IdentityStore(
            idn,
          ).accountByPhone(Recording(db, log), targetPhoneHash);
          final statement = log.single;
          await db.execute(
            'ALTER TABLE $idn.accounts DROP CONSTRAINT accounts_phone_hash_key',
          );
          try {
            final problems = await planProblems(db, [statement]);
            expect(
              problems.join('\n'),
              contains('Seq Scan on accounts'),
              reason:
                  '20,000 accounts read by an unindexed column: if this does '
                  'not report a sequential scan, the checks above prove nothing',
            );
          } finally {
            await db.execute(
              'ALTER TABLE $idn.accounts '
              'ADD CONSTRAINT accounts_phone_hash_key UNIQUE (phone_hash)',
            );
          }
        },
      );
    },
  );
}
