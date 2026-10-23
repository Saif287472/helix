import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/platform/storage_usage.dart';
import 'package:helix_remote/core/theme/orbit_app_theme.dart';
import 'package:helix_remote/core/theme/orbit_packs.dart';
import 'package:helix_remote_domain/models.dart'
    show OrbitPackFailure, OrbitPackLimits;
import 'package:helix_remote/features/settings/application/about_providers.dart'
    show serverTitleProvider;
import 'package:helix_remote/features/settings/application/theme_packs.dart';
import 'package:orbit_ui/orbit_ui.dart'
    show ListStatus, ThemeGalleryModel, ThemePackItem, ThemePackPlace;

import '../support/orbit_theme.dart';
import '../support/pack_fixtures.dart';

/// Part C step 3 on the device: the pack folder and what may be drawn with it,
/// the publisher anchor, the theme library a pack joins, the download manager's
/// sentences, and the Storage page's number for the bytes.
void main() {
  late Directory tmp;

  setUpAll(makePublisherKeys);

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
        final store = ThemePackStore(trustedPublishers: {});
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

  group('a pack that is not a theme', () {
    // Part C step 5: the format carries ringtones too, and this store draws
    // themes. A sound pack is a real, signable pack that has nothing here to
    // show for itself - so it must be refused, not read, and never crash the
    // folder scan that runs at every app start.
    test(
      'a hosted sound pack is refused before its bytes are fetched',
      () async {
        final store = ThemePackStore(trustedPublishers: trusted);
        final pack = await signedSoundPack(by: publisherKey);
        final source = FakePackSource([pack]);
        await expectLater(
          store.install(source, 'chime'),
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
        expect(Directory('${await packsRoot()}/chime').existsSync(), isFalse);
      },
    );

    test('a sound pack already on the device is not read as a theme', () async {
      // Written into the folder by hand, because [ThemePackStore.install] no
      // longer lets one in: an older app, or a person's own copy of the bytes.
      final pack = await signedSoundPack(by: publisherKey);
      final root = await packsRoot();
      Directory('$root/chime/r1/files').createSync(recursive: true);
      File('$root/chime/r1/manifest.json').writeAsBytesSync(pack.manifestBytes);
      File(
        '$root/chime/r1/files/${pack.manifest.files.single.sha256}',
      ).writeAsBytesSync(pack.files.values.single);

      final store = ThemePackStore(trustedPublishers: trusted);
      expect(await store.installed(), isEmpty);
      expect(await store.load('chime'), isNull);
      expect(await store.themeTokens(), isEmpty);
      // The bytes stay: this store is not the one that plays them.
      expect(Directory('$root/chime/r1').existsSync(), isTrue);
    });

    test('the themes page says the pack is not one it can use', () async {
      final container = libraryContainer(
        source: FakePackSource([await signedSoundPack(by: publisherKey)]),
      );
      expect(
        await container.read(themePackActionsProvider).install('chime'),
        'That pack cannot be used: a kind of pack this app does not know.',
      );
      expect(
        container.read(themeLibraryProvider).containsKey('chime'),
        isFalse,
      );
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
        (await container.read(hostedPacksProvider.future)).rows.single.id,
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

  group('the theme table as packs', () {
    /// Part C step 8, end to end. `tool/theme_pack_tool.dart build` stages
    /// these nine documents into pack folders and signs them; this is the same
    /// nine through the app's own gate, the registries this build actually
    /// ships and a real download into the pack folder. A document that cannot
    /// come back as a theme is a generator bug arriving as a refused download,
    /// which is the failure this keeps out of a phone.
    ///
    /// `orbit` and `night` are not here: the app ships those two, so a pack
    /// would only be a second claim to a name the built-in owns.
    final ids =
        Directory('../packages/orbit_ui/assets/themes')
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .where((name) => name.endsWith('.json'))
            .map((name) => name.substring(0, name.length - 5))
            .where((id) => id != 'orbit' && id != 'night')
            .toList()
          ..sort();

    Future<Map<String, Object?>> document(String id) async =>
        jsonDecode(
              File(
                '../packages/orbit_ui/assets/themes/$id.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;

    test(
      'every theme the generator writes installs and draws itself',
      () async {
        expect(ids, isNotEmpty, reason: 'the theme folder was not found');
        final store = ThemePackStore(trustedPublishers: trusted);
        final docs = {for (final id in ids) id: await document(id)};
        final packs = <HostedPack>[
          for (final entry in docs.entries)
            await signedPack(
              by: publisherKey,
              id: entry.key,
              name: entry.value['name']! as String,
              theme: entry.value,
            ),
        ];
        final source = FakePackSource(packs);
        for (final pack in packs) {
          expect(
            await store.install(source, pack.manifest.id),
            PackChange.installed,
            reason: '${pack.manifest.id} was refused',
          );
        }

        final installed = await store.installed();
        expect(installed.map((p) => p.id).toSet(), docs.keys.toSet());
        // The name a person reads on the page is the signed document's own.
        for (final pack in installed) {
          expect(
            pack.name,
            docs[pack.id]!['name'],
            reason: '${pack.id} installed under the wrong name',
          );
        }

        // And each theme is the bytes it was published as, not a copy of the
        // first one: the same parse the built-ins go through, token for token.
        final tokens = await store.themeTokens();
        expect(tokens.keys, docs.keys.toSet());
        for (final id in docs.keys) {
          expect(
            tokens[id]!.meta.name,
            docs[id]!['name'],
            reason: '$id did not arrive as its own theme',
          );
        }
        expect(
          tokens.values.map((t) => t.meta.vibe).toSet().length,
          tokens.length,
          reason: 'two of the real themes share a vibe, so one is not itself',
        );
      },
    );
  });

  group('the More themes page', () {
    /// The page's model, with the server's list already in hand and kept alive
    /// for the test, the way the open page keeps it.
    Future<ThemeGalleryModel> gallery(ProviderContainer container) async {
      container.listen(hostedPacksProvider, (_, _) {});
      try {
        await container.read(hostedPacksProvider.future);
      } on Object {
        // A host that does not answer is what some of these tests are about.
      }
      return container.read(themeGalleryProvider);
    }

    test(
      'names a theme this phone holds, and an offer by nothing but its id',
      () async {
        final container = libraryContainer(
          source: FakePackSource([
            await signedPack(by: publisherKey),
            await signedPack(
              by: publisherKey,
              id: 'hologram',
              name: 'Hologram',
            ),
          ]),
          host: 'Helix Global',
        );
        expect(
          await container.read(themePackActionsProvider).install('synthwave'),
          'Synthwave theme downloaded.',
        );

        final model = await gallery(container);
        expect(model.host, 'Helix Global');
        expect(model.status, ListStatus.ready);
        final byId = themesById(model.themes);
        expect(byId.keys, ['orbit', 'night', 'synthwave', 'hologram']);

        expect(byId['orbit']!.name, 'Orbit');
        expect(byId['orbit']!.builtIn, isTrue);
        expect(byId['orbit']!.inUse, isTrue);
        expect(byId['night']!.name, 'Orbit Night');
        expect(byId['synthwave']!.place, ThemePackPlace.onThisPhone);
        // The name the publisher signed, not the folder it was downloaded into.
        expect(byId['synthwave']!.name, 'Synthwave');
        expect(byId['synthwave']!.detail, matches(RegExp(r' (B|KB|MB|GB)$')));

        // The list route carries no display name on purpose, so an offer is only
        // ever its id until the signed document arrives.
        expect(byId['hologram']!.place, ThemePackPlace.onTheServer);
        expect(byId['hologram']!.name, 'hologram');
        expect(byId['hologram']!.detail, endsWith('to download'));
      },
    );

    test('the theme on screen is the one marked in use, and Orbit is when a '
        'chosen pack went away', () async {
      final container = libraryContainer(
        source: FakePackSource([await signedPack(by: publisherKey)]),
      );
      final page = container.read(themePackPageProvider);

      expect(await page.use('night'), 'Orbit Night theme on');
      var byId = themesById((await gallery(container)).themes);
      expect(byId['night']!.inUse, isTrue);
      expect(byId['orbit']!.inUse, isFalse);

      expect(await page.get('synthwave'), 'Synthwave theme downloaded.');
      expect(await page.use('synthwave'), 'Synthwave theme on');
      expect(container.read(orbitTokensProvider).meta.name, 'Synthwave');

      expect(await page.delete('synthwave'), 'Synthwave theme deleted.');
      // The choice is kept for the next download; Orbit is on screen meanwhile.
      expect(container.read(themeChoiceProvider), 'synthwave');
      expect(container.read(orbitTokensProvider).meta.name, 'Orbit');
      byId = themesById((await gallery(container)).themes);
      expect(byId['orbit']!.inUse, isTrue);
      // The server still offers it, so it is back in the lower group.
      expect(byId['synthwave']!.place, ThemePackPlace.onTheServer);
    });

    test('a pack the server has revised is offered an update, not a second '
        'download', () async {
      final container = libraryContainer(
        source: FakePackSource([
          await signedPack(by: publisherKey),
          await signedPack(by: publisherKey, revision: 3, name: 'Synthwave 3'),
        ]),
      );
      final page = container.read(themePackPageProvider);
      // This device got r1 when that was all there was; the host now lists r3.
      expect(
        await container
            .read(themePackActionsProvider)
            .install('synthwave', revision: 1),
        'Synthwave theme downloaded.',
      );

      // One offer per id, the largest revision, and this device holds r1.
      var byId = themesById((await gallery(container)).themes);
      expect(byId['synthwave']!.place, ThemePackPlace.onThisPhone);
      expect(byId['synthwave']!.updateAvailable, isTrue);

      expect(await page.update('synthwave'), 'Synthwave 3 theme downloaded.');
      byId = themesById((await gallery(container)).themes);
      expect(byId['synthwave']!.name, 'Synthwave 3');
      expect(byId['synthwave']!.updateAvailable, isFalse);
      expect(byId.keys, ['orbit', 'night', 'synthwave']);
    });

    test('a download waits its own row, and no other', () async {
      final source = GatedPackSource(await signedPack(by: publisherKey));
      final container = libraryContainer(source: source);
      final page = container.read(themePackPageProvider);
      final pending = page.get('synthwave');
      await pumpEventQueue();

      expect(container.read(packBusyProvider), 'synthwave');
      final byId = themesById((await gallery(container)).themes);
      expect(byId['synthwave']!.busy, isTrue);
      // Still an offer: nothing is a theme until the gate has passed.
      expect(byId['synthwave']!.place, ThemePackPlace.onTheServer);
      expect(byId['orbit']!.busy, isFalse);

      source.open();
      expect(await pending, 'Synthwave theme downloaded.');
      expect(container.read(packBusyProvider), isNull);
      expect(
        themesById((await gallery(container)).themes)['synthwave']!.busy,
        isFalse,
      );
    });

    test(
      'a refused pack is said in the format\'s own words and stays an offer',
      () async {
        // Its manifest is signed by a publisher this build trusts, so the page
        // can vouch for the offer; the bytes under it are not what that
        // manifest names, so the download is refused.
        final container = libraryContainer(
          source: FakePackSource([
            await signedPack(by: publisherKey).then((p) => p.servedAs(junk)),
          ]),
        );
        final said = await container
            .read(themePackPageProvider)
            .get('synthwave');
        expect(said, contains('cannot be used'));
        expect(said, isNot(contains('synthwave'))); // never quoted back
        final byId = themesById((await gallery(container)).themes);
        expect(byId['synthwave']!.place, ThemePackPlace.onTheServer);
        expect(byId['synthwave']!.busy, isFalse);
      },
    );

    test(
      'an offer this build cannot check is never listed, and the page says why',
      () async {
        // The shipped anchor trusts nobody, so every pack on every server is
        // this: a page that reads its own folder, and no downloads.
        final container = libraryContainer(
          source: FakePackSource([await signedPack(by: otherKey)]),
        );
        final model = await gallery(container);
        expect(model.status, ListStatus.ready);
        expect(themesById(model.themes).keys, ['orbit', 'night']);
        expect(model.emptyNote, contains('cannot check'));
      },
    );

    test('a sound pack on the server is not offered as a theme', () async {
      // One folder holds both kinds and the list route says nothing about
      // which a row is, so the signed manifest decides it here.
      final container = libraryContainer(
        source: FakePackSource([await signedSoundPack(by: publisherKey)]),
      );
      final model = await gallery(container);
      expect(themesById(model.themes).keys, ['orbit', 'night']);
      expect(model.emptyNote, contains('sound'));
    });

    test('a server that cannot be reached still shows this phone\'s themes, '
        'and asks again', () async {
      final source = OfflinePackSource();
      final container = libraryContainer(source: source, host: 'My server');
      final page = container.read(themePackPageProvider);

      var model = await gallery(container);
      expect(source.listCalls, 1);
      expect(model.status, ListStatus.failed);
      expect(model.error, 'That did not work. Try again.');
      expect(model.host, 'My server');
      expect(themesById(model.themes).keys, ['orbit', 'night']);

      page.retry();
      model = await gallery(container);
      expect(source.listCalls, 2);
      expect(model.status, ListStatus.failed);
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

// The signed packs, the fake hosts and the keys are in `../support/pack_fixtures.dart`, shared with the sounds store's tests.

/// A container with the themes [main] would seed, this test's anchor, and one
/// temp folder to write into.
ProviderContainer libraryContainer({PackSource? source, String? host}) {
  final container = ProviderContainer(
    overrides: [
      orbitThemeLibraryProvider.overrideWithValue(orbitTestThemes),
      initialThemeIdProvider.overrideWithValue(defaultThemeId),
      downloadedThemesAtStartupProvider.overrideWithValue(const {}),
      packPublishersProvider.overrideWithValue(trusted),
      if (source != null) packSourceProvider.overrideWithValue(source),
      if (host != null) serverTitleProvider.overrideWithValue(host),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// The page's rows, by theme id, in the order the page lists them.
Map<String, ThemePackItem> themesById(List<ThemePackItem> items) => {
  for (final item in items) item.id: item,
};
