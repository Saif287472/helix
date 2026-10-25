import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/ops/pack_host.dart';
import 'package:test/test.dart';

import '../support/harness.dart';
import '../support/test_database.dart';

/// A pack as the operator's `publish` writes it: a slug, an `r<revision>`
/// folder, the manifest, and each file named by its own SHA-256.
///
/// The bytes are not a real pack - nothing here knows the format, which is
/// the point. What a device makes of them is `helix_remote_domain`'s
/// `theme_packs_test.dart`'s business.
class PublishedPack {
  PublishedPack({
    required this.id,
    required this.revision,
    required this.manifest,
    this.files = const {'themes/synthwave.json': '{"id":"synthwave"}'},
  });

  final String id;
  final int revision;
  final String manifest;
  final Map<String, String> files;

  /// Writes it under [root] and answers each file's digest, so a test can ask
  /// for a file the way a client does: by the hash, not by the path.
  Map<String, String> publish(Directory root) {
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}$id${Platform.pathSeparator}r$revision',
    )..createSync(recursive: true);
    File(
      '${directory.path}${Platform.pathSeparator}manifest.json',
    ).writeAsStringSync(manifest);
    final files = Directory('${directory.path}${Platform.pathSeparator}files')
      ..createSync();
    final digests = <String, String>{};
    for (final entry in this.files.entries) {
      final bytes = utf8.encode(entry.value);
      final digest = sha256.convert(bytes).toString();
      File(
        '${files.path}${Platform.pathSeparator}$digest',
      ).writeAsBytesSync(bytes);
      digests[entry.key] = digest;
    }
    return digests;
  }
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('helix_packs_'));
  tearDown(() => root.deleteSync(recursive: true));

  group('the pack host', () {
    test('a server with no pack folder has nothing, and is not broken', () {
      final host = PackHost(null);
      expect(host.list(), completes, reason: 'an empty list, not a throw');
      expect(host.manifest('synthwave', 1), completes);
    });

    test(
      'a folder that does not exist answers the same as an empty one',
      () async {
        final host = PackHost('${root.path}${Platform.pathSeparator}absent');
        expect(await host.list(), isEmpty);
        expect(await host.manifest('synthwave', 1), isA<PackMiss>());
      },
    );

    test('a published pack is listed by what its folder shows', () async {
      PublishedPack(
        id: 'synthwave',
        revision: 3,
        manifest: '{"id":"synthwave","revision":3}',
      ).publish(root);
      final packs = await PackHost(root.path).list();
      expect(packs, hasLength(1));
      final pack = packs.single;
      expect(pack.id, 'synthwave');
      expect(pack.revision, 3);
      expect(
        pack.manifestBytes,
        utf8.encode('{"id":"synthwave","revision":3}').length,
      );
      expect(
        pack.totalBytes,
        pack.manifestBytes + utf8.encode('{"id":"synthwave"}').length,
      );
      expect(
        pack.updatedAt.isBefore(
          DateTime.now().toUtc().add(const Duration(minutes: 1)),
        ),
        isTrue,
        reason: 'the time on the entry is the time the folder holds',
      );
    });

    test('two revisions of a pack are two entries, sorted', () async {
      for (final revision in [11, 2]) {
        PublishedPack(
          id: 'bloom',
          revision: revision,
          manifest: '{"revision":$revision}',
        ).publish(root);
      }
      PublishedPack(id: 'arcade', revision: 1, manifest: '{}').publish(root);
      final packs = await PackHost(root.path).list();
      expect(
        [for (final p in packs) (p.id, p.revision)],
        [('arcade', 1), ('bloom', 2), ('bloom', 11)],
        reason: 'sorted by id then revision, so two nodes answer alike',
      );
    });

    test('a folder that is not a pack is not listed', () async {
      PublishedPack(id: 'field', revision: 1, manifest: '{}').publish(root);
      // A revision folder with no manifest: half-published.
      Directory(
        '${root.path}${Platform.pathSeparator}half${Platform.pathSeparator}r1',
      ).createSync(recursive: true);
      // A name the format cannot use, and a folder that is not a revision.
      Directory(
        '${root.path}${Platform.pathSeparator}Not A Pack',
      ).createSync(recursive: true);
      Directory(
        '${root.path}${Platform.pathSeparator}tidy${Platform.pathSeparator}tmp',
      ).createSync(recursive: true);
      File(
        '${root.path}${Platform.pathSeparator}notes.txt',
      ).writeAsStringSync('left in the folder');
      final packs = await PackHost(root.path).list();
      expect([for (final p in packs) p.id], ['field']);
    });

    test('the manifest is handed over exactly as published', () async {
      const manifest = '{"id":"synthwave","signature":"as-signed"}';
      PublishedPack(
        id: 'synthwave',
        revision: 1,
        manifest: manifest,
      ).publish(root);
      final read = await PackHost(root.path).manifest('synthwave', 1);
      final hit = expectA<PackHit>(read);
      expect(hit.length, utf8.encode(manifest).length);
      expect(
        await readAll(hit.open()),
        manifest,
        reason: 'the bytes a device hashes are the bytes that were signed',
      );
    });

    test('a file is served by its digest', () async {
      final digests = PublishedPack(
        id: 'synthwave',
        revision: 1,
        manifest: '{}',
      ).publish(root);
      const content = '{"id":"synthwave"}';
      final read = await PackHost(
        root.path,
      ).file('synthwave', 1, digests['themes/synthwave.json']!);
      final hit = expectA<PackHit>(read);
      expect(hit.length, utf8.encode(content).length);
      expect(await readAll(hit.open()), content);
    });

    test(
      'a name a pack folder cannot hold is the same 404 as a missing pack',
      () async {
        PublishedPack(
          id: 'synthwave',
          revision: 1,
          manifest: '{}',
        ).publish(root);
        final host = PackHost(root.path);
        for (final id in [
          '..',
          '.',
          'a/../../b',
          r'themes\files',
          '',
          '-synthwave',
          '.synthwave',
          'a' * 65,
        ]) {
          expect(
            await host.manifest(id, 1),
            isA<PackMiss>(),
            reason: 'an illegal slug never reaches the disk: $id',
          );
        }
        for (final revision in [0, -1, PackHost.maxRevision + 1]) {
          expect(
            await host.manifest('synthwave', revision),
            isA<PackMiss>(),
            reason: 'no folder is named r$revision',
          );
        }
        expect(
          await host.manifest('synthwave', 2),
          isA<PackMiss>(),
          reason: 'a revision not published here',
        );
        expect(
          await host.manifest('other', 1),
          isA<PackMiss>(),
          reason: 'a pack not published here',
        );
      },
    );

    test('a digest that is not a sha256 asks the disk for nothing', () async {
      final digests = PublishedPack(
        id: 'synthwave',
        revision: 1,
        manifest: '{}',
      ).publish(root);
      final real = digests['themes/synthwave.json']!;
      final host = PackHost(root.path);
      for (final digest in [
        '',
        real.toUpperCase(),
        '${real.substring(0, 63)}g',
        '${real}ab',
        real.substring(0, 63),
        '..',
        '../../../etc/passwd',
      ]) {
        expect(
          await host.file('synthwave', 1, digest),
          isA<PackMiss>(),
          reason: 'a selector that is not 64 lowercase hex: $digest',
        );
      }
      expect(await host.file('synthwave', 1, real), isA<PackHit>());
    });

    test('nothing larger than the format can describe is served', () async {
      PublishedPack(id: 'synthwave', revision: 1, manifest: '{}').publish(root);
      final directory =
          '${root.path}${Platform.pathSeparator}synthwave'
          '${Platform.pathSeparator}r1${Platform.pathSeparator}files';
      File(
        '$directory${Platform.pathSeparator}${'0' * 64}',
      ).writeAsBytesSync(List<int>.filled(PackHost.maxFileBytes + 1, 7));
      File(
        '${root.path}${Platform.pathSeparator}synthwave'
        '${Platform.pathSeparator}r1${Platform.pathSeparator}manifest.json',
      ).writeAsBytesSync(List<int>.filled(PackHost.maxManifestBytes + 1, 8));
      final host = PackHost(root.path);
      final manifest = await host.manifest('synthwave', 1);
      final big = expectA<PackTooBig>(manifest);
      expect(big.length, PackHost.maxManifestBytes + 1);
      expect(big.cap, PackHost.maxManifestBytes);
      expect(
        await host.file('synthwave', 1, '0' * 64),
        isA<PackTooBig>(),
        reason: 'a 8 MiB + 1 file is the operator\'s mistake, not a download',
      );
    });
  });

  group('the pack host index', () {
    test('one walk answers every caller until the lifetime ends', () async {
      var now = DateTime.utc(2026, 10, 25, 12);
      PublishedPack(id: 'arcade', revision: 1, manifest: '{}').publish(root);
      final host = PackHost(root.path, clock: () => now);

      final first = await host.list();
      expect([for (final pack in first) pack.revision], [1]);

      // A revision under an existing id and a whole new id both wait for the
      // lifetime: inside the window the same index answers, and a caller that
      // arrives meanwhile cannot see a half-published revision either.
      PublishedPack(id: 'arcade', revision: 2, manifest: '{}').publish(root);
      PublishedPack(id: 'bloom', revision: 1, manifest: '{}').publish(root);
      final second = await host.list();
      expect(identical(second, first), isTrue);

      now = now.add(PackHost.defaultListLifetime);
      final third = await host.list();
      expect(identical(third, first), isFalse);
      expect(
        [for (final pack in third) (pack.id, pack.revision)],
        [('arcade', 1), ('arcade', 2), ('bloom', 1)],
      );
    });

    test('concurrent callers wait on one walk', () async {
      PublishedPack(id: 'arcade', revision: 1, manifest: '{}').publish(root);
      final host = PackHost(root.path);
      final answers = await Future.wait([
        host.list(),
        host.list(),
        host.list(),
      ]);
      expect(identical(answers[0], answers[1]), isTrue);
      expect(identical(answers[1], answers[2]), isTrue);
    });

    test('the index is not what a download checks', () async {
      PublishedPack(id: 'arcade', revision: 1, manifest: '{}').publish(root);
      final host = PackHost(root.path);
      expect((await host.list()).single.revision, 1);

      // Removed after the walk: the list still names it until the lifetime
      // ends, but the read goes to the folder and misses.
      Directory(
        '${root.path}${Platform.pathSeparator}arcade'
        '${Platform.pathSeparator}r1',
      ).deleteSync(recursive: true);
      expect(await host.manifest('arcade', 1), isA<PackMiss>());
    });
  });

  group('the pack routes', skip: databaseTestSkipReason, () {
    late Harness h;
    late Map<String, String> digests;

    setUp(() async {
      const manifest =
          '{"id":"synthwave","revision":1,"publisher":"agiletechbd"}';
      digests = PublishedPack(
        id: 'synthwave',
        revision: 1,
        manifest: manifest,
      ).publish(root);
      h = await Harness.start(extra: {'HELIX_PACKS_DIR': root.path});
    });
    tearDown(() async => h.stop());

    test('the list says what the folder holds', () async {
      final response = await h.api.call(Routes.packs);
      expect(response.status, 200);
      expect(response.headers['content-type'], startsWith('application/json'));
      final list = OrbitPackList.fromJson(response.json);
      expect(list.packs, hasLength(1));
      final pack = list.packs.single;
      expect((pack.id, pack.revision), ('synthwave', 1));
      expect(
        pack.manifestBytes,
        utf8
            .encode('{"id":"synthwave","revision":1,"publisher":"agiletechbd"}')
            .length,
      );
      expect(pack.totalBytes, greaterThan(pack.manifestBytes));
      expect(
        response.headers['cache-control'],
        'no-store',
        reason: 'the pipeline adds it to every response, pack routes included',
      );
    });

    test('the manifest and a file come out as they went in', () async {
      final manifest = await h.api.call(
        Routes.packManifest,
        params: {'pack_id': 'synthwave', 'revision': '1'},
      );
      expect(manifest.status, 200);
      expect(manifest.headers['content-type'], startsWith('application/json'));
      expect(
        manifest.body,
        '{"id":"synthwave","revision":1,"publisher":"agiletechbd"}',
        reason: 'the signed bytes, unchanged',
      );

      final file = await h.api.call(
        Routes.packFile,
        params: {
          'pack_id': 'synthwave',
          'revision': '1',
          'digest': digests['themes/synthwave.json']!,
        },
      );
      expect(file.status, 200);
      expect(
        file.headers['content-type'],
        'application/octet-stream',
        reason: 'a pack file is data a device checks, never something to run',
      );
      expect(file.body, '{"id":"synthwave"}');
      expect(
        file.headers['content-length'],
        '${utf8.encode('{"id":"synthwave"}').length}',
      );
    });

    test('a pack, revision or file that is not here is a 404', () async {
      expect((await h.api.call(Routes.packs)).status, 200);
      for (final params in [
        {'pack_id': 'other', 'revision': '1'},
        {'pack_id': 'synthwave', 'revision': '2'},
        {'pack_id': 'synthwave', 'revision': 'not-a-number'},
        {'pack_id': '..', 'revision': '1'},
        {'pack_id': 'synthwave', 'revision': '01'},
      ]) {
        final response = await h.api.call(Routes.packManifest, params: params);
        expect(
          response.status,
          params['revision'] == '01' ? 200 : 404,
          reason: 'r1 is revision 1 however it is written: $params',
        );
      }
      final real = digests['themes/synthwave.json']!;
      for (final digest in [
        '',
        real.toUpperCase(),
        '${real}ab',
        real.substring(0, 63),
        '../../../etc/passwd',
      ]) {
        expect(
          (await h.api.call(
            Routes.packFile,
            params: {'pack_id': 'synthwave', 'revision': '1', 'digest': digest},
          )).status,
          404,
          reason: 'a selector that is not a digest: $digest',
        );
      }
    });

    test('a manifest past the format cap is refused, not streamed', () async {
      File(
        '${root.path}${Platform.pathSeparator}synthwave'
        '${Platform.pathSeparator}r1${Platform.pathSeparator}manifest.json',
      ).writeAsBytesSync(List<int>.filled(PackHost.maxManifestBytes + 1, 8));
      final response = await h.api.call(
        Routes.packManifest,
        params: {'pack_id': 'synthwave', 'revision': '1'},
      );
      expect(response.status, 413);
      expect(
        response.body,
        contains('payload_too_large'),
        reason: 'the operator sees what is wrong with their folder',
      );
    });

    test('the routes need no session and give no account away', () async {
      final response = await h.api.call(
        Routes.packs,
        headers: {'authorization': 'Bearer not-a-session'},
      );
      expect(
        response.status,
        200,
        reason: 'a bad token is not a reason to fail',
      );
      expect(response.body, isNot(contains('@')));
      expect(response.body, isNot(contains('account')));
    });
  });

  group('a server with no pack folder', skip: databaseTestSkipReason, () {
    late Harness h;

    setUp(() async => h = await Harness.start());
    tearDown(() async => h.stop());

    test('answers an empty list and 404s, and stays up', () async {
      final list = await h.api.call(Routes.packs);
      expect(list.status, 200);
      expect(OrbitPackList.fromJson(list.json).packs, isEmpty);
      expect(
        (await h.api.call(
          Routes.packManifest,
          params: {'pack_id': 'synthwave', 'revision': '1'},
        )).status,
        404,
      );
      expect(
        (await h.api.call(Routes.ready)).status,
        200,
        reason: 'hosting no packs is not an unhealthy server',
      );
    });
  });
}

/// The read of one type, with a message that names what actually came back.
T expectA<T>(Object? value) {
  expect(value, isA<T>());
  return value as T;
}

/// A served file, whole, as text.
Future<String> readAll(Stream<List<int>> stream) async {
  final bytes = <int>[];
  await for (final chunk in stream) {
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes);
}
