import 'dart:io';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/identity/module.dart';
import 'package:helix_remote_server/src/modules/media/module.dart';
import 'package:helix_remote_server/src/modules/messaging/module.dart';
import 'package:helix_remote_server/src/modules/people/module.dart';
import 'package:helix_remote_server/src/platform/blobs/object_storage.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/flows.dart';
import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';

/// Local storage whose deletes can be made to fail, like a file an antivirus
/// scan holds open on Windows.
final class _LockableStorage implements ObjectStorage {
  _LockableStorage(this.inner);

  final LocalObjectStorage inner;
  final Set<String> locked = {};

  /// Runs after each successful delete; the sweep tests move a fake clock
  /// here so that "slow" is a time step, not a sleep.
  void Function()? onDelete;

  @override
  bool get supportsPresign => inner.supportsPresign;

  @override
  Future<int?> size(String key) => inner.size(key);

  @override
  Future<int> append(
    String key,
    Stream<List<int>> data, {
    required int offset,
    required int maxSize,
  }) => inner.append(key, data, offset: offset, maxSize: maxSize);

  @override
  Stream<List<int>> read(String key, {int start = 0, int? endInclusive}) =>
      inner.read(key, start: start, endInclusive: endInclusive);

  @override
  Future<void> delete(String key) async {
    if (locked.contains(key)) {
      throw FileSystemException('locked by another process', key);
    }
    await inner.delete(key);
    onDelete?.call();
  }

  @override
  Stream<StoredObject> list(String prefix) => inner.list(prefix);

  @override
  Uri presignPut(String key, Duration ttl, {required int contentLength}) =>
      inner.presignPut(key, ttl, contentLength: contentLength);

  @override
  Uri presignGet(String key, Duration ttl) => inner.presignGet(key, ttl);

  @override
  Future<bool> ping() => inner.ping();
}

