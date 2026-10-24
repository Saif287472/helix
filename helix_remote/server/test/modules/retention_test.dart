import 'dart:io';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
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

    Future<String> upload(List<int> bytes) async {
      final r = await h.api.call(
        Routes.createUpload,
        bearer: alice.bearer,
        body: CreateUploadRequest(size: bytes.length).toJson(),
      );
      final target = UploadTarget.fromJson(r.json);
      final put = await http.put(
        h.server.baseUri.resolve(target.url),
        headers: {
          'authorization': 'Bearer ${alice.bearer}',
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

    Future<bool> blobExists(String id) async =>
        await blobs.size('attachment/$id') != null;

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
