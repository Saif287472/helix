import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/flows.dart';
import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';

void main() {
  group('media', skip: databaseTestSkipReason, () {
    late Harness h;
    late TestDevice alice;
    late TestDevice bob;

    setUp(() async {
      h = await Harness.start();
      alice = await h.registerGlobal(aliceNumber);
      bob = await h.registerGlobal(bobNumber);
    });

    tearDown(() async => h.stop());

    Future<UploadTarget> create(
      int size, {
      MediaKind kind = MediaKind.attachment,
    }) async {
      final r = await h.api.call(
        Routes.createUpload,
        bearer: alice.bearer,
        body: CreateUploadRequest(size: size, kind: kind).toJson(),
      );
      expect(r.status, 201, reason: r.body);
      return UploadTarget.fromJson(r.json);
    }

    Future<http.Response> put(
      UploadTarget t,
      List<int> data, {
      int offset = 0,
      String? bearer,
    }) => http.put(
      h.server.baseUri.resolve(t.url),
      headers: {
        'authorization': 'Bearer ${bearer ?? alice.bearer}',
        'upload-offset': '$offset',
        'content-type': 'application/octet-stream',
      },
      body: data,
    );

    test(
      'resumable upload, status, ranged download by anyone signed in',
      () async {
        final data = bytes(1000, 3);
        final target = await create(data.length);
        expect(Uuid.isValid(target.mediaId), isTrue);
        expect(target.resumable, isTrue);

        final first = await put(target, data.sublist(0, 400));
        expect(first.statusCode, 204);
        expect(first.headers['upload-offset'], '400');
        final status = await h.api.call(
          Routes.uploadStatus,
          params: {'media_id': target.mediaId},
          bearer: alice.bearer,
        );
        expect(status.headers['upload-offset'], '400');
        expect(status.headers['upload-length'], '1000');

        final wrongOffset = await put(target, data.sublist(400), offset: 100);
        expect(wrongOffset.statusCode, 409);

        final notOwner = await put(
          target,
          data.sublist(400),
          offset: 400,
          bearer: bob.bearer,
        );
        expect(notOwner.statusCode, 404);

        final early = await h.api.call(
          Routes.downloadContent,
          params: {'media_id': target.mediaId},
          bearer: bob.bearer,
        );
        expect(early.status, 404, reason: 'not finished');

        expect(
          (await put(
            target,
            data.sublist(400),
            offset: 400,
          )).headers['upload-offset'],
          '1000',
        );

        final full = await http.get(
          h.server.baseUri.resolve(
            Routes.downloadContent.expand({'media_id': target.mediaId}),
          ),
          headers: {'authorization': 'Bearer ${bob.bearer}'},
        );
        expect(full.statusCode, 200);
        expect(full.bodyBytes, data);

        final part = await http.get(
          h.server.baseUri.resolve(
            Routes.downloadContent.expand({'media_id': target.mediaId}),
          ),
          headers: {
            'authorization': 'Bearer ${bob.bearer}',
            'range': 'bytes=10-19',
          },
        );
        expect(part.statusCode, 206);
        expect(part.headers['content-range'], 'bytes 10-19/1000');
        expect(part.bodyBytes, data.sublist(10, 20));

        final tail = await http.get(
          h.server.baseUri.resolve(
            Routes.downloadContent.expand({'media_id': target.mediaId}),
          ),
          headers: {
            'authorization': 'Bearer ${bob.bearer}',
            'range': 'bytes=-5',
          },
        );
        expect(tail.bodyBytes, data.sublist(995));

        final bad = await http.get(
          h.server.baseUri.resolve(
            Routes.downloadContent.expand({'media_id': target.mediaId}),
          ),
          headers: {
            'authorization': 'Bearer ${bob.bearer}',
            'range': 'bytes=5000-',
          },
        );
        expect(bad.statusCode, 416);
      },
    );

    test(
      'uploads are capped at the declared size and per-kind limits',
      () async {
        final target = await create(10);
        expect((await put(target, bytes(11))).statusCode, 413);
        final tooBig = await h.api.call(
          Routes.createUpload,
          bearer: alice.bearer,
          body: const CreateUploadRequest(
            size: 6 * 1024 * 1024,
            kind: MediaKind.persistent,
          ).toJson(),
        );
        expect(tooBig.status, 413);
      },
    );

    test('owners delete; expired objects disappear', () async {
      final target = await create(4);
      await put(target, [1, 2, 3, 4]);
      expect(
        (await h.api.call(
          Routes.deleteMedia,
          params: {'media_id': target.mediaId},
          bearer: bob.bearer,
        )).status,
        404,
      );
      expect(
        (await h.api.call(
          Routes.deleteMedia,
          params: {'media_id': target.mediaId},
          bearer: alice.bearer,
        )).status,
        204,
      );
      expect(
        (await h.api.call(
          Routes.downloadContent,
          params: {'media_id': target.mediaId},
          bearer: bob.bearer,
        )).status,
        404,
      );

      final aged = await create(2);
      await put(aged, [1, 2]);
      await h.env.platform.db.execute(
        "UPDATE ${h.env.platform.schemas.of('media')}.objects SET expires_at = now() - interval '1 minute' "
        'WHERE id = @id:uuid',
        {'id': aged.mediaId},
      );
      expect(
        (await h.api.call(
          Routes.downloadContent,
          params: {'media_id': aged.mediaId},
          bearer: bob.bearer,
        )).status,
        404,
        reason: 'expired objects are not served even before the sweep',
      );
    });
  });

  group('backup', skip: databaseTestSkipReason, () {
    late Harness h;
    late TestDevice alice;

    setUp(() async {
      h = await Harness.start();
      alice = await h.registerGlobal(aliceNumber);
    });

    tearDown(() async => h.stop());

    test('history backup: only newer versions replace it', () async {
      Future<TestResponse> put(int version, int seed) => h.api.call(
        Routes.putHistoryBackup,
        bearer: alice.bearer,
        body: HistoryBackup(version: version, data: bytes(300, seed)).toJson(),
      );
      expect((await put(1, 1)).status, 204);
      expect((await put(2, 2)).status, 204);
      expect((await put(2, 3)).errorCode, 'version_conflict');
      final stored = HistoryBackup.fromJson(
        (await h.api.call(Routes.getHistoryBackup, bearer: alice.bearer)).json,
      );
      expect(stored.version, 2);
      expect(stored.data, bytes(300, 2));
      expect(
        (await h.api.call(
          Routes.deleteHistoryBackup,
          bearer: alice.bearer,
        )).status,
        204,
      );
      expect(
        (await h.api.call(
          Routes.getHistoryBackup,
          bearer: alice.bearer,
        )).status,
        404,
      );
    });

    test('a changed identity key deletes the history backup', () async {
      await h.api.call(
        Routes.putHistoryBackup,
        bearer: alice.bearer,
        body: HistoryBackup(version: 1, data: bytes(10)).toJson(),
      );
      final code = await h.env.platform.db.tx(
        (tx) => h.identity.registration.issueRecoveryCode(tx, alice.accountId),
      );
      final verified = await h.verifyPhone(
        aliceNumber,
        purpose: PhonePurpose.recover,
      );
      final rotated = await alice.account.rotated();
      final device = await rotated.newDevice();
      final redeemed = await h.api.call(
        Routes.recoveryRedeem,
        body: RecoveryRedeemRequest(
          recoveryCode: code.code,
          identityKey: rotated.publicKey,
          device: await device.registration(),
          prekeys: await device.prekeys(),
          verificationToken: verified.verificationToken,
        ).toJson(),
      );
      device.session = Session.fromJson(redeemed.json);
      expect(
        (await h.api.call(
          Routes.getHistoryBackup,
          bearer: device.bearer,
        )).status,
        404,
      );
    });

    test(
      'full backups refuse secrets at any depth and refresh their media',
      () async {
        final media = UploadTarget.fromJson(
          (await h.api.call(
            Routes.createUpload,
            bearer: alice.bearer,
            body: const CreateUploadRequest(
              size: 3,
              kind: MediaKind.backup,
            ).toJson(),
          )).json,
        );
        final leaky = await h.api.call(
          Routes.putFullBackup,
          bearer: alice.bearer,
          body: FullBackup(
            backupId: Uuid.v7(),
            version: 1,
            envelope: {
              'ciphertext': 'x',
              'wraps': [
                {'passphrase': 'oops'},
              ],
            },
          ).toJson(),
        );
        expect(leaky.errorCode, 'invalid_field');

        final ok = await h.api.call(
          Routes.putFullBackup,
          bearer: alice.bearer,
          body: FullBackup(
            backupId: Uuid.v7(),
            version: 1,
            envelope: const {'ciphertext': 'x', 'kdf': 'argon2id'},
            mediaIds: [media.mediaId],
          ).toJson(),
        );
        expect(ok.status, 204);
        final read = FullBackup.fromJson(
          (await h.api.call(Routes.getFullBackup, bearer: alice.bearer)).json,
        );
        expect(read.mediaIds, [media.mediaId]);
        expect(read.envelope['kdf'], 'argon2id');
      },
    );
  });
}