/// What the documents say is deleted, is deleted (review 2026-10-09, batch
/// 7: A-10 media blobs before rows and the orphan sweep, C-02 report
/// retention).
void main() {
  group('retention', skip: databaseTestSkipReason, () {
    late Harness h;
    late Directory dir;
    late _LockableStorage blobs;
    late TestDevice alice;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('helix_retention_');
      blobs = _LockableStorage(LocalObjectStorage(dir.path));
      h = await Harness.start(blobs: blobs);
      alice = await h.registerGlobal(aliceNumber);
    });

    tearDown(() async {
      await h.stop();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    MediaModule media() => h.server.modules.whereType<MediaModule>().single;
    MessagingModule messaging() =>
        h.server.modules.whereType<MessagingModule>().single;
    String objects() => '${h.env.platform.schemas.of('media')}.objects';
    String usage() => '${h.env.platform.schemas.of('media')}.account_usage';

    Future<({int bytes, int objects})?> usageRow(
      String account, {
      String kind = 'attachment',
    }) async {
      final row = await h.env.platform.db.queryOne(
        'SELECT bytes, objects FROM ${usage()} '
        'WHERE account_id = @a:uuid AND kind = @k:text',
        {'a': account, 'k': kind},
      );
      return row == null
          ? null
          : (bytes: row.integer('bytes'), objects: row.integer('objects'));
    }

    Future<String> upload(
      List<int> bytes, {
      TestDevice? owner,
      MediaKind kind = MediaKind.attachment,
    }) async {
      final device = owner ?? alice;
      final r = await h.api.call(
        Routes.createUpload,
        bearer: device.bearer,
        body: CreateUploadRequest(size: bytes.length, kind: kind).toJson(),
      );
      final target = UploadTarget.fromJson(r.json);
      final put = await http.put(
        h.server.baseUri.resolve(target.url),
        headers: {
          'authorization': 'Bearer ${device.bearer}',
          'upload-offset': '0',
          'content-type': 'application/octet-stream',
        },
        body: bytes,
      );
      expect(put.statusCode, inInclusiveRange(200, 204));
      return target.mediaId;
    }

    Future<bool> rowExists(String id) async =>
        await h.env.platform.db.queryOne(
          'SELECT 1 FROM ${objects()} WHERE id = @id:uuid',
          {'id': id},
        ) !=
        null;

    Future<bool> blobExists(String id, {String kind = 'attachment'}) async =>
        await blobs.size('$kind/$id') != null;

    test('an expired blob that cannot be deleted keeps its row, and goes on '
        'the next run', () async {
      final kept = await upload([1, 2, 3]);
      final gone = await upload([4, 5, 6]);
      await h.env.platform.db.execute(
        "UPDATE ${objects()} SET expires_at = now() - interval '1 minute'",
      );
      blobs.locked.add('attachment/$kept');
      final expire = media().periodic.singleWhere(
        (j) => j.name == 'media.expire',
      );

      await expire.run();
      expect(await rowExists(kept), isTrue, reason: 'retried next run');
      expect(await blobExists(kept), isTrue);
      expect(await rowExists(gone), isFalse);
      expect(await blobExists(gone), isFalse);

      blobs.locked.clear();
      await expire.run();
      expect(await rowExists(kept), isFalse);
      expect(await blobExists(kept), isFalse);
    });

    test('purging a deleted account deletes each blob before its row, and '
        'retries what is left', () async {
      final kept = await upload([1, 2, 3]);
      final gone = await upload([4, 5, 6]);
      blobs.locked.add('attachment/$kept');
      final purge = media().jobs[MediaModule.purgeJob]!;

      await expectLater(
        purge({'account': alice.accountId}),
        throwsA(isA<StateError>()),
        reason: 'the job is retried',
      );
      expect(await rowExists(kept), isTrue);
      expect(await rowExists(gone), isFalse);
      expect(await blobExists(gone), isFalse);

      blobs.locked.clear();
      await purge({'account': alice.accountId});
      expect(await rowExists(kept), isFalse);
      expect(await blobExists(kept), isFalse);
    });

    test('an expire sweep stops at its budget, and the next run continues '
        'where it left off', () async {
      final ids = [
        for (var i = 0; i < 4; i++) await upload([i]),
      ];
      await h.env.platform.db.execute(
        "UPDATE ${objects()} SET expires_at = now() - interval '1 minute'",
      );
      var now = DateTime.utc(2026, 10, 25, 12);
      final sweep = media();
      sweep.sweepClock = () => now;
      sweep.expireBudget = const Duration(minutes: 1);
      // Each blob delete costs two minutes of the one-minute budget.
      blobs.onDelete = () => now = now.add(const Duration(minutes: 2));

      await sweep.expire();
      expect(await rowExists(ids.first), isFalse);
      expect(await rowExists(ids[1]), isTrue, reason: 'the budget stopped it');
      expect(await usageRow(alice.accountId), (bytes: 3, objects: 3));

      blobs.onDelete = null;
      await sweep.expire();
      for (final id in ids) {
        expect(await rowExists(id), isFalse);
        expect(await blobExists(id), isFalse);
      }
      expect(await usageRow(alice.accountId), (bytes: 0, objects: 0));
    });

    test('a purge stops at its budget with what it deleted kept, and the '
        'retry finishes the rest', () async {
      final ids = [
        for (var i = 0; i < 4; i++) await upload([i]),
      ];
      var now = DateTime.utc(2026, 10, 25, 12);
      final module = media();
      module.sweepClock = () => now;
      module.purgeBudget = const Duration(minutes: 1);
      blobs.onDelete = () => now = now.add(const Duration(minutes: 2));
      final purge = module.jobs[MediaModule.purgeJob]!;

      await expectLater(
        purge({'account': alice.accountId}),
        throwsA(isA<StateError>()),
        reason: 'the job retries the rest',
      );
      expect(await rowExists(ids.first), isFalse);
      expect(await rowExists(ids.last), isTrue);
      expect(
        await usageRow(alice.accountId),
        (bytes: 3, objects: 3),
        reason: 'the usage row stays for the rows that remain',
      );

      blobs.onDelete = null;
      await purge({'account': alice.accountId});
      expect(await rowExists(ids.last), isFalse);
      expect(await blobExists(ids.last), isFalse);
      expect(await usageRow(alice.accountId), isNull);
    });

    test('the weekly reconcile deletes the media of an account whose purge '
        'job died', () async {
      await h.env.platform.jobs.stop();
      await h.env.platform.periodic.stop();
      final bob = await h.registerGlobal(bobNumber);
      final gone = await upload([1, 2, 3], kind: MediaKind.persistent);
      final kept = await upload([4, 5], owner: bob, kind: MediaKind.persistent);
      await h.env.platform.db.tx(
        (tx) => h.identity.api.deleteAccount(tx, alice.accountId),
      );
      await h.env.platform.db.execute(
        'UPDATE ${h.env.platform.schemas.platform}.jobs '
        "SET status = 'dead' WHERE kind = @k:text",
        {'k': MediaModule.purgeJob},
      );
      expect(await rowExists(gone), isTrue, reason: 'the purge job never ran');
      expect(await usageRow(alice.accountId, kind: 'persistent'), isNotNull);

      final result = await media().reconcile();

      expect(result.deleted, 1);
      expect(await rowExists(gone), isFalse);
      expect(await blobExists(gone, kind: 'persistent'), isFalse);
      expect(await usageRow(alice.accountId, kind: 'persistent'), isNull);
      expect(
        await rowExists(kept),
        isTrue,
        reason: 'a live account is not touched',
      );
      expect(await blobExists(kept, kind: 'persistent'), isTrue);
      expect(result.drift, 0);
    });

    test(
      'the reconcile reports quota drift instead of correcting it',
      () async {
        final id = await upload([1, 2, 3]);
        await h.env.platform.db.execute(
          'UPDATE ${usage()} SET bytes = bytes + 10 WHERE account_id = @a:uuid',
          {'a': alice.accountId},
        );

        final result = await media().reconcile();

        expect(result.drift, 1);
        expect(await rowExists(id), isTrue);
        expect(
          (await usageRow(alice.accountId))!.bytes,
          13,
          reason: 'reported, not silently overwritten',
        );
      },
    );

    test('the weekly sweep deletes blobs with no row once they are a day '
        'old', () async {
      final live = await upload([1, 2, 3]);
      final orphan = Uuid.v7();
      final fresh = Uuid.v7();
      for (final key in [
        'attachment/$orphan',
        'attachment/$fresh',
        'attachment/not-a-media-id',
      ]) {
        await blobs.append(key, Stream.value([9]), offset: 0, maxSize: 10);
      }
      final old = DateTime.now().subtract(const Duration(days: 2));
      for (final name in [orphan, live, 'not-a-media-id']) {
        File('${dir.path}/attachment/$name').setLastModifiedSync(old);
      }
      final job = media().periodic.singleWhere(
        (j) => j.name == 'media.sweep_orphans',
      );
      expect(job.interval, const Duration(days: 7));

      expect(await media().sweepOrphans(), 1);
      expect(await blobs.size('attachment/$orphan'), isNull);
      expect(await blobExists(live), isTrue, reason: 'it has a row');
      expect(
        await blobs.size('attachment/$fresh'),
        isNotNull,
        reason: 'younger than a day: its row may be on its way',
      );
      expect(
        await blobs.size('attachment/not-a-media-id'),
        isNotNull,
        reason: 'not a media object',
      );
    });

    test('closed reports go 180 days after they were closed; open ones '
        'stay', () async {
      final bob = await h.registerGlobal(bobNumber);
      Future<String> report() async => ReportResponse.fromJson(
        (await h.api.call(
          Routes.report,
          bearer: alice.bearer,
          body: ReportRequest(
            account: bob.accountId,
            category: ReportCategory.spam,
            note: 'sends links',
          ).toJson(),
        )).json,
      ).reportId;
      final open = await report();
      final closedLongAgo = await report();
      final closedRecently = await report();
      final people = h.server.modules.whereType<PeopleModule>().single;
      final db = h.env.platform.db;
      for (final id in [closedLongAgo, closedRecently]) {
        expect(
          await people.api.resolveReport(db, id, ReportStatus.resolved),
          isTrue,
        );
      }
      final reports = '${h.env.platform.schemas.of('people')}.reports';
      await db.execute(
        "UPDATE $reports SET resolved_at = now() - interval '181 days' "
        'WHERE id = @id:uuid',
        {'id': closedLongAgo},
      );
      // An open report older than the retention is the operator's to handle.
      await db.execute(
        "UPDATE $reports SET created_at = now() - interval '400 days' "
        'WHERE id = @id:uuid',
        {'id': open},
      );

      await people.periodic
          .singleWhere((j) => j.name == 'people.purge_reports')
          .run();
      final left = {
        for (final r in await db.query('SELECT id FROM $reports'))
          r.string('id'),
      };
      expect(left, {open, closedRecently});
      expect(PeopleModule.reportRetention, const Duration(days: 180));
    });

    test('past discovery budget days go, today and yesterday stay', () async {
      // One row per account per UTC day, and nothing used to delete a past day
      // except the account itself (AUD-4a-4).
      final db = h.env.platform.db;
      final budget = '${h.env.platform.schemas.of('people')}.discovery_budget';
      for (final ago in [0, 1, 2, 30]) {
        await db.execute(
          'INSERT INTO $budget (account_id, day, used) VALUES (@a:uuid, '
          "(now() at time zone 'utc')::date - @d:int4, 1)",
          {'a': alice.accountId, 'd': ago},
        );
      }
      final people = h.server.modules.whereType<PeopleModule>().single;
      expect(
        people.periodic.map((j) => j.name),
        contains('people.purge_discovery'),
      );

      await people.periodic
          .singleWhere((j) => j.name == 'people.purge_discovery')
          .run();

      final left = await db.query(
        "SELECT day, day >= (now() at time zone 'utc')::date - @keep:int4 "
        'AS kept FROM $budget WHERE account_id = @a:uuid',
        {'a': alice.accountId, 'keep': PeopleModule.discoveryHistory.inDays},
      );
      expect(
        [for (final r in left) r.boolean('kept')],
        [true, true],
        reason: 'today and the day before are what the sweep keeps',
      );
    });

    test(
      'a dead invite or spent recovery code goes without the purge button',
      () async {
        // These two deletes lived only in the operator's purge, so on a public
        // server every self-issued invite (7-day life, minted 3 an hour per
        // address) and every recovery code that was never used stayed for
        // ever. The windows are the operator's own: 30 days past an
        // unredeemed invite's expiry, 1 day past a code's expiry or its use.
        const day = 86400;
        final db = h.env.platform.db;
        final identity = h.env.platform.schemas.of('identity');
        Future<void> invite(String id, int expiresFromNow) => db.execute(
          'INSERT INTO $identity.invites (id, code_hash, issuer, expires_at) '
          "VALUES (@id:uuid, decode(md5(@c:text), 'hex'), 'self', "
          'now() + make_interval(secs => @e:int8))',
          {'id': id, 'c': 'invite-$id', 'e': expiresFromNow},
        );
        Future<void> redeemedInvite(String id, String by) => db.execute(
          'INSERT INTO $identity.invites (id, code_hash, issuer, expires_at, '
          "redeemed_at, redeemed_by) VALUES (@id:uuid, "
          "decode(md5(@c:text), 'hex'), 'self', "
          'now() - make_interval(secs => @e:int8), now(), @r:uuid)',
          {'id': id, 'c': 'invite-$id', 'e': 40 * day, 'r': by},
        );
        Future<void> code(
          String id, {
          required int expiresFromNow,
          required int usedSecondsAgo,
        }) => db.execute(
          'INSERT INTO $identity.recovery_codes (id, account_id, code_hash, '
          "expires_at, used_at) VALUES (@id:uuid, @a:uuid, "
          "decode(md5(@c:text), 'hex'), "
          'now() + make_interval(secs => @e:int8), '
          'now() - make_interval(secs => @u:int8))',
          {
            'id': id,
            'a': alice.accountId,
            'c': 'code-$id',
            'e': expiresFromNow,
            'u': usedSecondsAgo,
          },
        );
        final deadInvite = Uuid.v7();
        final openInvite = Uuid.v7();
        final takenInvite = Uuid.v7();
        final spentCode = Uuid.v7();
        final freshCode = Uuid.v7();
        await invite(deadInvite, -40 * day);
        await invite(openInvite, day);
        await redeemedInvite(takenInvite, Uuid.v7());
        await code(spentCode, expiresFromNow: day, usedSecondsAgo: 2 * day);
        await code(freshCode, expiresFromNow: day, usedSecondsAgo: 60);

        final module = h.server.modules.whereType<IdentityModule>().single;
        await module.periodic
            .singleWhere((j) => j.name == 'identity.purge_expired')
            .run();

        Future<Set<String>> left(String table, List<String> ids) async {
          final marks = [
            for (var i = 0; i < ids.length; i++) '@i$i:uuid',
          ].join(', ');
          final rows = await db.query(
            'SELECT id FROM $identity.$table WHERE id IN ($marks)',
            {for (var i = 0; i < ids.length; i++) 'i$i': ids[i]},
          );
          return {for (final r in rows) r.string('id')};
        }

        expect(
          await left('invites', [deadInvite, openInvite, takenInvite]),
          {openInvite, takenInvite},
          reason:
              'an invite nobody redeemed is gone 30 days past its expiry, '
              'while a redeemed one is the record of who joined and stays',
        );
        expect(
          await left('recovery_codes', [spentCode, freshCode]),
          {freshCode},
          reason: 'the code used two days ago is dead weight',
        );
      },
    );

    test('an expiry batch deletes exactly the rows it picked', () async {
      // The batch used to pick rows by `ctid`, which is unique only inside one
      // of the mailbox's sixteen partitions: `ctid IN (...)` matched the same
      // block and offset in *every* partition, so sweeping one device's expired
      // mail also deleted live, undelivered envelopes of other devices - and an
      // undelivered envelope is the only copy of that message.
      final db = h.env.platform.db;
      final box = h.env.platform.schemas.of('messaging');
      final doomed = Uuid.v7();
      final neighbours = [for (var i = 0; i < 24; i++) Uuid.v7()];
      for (final d in [doomed, ...neighbours]) {
        await db.execute(
          'INSERT INTO $box.mailbox (device_id, seq, id, kind, urgent, expires_at) '
          "SELECT @d:uuid, g, gen_random_uuid(), 'message', false, "
          "now() + interval '1 day' FROM generate_series(1, 4) g",
          {'d': d},
        );
        await db.execute(
          'INSERT INTO $box.device_seq (device_id, last_seq, pending) '
          'VALUES (@d:uuid, 4, 4)',
          {'d': d},
        );
      }
      await db.execute(
        "UPDATE $box.mailbox SET expires_at = now() - interval '1 minute' "
        'WHERE device_id = @d:uuid',
        {'d': doomed},
      );
      await h.env.platform.jobs.stop();

      await messaging().jobs[MessagingModule.expireBatchJob]!(const {});

      final stored = {
        for (final r in await db.query(
          'SELECT device_id, count(*)::int AS n FROM $box.mailbox '
          'GROUP BY device_id',
        ))
          r.string('device_id'): r.integer('n'),
      };
      expect(stored.containsKey(doomed), isFalse);
      expect(
        stored,
        {for (final d in neighbours) d: 4},
        reason:
            'a neighbour whose row shares a ctid with a deleted one keeps it',
      );
      // The other half of the same statement: `pending` is what is stored, so
      // a later send cannot `trim` mail that is not there (AUD-3-2).
      final drift = await db.query(
        'SELECT d.device_id FROM $box.device_seq d '
        'LEFT JOIN (SELECT device_id, count(*)::int AS n FROM $box.mailbox '
        'GROUP BY device_id) m USING (device_id) '
        'WHERE d.pending <> coalesce(m.n, 0)',
      );
      expect(drift, isEmpty);
    });

    test('a backlog drains in bounded batches that queue the rest', () async {
      // `messaging.expire` used to delete 5,000-row batches in a tight loop
      // until nothing was expired: after an outage that loop ran for minutes on
      // the request pool and could outlive its own lease (AUD-3-5). One run is
      // now one batch, and the next batch is a queued job - so the work is
      // spread over seconds, coalesced to one waiting batch, and retried with
      // the backoff every other job has.
      final db = h.env.platform.db;
      final box = h.env.platform.schemas.of('messaging');
      final jobs = '${h.env.platform.schemas.platform}.jobs';
      final device = Uuid.v7();
      final backlog = MessagingModule.expireBatch + 3;
      await db.execute(
        'INSERT INTO $box.mailbox (device_id, seq, id, kind, urgent, expires_at) '
        "SELECT @d:uuid, g, gen_random_uuid(), 'message', false, "
        "now() - interval '1 minute' FROM generate_series(1, @n:int4) g",
        {'d': device, 'n': backlog},
      );
      await db.execute(
        'INSERT INTO $box.device_seq (device_id, last_seq, pending) '
        'VALUES (@d:uuid, @n:int8, @n:int8)',
        {'d': device, 'n': backlog},
      );
      await h.env.platform.jobs.stop();
      // The node's own loops would both run a queued batch and kick another
      // while the test is measuring.
      await h.env.platform.periodic.stop();
      final expire = messaging().jobs[MessagingModule.expireBatchJob]!;
      Future<int> stored() async => (await db.queryOne(
        'SELECT count(*)::int AS n FROM $box.mailbox WHERE device_id = @d:uuid',
        {'d': device},
      ))!.integer('n');
      Future<int> pending() async => (await db.queryOne(
        'SELECT pending FROM $box.device_seq WHERE device_id = @d:uuid',
        {'d': device},
      ))!.integer('pending');
      Future<int> queued() async => (await db.queryOne(
        "SELECT count(*)::int AS n FROM $jobs WHERE kind = @k:text "
        "AND status = 'pending'",
        {'k': MessagingModule.expireBatchJob},
      ))!.integer('n');

      await expire(const {});
      expect(await stored(), 3, reason: 'a run stops at the batch');
      expect(await pending(), 3);
      expect(await queued(), 1, reason: 'what is left is queued, not looped');

      await expire(const {});
      expect(await stored(), 0);
      expect(await pending(), 0);

      // A run that found less than a batch does not ask for another, and the
      // periodic kick coalesces however often it fires.
      await db.execute("DELETE FROM $jobs WHERE kind = @k:text", {
        'k': MessagingModule.expireBatchJob,
      });
      await expire(const {});
      expect(await queued(), 0);
      final sweep = messaging().periodic.singleWhere(
        (j) => j.name == 'messaging.expire',
      );
      await sweep.run();
      await sweep.run();
      expect(await queued(), 1);
    });
  });
}
