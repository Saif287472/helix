import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/sounds/orbit_sounds.dart';
import 'package:helix_remote/core/theme/orbit_packs.dart';
import 'package:helix_remote_domain/models.dart' show OrbitPackFailure;

import '../support/pack_fixtures.dart';

/// Part C step 5 on the device: the ringtone a person downloads, kept in the
/// same pack folder as the themes, gate-checked the same way, and read only by
/// the store that plays it.
void main() {
  late Directory tmp;

  setUpAll(makePublisherKeys);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('helix_sounds');
    AppPaths.localDataDirectory = () async => tmp;
    AppPaths.privateDataDirectory = () async => tmp;
    AppPaths.isWindows = () => true;
  });

  tearDown(() {
    AppPaths.localDataDirectory = () async => throw StateError('unset');
    AppPaths.privateDataDirectory = () async => throw StateError('unset');
    AppPaths.isWindows = () => Platform.isWindows;
    tmp.deleteSync(recursive: true);
  });

  group('the sound folder', () {
    test(
      'a signed sound pack installs, and is a ringtone from then on',
      () async {
        final store = SoundPackStore(trustedPublishers: trusted);
        final pack = await signedSoundPack(by: publisherKey);
        expect(
          await store.install(FakePackSource([pack]), 'chime'),
          PackChange.installed,
        );

        final installed = await store.installed();
        expect(installed.single.id, 'chime');
        expect(installed.single.revision, 1);
        expect(installed.single.bytes, greaterThan(pack.manifestBytes.length));
        expect(installed.single.suffix, '.m4a');
        expect(installed.single.file.existsSync(), isTrue);
        expect(
          installed.single.file.readAsBytesSync(),
          pack.files.values.single,
        );

        // The server's own layout, and the file named by its digest rather than
        // by the path the manifest wrote - which is the path a sound's page has
        // to hand a notification channel.
        final folder = Directory('${await packsRoot()}/chime/r1');
        expect(File('${folder.path}/manifest.json').existsSync(), isTrue);
        final files = Directory('${folder.path}/files').listSync();
        expect(
          files.single.path.replaceAll(r'\', '/'),
          endsWith(pack.manifest.files.single.sha256),
        );
        expect(Directory('${folder.path}/sounds').existsSync(), isFalse);
      },
    );

    test('a hosted theme pack is refused before its bytes are fetched', () async {
      // One folder holds both kinds, so this is the ordinary case: the server
      // lists a theme and a ringtone, and only the manifest says which is which.
      final store = SoundPackStore(trustedPublishers: trusted);
      final source = FakePackSource([await signedPack(by: publisherKey)]);
      await expectLater(
        store.install(source, 'synthwave'),
        throwsA(
          isA<PackRefused>().having(
            (e) => e.failure,
            'failure',
            OrbitPackFailure.unknownContent,
          ),
        ),
      );
      expect(source.fetched, isEmpty);
      expect(await store.installed(), isEmpty);
      expect(Directory('${await packsRoot()}/synthwave').existsSync(), isFalse);
    });

    test('a theme pack already on the device is not a ringtone', () async {
      final themes = ThemePackStore(trustedPublishers: trusted);
      await themes.install(
        FakePackSource([await signedPack(by: publisherKey)]),
        'synthwave',
      );

      final sounds = SoundPackStore(trustedPublishers: trusted);
      expect(await sounds.installed(), isEmpty);
      expect(await sounds.load('synthwave'), isNull);
      // Its bytes stay: this store is not the one that draws it.
      expect(
        Directory('${await packsRoot()}/synthwave/r1').existsSync(),
        isTrue,
      );
    });

    test('an unsigned sound pack is refused and nothing is written', () async {
      final store = SoundPackStore(trustedPublishers: trusted);
      final pack = await signedSoundPack(by: publisherKey, signature: false);
      await expectLater(
        store.install(FakePackSource([pack]), 'chime'),
        throwsA(
          isA<PackRefused>().having(
            (e) => e.failure,
            'failure',
            OrbitPackFailure.unsigned,
          ),
        ),
      );
      expect(await store.installed(), isEmpty);
      final root = await packsRoot();
      expect(Directory('$root/chime').existsSync(), isFalse);
      expect(Directory('$root/.staging').existsSync(), isFalse);
    });

    test(
      'a sound pack from a publisher this build does not trust is refused',
      () async {
        // The anchor an app ships with is empty, which is what this says.
        final store = SoundPackStore(trustedPublishers: {});
        await expectLater(
          store.install(
            FakePackSource([await signedSoundPack(by: publisherKey)]),
            'chime',
          ),
          throwsA(
            isA<PackRefused>().having(
              (e) => e.failure,
              'failure',
              OrbitPackFailure.unknownPublisher,
            ),
          ),
        );
        expect(await store.installed(), isEmpty);
      },
    );

    test('bytes the publisher did not sign are refused', () async {
      final store = SoundPackStore(trustedPublishers: trusted);
      await expectLater(
        store.install(
          FakePackSource([await signedSoundPack(by: otherKey)]),
          'chime',
        ),
        throwsA(
          isA<PackRefused>().having(
            (e) => e.failure,
            'failure',
            OrbitPackFailure.badSignature,
          ),
        ),
      );
      expect(await store.installed(), isEmpty);
    });

    test(
      'a sound edited on the device stops being a ringtone, and is kept',
      () async {
        final store = SoundPackStore(trustedPublishers: trusted);
        final pack = await signedSoundPack(by: publisherKey);
        await store.install(FakePackSource([pack]), 'chime');

        // Someone writes over the downloaded file after it was installed - or the
        // bytes rot. Re-checking on every read is what keeps this app from ringing
        // with something nobody signed.
        final digest = pack.manifest.files.single.sha256;
        final at = File('${await packsRoot()}/chime/r1/files/$digest');
        at.writeAsBytesSync(junk);

        expect(await store.installed(), isEmpty);
        expect(await store.load('chime'), isNull);
        expect(at.existsSync(), isTrue);
      },
    );

    test('the same revision is never fetched twice', () async {
      final store = SoundPackStore(trustedPublishers: trusted);
      final pack = await signedSoundPack(by: publisherKey);
      final source = FakePackSource([pack]);
      expect(await store.install(source, 'chime'), PackChange.installed);
      expect(await store.install(source, 'chime'), PackChange.alreadyCurrent);
      expect(source.fetched, [pack.manifest.files.single.sha256]);
    });

    test('a newer revision updates, and the older bytes go', () async {
      final store = SoundPackStore(trustedPublishers: trusted);
      await store.install(
        FakePackSource([await signedSoundPack(by: publisherKey)]),
        'chime',
      );
      await store.install(
        FakePackSource([await signedSoundPack(by: publisherKey, revision: 2)]),
        'chime',
      );

      final installed = await store.installed();
      expect(installed.single.revision, 2);
      final root = await packsRoot();
      expect(Directory('$root/chime/r1').existsSync(), isFalse);
      expect(Directory('$root/chime/r2').existsSync(), isTrue);

      // Asking for an old revision back does not downgrade the device.
      expect(
        await store.install(
          FakePackSource([await signedSoundPack(by: publisherKey)]),
          'chime',
          revision: 1,
        ),
        PackChange.alreadyCurrent,
      );
      expect((await store.installed()).single.revision, 2);
    });

    test('a sound pack that promises too many bytes is refused before they are '
        'fetched', () async {
      final store = SoundPackStore(trustedPublishers: trusted);
      // One file the manifest claims is 1 MiB over the per-file cap - a
      // ringtone is a few hundred KiB, so this is a pack worth refusing.
      final pack = await signedSoundPack(
        by: publisherKey,
        fileBytes: 9 * 1024 * 1024,
      );
      final source = FakePackSource([pack]);
      await expectLater(
        store.install(source, 'chime'),
        throwsA(
          isA<PackRefused>().having(
            (e) => e.failure,
            'failure',
            OrbitPackFailure.tooLarge,
          ),
        ),
      );
      expect(source.fetched, isEmpty);
    });

    test('deleting a sound pack takes its folder with it', () async {
      final store = SoundPackStore(trustedPublishers: trusted);
      await store.install(
        FakePackSource([await signedSoundPack(by: publisherKey)]),
        'chime',
      );
      final root = await packsRoot();
      expect(Directory('$root/chime').existsSync(), isTrue);

      expect(await store.remove('chime'), isTrue);
      expect(Directory('$root/chime').existsSync(), isFalse);
      expect(await store.installed(), isEmpty);
      expect(await store.remove('chime'), isFalse);
      expect(await store.remove('../..'), isFalse);
    });

    test(
      'one folder holds both kinds, and each store lists only its own',
      () async {
        final pack = await signedPack(by: publisherKey);
        final sound = await signedSoundPack(by: publisherKey);
        final source = FakePackSource([pack, sound]);
        final themes = ThemePackStore(trustedPublishers: trusted);
        final sounds = SoundPackStore(trustedPublishers: trusted);
        await themes.install(source, 'synthwave');
        await sounds.install(source, 'chime');

        expect((await themes.installed()).map((p) => p.id), ['synthwave']);
        expect((await sounds.installed()).map((s) => s.id), ['chime']);
        // Neither store can delete the other's pack by accident of a shared id:
        // the ids are different folders, and a store that cannot read the other's
        // bytes never claims to have removed them.
        expect(await themes.load('chime'), isNull);
        expect(await sounds.load('synthwave'), isNull);
      },
    );
  });
}
