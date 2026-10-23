import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/platform/storage_usage.dart';
import 'package:helix_remote/core/theme/orbit_app_theme.dart';
import 'package:helix_remote/core/theme/orbit_packs.dart';
import 'package:helix_remote_crypto/v2.dart'
    show Ed25519KeyPair, Sha256Accumulator;
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote/features/settings/application/theme_packs.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show OrbitPackEntry;

import '../support/orbit_theme.dart';

/// Part C step 3 on the device: the pack folder and what may be drawn with it,
/// the publisher anchor, the theme library a pack joins, the download manager's
/// sentences, and the Storage page's number for the bytes.
void main() {
  late Directory tmp;

  setUpAll(() async {
    publisherKey = await Ed25519KeyPair.fromSeed(List<int>.filled(32, 3));
    otherKey = await Ed25519KeyPair.fromSeed(List<int>.filled(32, 9));
    trusted = {'helix': publisherKey.publicKey};
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('helix_packs');
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

  group('the pack folder', () {
    test('a signed pack installs, and is a theme from then on', () async {
      final store = ThemePackStore(trustedPublishers: trusted);
      final pack = await signedPack(by: publisherKey);
      expect(
        await store.install(FakePackSource([pack]), 'synthwave'),
        PackChange.installed,
      );

      final installed = await store.installed();
      expect(installed.single.id, 'synthwave');
      expect(installed.single.name, 'Synthwave');
      expect(installed.single.revision, 1);
      expect(installed.single.bytes, greaterThan(pack.manifestBytes.length));
      expect((await store.themeTokens()).keys, ['synthwave']);

      // Files are kept by their digest, not by the path the manifest named:
      // that is what makes a file two revisions share one copy, and what leaves
      // no path for a pack to point somewhere else with.
      final folder = Directory('${await packsRoot()}/synthwave/r1');
      expect(File('${folder.path}/manifest.json').existsSync(), isTrue);
      final files = Directory('${folder.path}/files').listSync();
      expect(files.single, isA<File>());
      expect(
        files.single.path.replaceAll(r'\', '/'),
        endsWith(pack.manifest.files.single.sha256),
      );
      expect(Directory('${folder.path}/themes').existsSync(), isFalse);
    });

    test('an unsigned pack is refused and nothing is written', () async {
      final store = ThemePackStore(trustedPublishers: trusted);
      final pack = await signedPack(by: publisherKey, signature: false);
      await expectLater(
        store.install(FakePackSource([pack]), 'synthwave'),
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
      expect(Directory('$root/synthwave').existsSync(), isFalse);
      // A download that failed leaves no staging bytes behind either.
      expect(Directory('$root/.staging').existsSync(), isFalse);
    });

    test(
      'a pack from a publisher this build does not trust is refused',
      () async {
        // The anchor an app ships with is empty, which is what this says.
        final store = const ThemePackStore(trustedPublishers: {});
        await expectLater(
          store.install(
            FakePackSource([await signedPack(by: publisherKey)]),
            'synthwave',
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
      final store = ThemePackStore(trustedPublishers: trusted);
      await expectLater(
        store.install(
          FakePackSource([await signedPack(by: otherKey)]),
          'synthwave',
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

    test('a file that is not the one signed is refused, and the theme on '
        'screen is left alone', () async {
      final store = ThemePackStore(trustedPublishers: trusted);
      await store.install(
        FakePackSource([await signedPack(by: publisherKey)]),
        'synthwave',
      );

      // r2 on offer, with other bytes under the digest its signed manifest
      // names: a host that swapped the theme document after it was signed.
      final tampered = await signedPack(
        by: publisherKey,
        revision: 2,
        name: 'Synthwave 2',
      ).then((pack) => pack.servedAs(junk));
      await expectLater(
        store.install(FakePackSource([tampered]), 'synthwave', revision: 2),
        throwsA(
          isA<PackRefused>().having(
            (e) => e.failure,
            'failure',
            OrbitPackFailure.changedFile,
          ),
        ),
      );
      // r1 is still what the app draws with, and nothing became r2.
      final still = await store.installed();
      expect(still.single.revision, 1);
      expect(still.single.name, 'Synthwave');
      expect(
        Directory('${await packsRoot()}/synthwave/r2').existsSync(),
        isFalse,
      );
    });

    test('a theme that switches on an effect this build has not got is '
        'refused', () async {
      final store = ThemePackStore(trustedPublishers: trusted);
      final pack = await signedPack(
        by: publisherKey,
        theme: themed(
          id: 'synthwave',
          name: 'Synthwave',
          effects: const [
            {'kind': 'hologram'},
          ],
        ),
      );
      await expectLater(
        store.install(FakePackSource([pack]), 'synthwave'),
        throwsA(
          isA<PackRefused>().having(
            (e) => e.failure,
            'failure',
            OrbitPackFailure.unknownEffect,
          ),
        ),
      );
    });

    test('a pack the host does not list is not installed', () async {
      final store = ThemePackStore(trustedPublishers: trusted);
      await expectLater(
        store.install(FakePackSource(const []), 'synthwave'),
        throwsA(isA<PackNotHosted>()),
      );
      // A name that could never be a pack is refused without asking the host.
      await expectLater(
        store.install(FakePackSource(const []), '../../windows'),
        throwsA(isA<PackNotHosted>()),
      );
    });

    test('the same revision is never fetched twice', () async {
      final store = ThemePackStore(trustedPublishers: trusted);
      final pack = await signedPack(by: publisherKey);
      final source = FakePackSource([pack]);
      expect(await store.install(source, 'synthwave'), PackChange.installed);
      expect(
        await store.install(source, 'synthwave'),
        PackChange.alreadyCurrent,
      );
      expect(source.fetched, [pack.manifest.files.single.sha256]);
    });

    test('a newer revision updates, and the older bytes go', () async {
      final store = ThemePackStore(trustedPublishers: trusted);
      await store.install(
        FakePackSource([await signedPack(by: publisherKey)]),
        'synthwave',
      );
      await store.install(
        FakePackSource([
          await signedPack(by: publisherKey, revision: 2, name: 'Synthwave 2'),
        ]),
        'synthwave',
      );

      final installed = await store.installed();
      expect(installed.single.revision, 2);
      expect(installed.single.name, 'Synthwave 2');
      final root = await packsRoot();
      expect(Directory('$root/synthwave/r1').existsSync(), isFalse);
      expect(Directory('$root/synthwave/r2').existsSync(), isTrue);

      // Asking for an old revision back does not downgrade the device.
      expect(
        await store.install(
          FakePackSource([await signedPack(by: publisherKey)]),
          'synthwave',
          revision: 1,
        ),
        PackChange.alreadyCurrent,
      );
      expect((await store.installed()).single.revision, 2);
    });

    test(
      'a pack edited on the device stops being a theme, and is kept',
      () async {
        final store = ThemePackStore(trustedPublishers: trusted);
        final pack = await signedPack(by: publisherKey);
        await store.install(FakePackSource([pack]), 'synthwave');

        // Someone writes over the theme document after it was installed - or the
        // bytes rot. Re-checking on every read is what keeps this app from
        // drawing with it.
        final digest = pack.manifest.files.single.sha256;
        final at = File('${await packsRoot()}/synthwave/r1/files/$digest');
        at.writeAsBytesSync(junk);

        expect(await store.installed(), isEmpty);
        expect(await store.load('synthwave'), isNull);
        expect(await store.themeTokens(), isEmpty);
        // Left on disk: a bad read today must not delete a person's download.
        expect(at.existsSync(), isTrue);
      },
    );

    test('a folder naming another pack is not read as one', () async {
      final store = ThemePackStore(trustedPublishers: trusted);
      final pack = await signedPack(by: publisherKey, id: 'other');
      final root = await packsRoot();
      Directory('$root/synthwave/r1/files').createSync(recursive: true);
      File(
        '$root/synthwave/r1/manifest.json',
      ).writeAsBytesSync(pack.manifestBytes);
      File(
        '$root/synthwave/r1/files/${pack.manifest.files.single.sha256}',
      ).writeAsBytesSync(pack.manifestBytes); // any bytes: the name is wrong

      expect(await store.installed(), isEmpty);
      expect(await store.load('synthwave'), isNull);
    });

    test('deleting a pack takes its folder with it', () async {
      final store = ThemePackStore(trustedPublishers: trusted);
      await store.install(
        FakePackSource([await signedPack(by: publisherKey)]),
        'synthwave',
      );
      final root = await packsRoot();
      expect(Directory('$root/synthwave').existsSync(), isTrue);

      expect(await store.remove('synthwave'), isTrue);
      expect(Directory('$root/synthwave').existsSync(), isFalse);
      expect(await store.installed(), isEmpty);
      expect(await store.remove('synthwave'), isFalse);
      expect(await store.remove('../..'), isFalse);
    });

    test('a pack that promises more bytes than a pack may hold is refused '
        'before it is fetched', () async {
      final store = ThemePackStore(trustedPublishers: trusted);
      // One file the manifest claims is 1 MiB over the per-file cap.
      final pack = await signedPack(
        by: publisherKey,
        fileBytes: OrbitPackLimits.standard.fileBytes + 1024,
      );
      final source = FakePackSource([pack]);
      await expectLater(
        store.install(source, 'synthwave'),
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
  });

  group('the anchor', () {
    test('is empty unless the build passes one', () {
      expect(PackTrust.parse(''), isEmpty);
      expect(PackTrust.forThisBuild(''), isEmpty);
    });

    test('reads a publisher and its key', () {
      final parsed = PackTrust.parse('helix:$hexKey, other-lab:$hexKey');
      expect(parsed.keys, ['helix', 'other-lab']);
      expect(parsed['helix'], keyBytes);
    });

    test('refuses a value that is not a publisher and a key', () {
      expect(() => PackTrust.parse('helix'), throwsA(isA<FormatException>()));
      expect(
        () => PackTrust.parse('helix:${'0' * 63}'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PackTrust.parse('Helix:$hexKey'),
        throwsA(isA<FormatException>()),
      );
      // The read path falls back to trusting nobody rather than to a build
      // that will not start; a download says so.
      expect(PackTrust.forThisBuildOrNone('helix'), isEmpty);
    });
  });

  group('the theme library', () {
    test(
      'a downloaded pack is a theme, and the app draws with it once chosen',
      () async {
        final container = libraryContainer();
        expect(
          container.read(themeLibraryProvider).keys,
          containsAll(builtInThemeIds),
        );
        // Nothing changes on screen until the theme is chosen.
        expect(container.read(orbitTokensProvider).meta.id, defaultThemeId);

        final source = FakePackSource([await signedPack(by: publisherKey)]);
        await container
            .read(themePackStoreProvider)
            .install(source, 'synthwave');
        await container.read(downloadedThemesProvider.notifier).reload();

        expect(
          container.read(themeLibraryProvider).keys,
          containsAll(<String>['synthwave', ...builtInThemeIds]),
        );
        await container.read(themeChoiceProvider.notifier).choose('synthwave');
        expect(container.read(themeChoiceProvider), 'synthwave');
        expect(container.read(orbitTokensProvider).meta.name, 'Synthwave');
        // The choice is a device setting, so it is written down as a pack id.
        expect(await const FileDeviceSettingsStore().readTheme(), 'synthwave');
      },
    );

    test(
      'a pack never takes a built-in theme name, whatever it claims',
      () async {
        final container = ProviderContainer(
          overrides: [
            orbitThemeLibraryProvider.overrideWithValue(orbitTestThemes),
            initialThemeIdProvider.overrideWithValue(defaultThemeId),
            packPublishersProvider.overrideWithValue(trusted),
            // A pack folder that arrived claiming the name of a built-in theme.
            downloadedThemesAtStartupProvider.overrideWithValue({
              'orbit': orbitTestThemes['night']!,
              'synthwave': orbitTestThemes['night']!,
            }),
          ],
        );
        addTearDown(container.dispose);
        expect(
          container.read(themeLibraryProvider)['orbit'],
          same(orbitTestThemes['orbit']),
        );
        expect(
          container.read(themeLibraryProvider).containsKey('synthwave'),
          isTrue,
        );
      },
    );

    test('a theme that is not on the device cannot be chosen', () async {
      final container = libraryContainer();
      await container.read(themeChoiceProvider.notifier).choose('bloom');
      expect(container.read(themeChoiceProvider), defaultThemeId);
    });

    test('when a chosen pack goes, the app draws Orbit again', () async {
      final container = libraryContainer();
      await container
          .read(themePackStoreProvider)
          .install(
            FakePackSource([await signedPack(by: publisherKey)]),
            'synthwave',
          );
      await container.read(downloadedThemesProvider.notifier).reload();
      await container.read(themeChoiceProvider.notifier).choose('synthwave');

      await container.read(themePackStoreProvider).remove('synthwave');
      await container.read(downloadedThemesProvider.notifier).reload();

      expect(container.read(orbitTokensProvider).meta.id, defaultThemeId);
      // The choice is kept: downloading it again brings the theme back.
      expect(container.read(themeChoiceProvider), 'synthwave');
      expect(await const FileDeviceSettingsStore().readTheme(), 'synthwave');
    });

    test(
      'a pack that stops passing its checks leaves the app on Orbit',
      () async {
        final container = libraryContainer();
        final pack = await signedPack(by: publisherKey);
        await container
            .read(themePackStoreProvider)
            .install(FakePackSource([pack]), 'synthwave');
        await container.read(downloadedThemesProvider.notifier).reload();
        await container.read(themeChoiceProvider.notifier).choose('synthwave');

        File(
          '${await packsRoot()}/synthwave/r1/files/'
          '${pack.manifest.files.single.sha256}',
        ).writeAsBytesSync(junk);
        await container.read(downloadedThemesProvider.notifier).reload();

        expect(container.read(orbitTokensProvider).meta.id, defaultThemeId);
      },
    );

    test('the saved theme is only ever a theme id', () async {
      final file = await AppPaths.deviceSettingsFile();
      file.createSync(recursive: true);
      Future<String?> read(String json) async {
        file.writeAsStringSync(json);
        return const FileDeviceSettingsStore().readTheme();
      }

      expect(await read('{"theme":"synthwave.v2-1"}'), 'synthwave.v2-1');
      expect(await read('{"theme":"../etc"}'), isNull);
      expect(await read('{"theme":"Orbit"}'), isNull);
      expect(await read('{"theme":""}'), isNull);
      expect(await read('{"theme":7}'), isNull);
      expect(await read('not json'), isNull);
    });
  });

  group('the download manager', () {
    test('a download says which theme arrived, and the pages see it', () async {
      final pack = await signedPack(by: publisherKey);
      final container = libraryContainer(source: FakePackSource([pack]));

      expect(
        await container.read(themePackActionsProvider).install('synthwave'),
        'Synthwave theme downloaded.',
      );
      expect(
        container.read(themeLibraryProvider).containsKey('synthwave'),
        isTrue,
      );
      expect(
        (await container.read(installedPacksProvider.future)).single.name,
        'Synthwave',
      );
      expect(
        (await container.read(hostedPacksProvider.future)).single.id,
        'synthwave',
      );
      // Asking again brings nothing back: a revision is fetched once.
      expect(
        await container.read(themePackActionsProvider).install('synthwave'),
        'Already up to date.',
      );
      expect(
        await container.read(themePackActionsProvider).install('night'),
        'That theme is built into the app, so there is nothing to download.',
      );
    });

    test(
      'a refusal is said in the format\'s own words and installs nothing',
      () async {
        final container = libraryContainer(
          source: FakePackSource([await signedPack(by: otherKey)]),
        );
        final said = await container
            .read(themePackActionsProvider)
            .install('synthwave');
        expect(said, contains('cannot be used'));
        expect(said, isNot(contains('synthwave'))); // never quoted back
        expect(
          container.read(themeLibraryProvider).containsKey('synthwave'),
          isFalse,
        );
        expect(await container.read(installedPacksProvider.future), isEmpty);
      },
    );

    test('a pack that is no longer on offer is said so', () async {
      final container = libraryContainer(source: FakePackSource(const []));
      expect(
        await container.read(themePackActionsProvider).install('synthwave'),
        'That theme is no longer on offer.',
      );
    });

    test('deleting says the theme is gone', () async {
      final pack = await signedPack(by: publisherKey);
      final container = libraryContainer(source: FakePackSource([pack]));
      await container.read(themePackActionsProvider).install('synthwave');

      expect(
        await container.read(themePackActionsProvider).remove('synthwave'),
        'Synthwave theme deleted.',
      );
      expect(await container.read(installedPacksProvider.future), isEmpty);
      expect(
        container.read(themeLibraryProvider).containsKey('synthwave'),
        isFalse,
      );
      expect(
        await container.read(themePackActionsProvider).remove('synthwave'),
        'That theme is not on this device.',
      );
    });

    test('an update is a download of the newest revision', () async {
      final container = libraryContainer(
        source: FakePackSource([
          await signedPack(by: publisherKey),
          await signedPack(by: publisherKey, revision: 3, name: 'Synthwave 3'),
        ]),
      );
      expect(
        await container.read(themePackActionsProvider).install('synthwave'),
        'Synthwave 3 theme downloaded.',
      );
      expect(
        (await container.read(installedPacksProvider.future)).single.revision,
        3,
      );
    });
  });

  group('storage', () {
    test('theme packs are counted as themselves, not as media', () async {
      final base = await AppPaths.appDirectory();
      File(
        '${base.path}/helix_remote.db',
      ).writeAsBytesSync(List<int>.filled(1024, 0));
      File('${base.path}/work.tmp').writeAsBytesSync(List<int>.filled(2048, 0));
      final root = await packsRoot();
      Directory('$root/synthwave/r1/files').createSync(recursive: true);
      File(
        '$root/synthwave/r1/manifest.json',
      ).writeAsBytesSync(List<int>.filled(512, 1));
      File(
        '$root/synthwave/r1/files/a',
      ).writeAsBytesSync(List<int>.filled(512, 1));

      final usage = await const DeviceStorageUsageProbe().measure();
      expect(usage.databaseBytes, 1024);
      expect(usage.mediaBytes, 2048);
      expect(usage.packBytes, 1024);
      expect(usage.totalBytes, 4096);
    });

    test('a device with no packs has nothing to count', () async {
      final usage = await const DeviceStorageUsageProbe().measure();
      expect(usage.packBytes, 0);
      expect(usage.totalBytes, 0);
    });
  });
}

// ------------------------------------------------------------------ fixtures

/// The key the test packs are signed by, and the build's trust in it. Both are
/// made once, in `setUpAll`, because Ed25519 derivation is not free.
late final Ed25519KeyPair publisherKey;
late final Ed25519KeyPair otherKey;
late final Map<String, List<int>> trusted;

/// The theme a test pack carries, as bytes and as the file it is in.
final List<int> junk = utf8.encode('{"id": "synthwave", "tokens": {}}');

final List<int> keyBytes = List<int>.generate(32, (i) => i);
final String hexKey = keyBytes
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

Future<String> packsRoot() async => (await AppPaths.packsDirectory()).path;

/// A container with the themes [main] would seed, this test's anchor, and one
/// temp folder to write into.
ProviderContainer libraryContainer({FakePackSource? source}) {
  final container = ProviderContainer(
    overrides: [
      orbitThemeLibraryProvider.overrideWithValue(orbitTestThemes),
      initialThemeIdProvider.overrideWithValue(defaultThemeId),
      downloadedThemesAtStartupProvider.overrideWithValue(const {}),
      packPublishersProvider.overrideWithValue(trusted),
      if (source != null) packSourceProvider.overrideWithValue(source),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// The theme document of a pack: one of the app's own generated themes, with
/// its id and name moved to the pack's, so it is a real document and every
/// effect and pattern in it is one this build ships.
Map<String, Object?> themed({
  required String id,
  required String name,
  List<Object?> effects = const [],
}) {
  final doc =
      jsonDecode(
            File(
              '../packages/orbit_ui/assets/themes/night.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  doc['id'] = id;
  doc['name'] = name;
  if (effects.isNotEmpty) doc['effects'] = effects;
  return doc;
}

/// One pack as its host has it: the manifest as published, and the bytes of
/// every file it names, by path.
final class HostedPack {
  HostedPack({required this.manifest, required this.files});

  final OrbitPackManifest manifest;
  final Map<String, List<int>> files;

  Uint8List get manifestBytes =>
      Uint8List.fromList(utf8.encode(jsonEncode(manifest.toJson())));

  Map<String, List<int>> get byDigest => {
    for (final entry in manifest.files) entry.sha256: files[entry.path]!,
  };

  OrbitPackEntry get listed => OrbitPackEntry(
    id: manifest.id,
    revision: manifest.revision,
    manifestBytes: manifestBytes.length,
    totalBytes: manifest.files.fold(0, (a, f) => a + f.bytes),
    updatedAt: DateTime.utc(2026, 10, 23),
  );

  /// The same manifest, serving other bytes: what a host that changed a
  /// published pack answers.
  HostedPack servedAs(List<int> bytes) => HostedPack(
    manifest: manifest,
    files: {for (final path in files.keys) path: bytes},
  );
}

/// A pack the publisher signed - or one they did not, with [signature] false.
Future<HostedPack> signedPack({
  required Ed25519KeyPair by,
  String id = 'synthwave',
  int revision = 1,
  String publisher = 'helix',
  String name = 'Synthwave',
  Map<String, Object?>? theme,
  bool signature = true,
  int? fileBytes,
}) async {
  final doc = theme ?? themed(id: id, name: name);
  var bytes = Uint8List.fromList(utf8.encode(jsonEncode(doc)));
  if (fileBytes != null) {
    // Padded, so it is the manifest's promise being checked and not the size
    // of a real theme document.
    bytes = Uint8List.fromList([
      ...bytes,
      ...List<int>.filled(fileBytes - bytes.length, 0x20),
    ]);
  }
  final path = 'themes/$id.json';
  final digest = await sha256Hex(bytes);
  OrbitPackManifest build(String? signed) => OrbitPackManifest(
    formatVersion: orbitPackFormatVersion,
    id: id,
    publisher: publisher,
    revision: revision,
    theme: path,
    files: [
      OrbitPackFile(
        path: path,
        kind: 'theme',
        bytes: bytes.length,
        sha256: digest,
      ),
    ],
    signature: signed,
  );
  final signature64 = base64Encode(await by.sign(build(null).signingBytes()));
  return HostedPack(
    manifest: build(signature ? signature64 : null),
    files: {path: bytes},
  );
}

/// The host: answers the three pack routes from [packs], and remembers every
/// file digest it was asked for.
final class FakePackSource implements PackSource {
  FakePackSource(this.packs);

  final List<HostedPack> packs;
  final List<String> fetched = [];

  HostedPack _one(String id, int revision) => packs.firstWhere(
    (p) => p.manifest.id == id && p.manifest.revision == revision,
    orElse: () => throw StateError('the host holds no $id r$revision'),
  );

  @override
  Future<List<OrbitPackEntry>> list() async => [
    for (final pack in packs) pack.listed,
  ];

  @override
  Future<List<int>> manifest(String id, int revision) async =>
      _one(id, revision).manifestBytes;

  @override
  Future<List<int>> file(String id, int revision, String digest) async {
    fetched.add(digest);
    final bytes = _one(id, revision).byDigest[digest];
    if (bytes == null) throw StateError('the host has no file $digest');
    return bytes;
  }
}

Future<String> sha256Hex(List<int> bytes) async {
  final digest = Sha256Accumulator()..add(bytes);
  return digest.close().map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
