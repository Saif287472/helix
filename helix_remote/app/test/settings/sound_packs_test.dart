import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/sounds/orbit_ringtones.dart';
import 'package:helix_remote/core/theme/orbit_app_theme.dart';
import 'package:helix_remote/core/theme/orbit_packs.dart';
import 'package:helix_remote/features/settings/application/about_providers.dart'
    show serverTitleProvider;
import 'package:helix_remote/features/settings/application/sound_packs.dart';
import 'package:helix_remote/features/settings/application/theme_packs.dart'
    show packBusyProvider, packSourceProvider;
import 'package:orbit_ui/orbit_ui.dart'
    show
        ListStatus,
        RingtoneGalleryItem,
        RingtoneGalleryModel,
        ThemePackPlace,
        phoneRingtoneId,
        phoneRingtoneLabel;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart'
    show getExternalStorageDirectory;

import '../support/pack_fixtures.dart';

/// Part C step 5 on the device: the Ringtones page's model and verbs, the choice
/// the ringer will read, and the one line Settings > Notifications shows for it.
///
/// The folder, the gate and the refused bytes are `orbit_sounds_test.dart`'s;
/// what is here is the layer a person taps.
void main() {
  late Directory tmp;

  setUpAll(makePublisherKeys);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('helix_ringtones');
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

  /// A [RingtoneGalleryModel]'s rows, by the id the page rings with.
  Map<String, RingtoneGalleryItem> rowsById(List<RingtoneGalleryItem> rows) => {
    for (final row in rows) row.id: row,
  };

  /// The page's model, with the server's list already in hand and kept alive
  /// for the test, the way the open page keeps it.
  Future<RingtoneGalleryModel> gallery(ProviderContainer container) async {
    container.listen(hostedSoundsProvider, (_, _) {});
    try {
      await container.read(hostedSoundsProvider.future);
    } on Object {
      // A host that does not answer is what some of these tests are about.
    }
    return container.read(ringtoneGalleryProvider);
  }

  group('the sound folder read through the page', () {
    test('a signed sound pack arrives, and the pages see it', () async {
      final container = soundContainer(
        source: FakePackSource([await signedSoundPack(by: publisherKey)]),
      );
      expect(
        await container.read(soundPackActionsProvider).install('chime'),
        'chime ringtone downloaded.',
      );
      expect(
        (await container.read(installedSoundsProvider.future)).single.id,
        'chime',
      );
      expect(
        (await container.read(hostedSoundsProvider.future)).rows.single.id,
        'chime',
      );
      expect(
        await container.read(soundPackActionsProvider).install('chime'),
        'Already up to date.',
      );
    });

    test('a theme pack on the server is refused as a ringtone', () async {
      final source = FakePackSource([await signedPack(by: publisherKey)]);
      final container = soundContainer(source: source);
      final said = await container.read(ringtonePageProvider).get('synthwave');
      expect(said, contains('cannot be used'));
      expect(await container.read(installedSoundsProvider.future), isEmpty);
      // Its bytes were never fetched: the signed manifest decided the kind.
      expect(source.fetched, isEmpty);
    });

    test('bytes the host swapped after signing are refused', () async {
      final container = soundContainer(
        source: FakePackSource([
          await signedSoundPack(
            by: publisherKey,
          ).then((pack) => pack.servedAs(junk)),
        ]),
      );
      final said = await container.read(ringtonePageProvider).get('chime');
      expect(said, contains('cannot be used'));
      expect(await container.read(installedSoundsProvider.future), isEmpty);
    });

    test(
      'deleting a sound pack says it is gone, and twice says so once',
      () async {
        final container = soundContainer(
          source: FakePackSource([await signedSoundPack(by: publisherKey)]),
        );
        final actions = container.read(soundPackActionsProvider);
        await actions.install('chime');
        expect(await actions.remove('chime'), 'chime ringtone deleted.');
        expect(
          await actions.remove('chime'),
          'That ringtone is not on this phone.',
        );
      },
    );
  });

  group('the choice', () {
    test(
      'a held sound is chosen, and the phone\'s own un-chooses it',
      () async {
        final container = soundContainer(
          source: FakePackSource([await signedSoundPack(by: publisherKey)]),
        );
        final actions = container.read(soundPackActionsProvider);
        await actions.install('chime');
        final store = container.read(deviceSettingsStoreProvider);

        expect(await store.readRingtone(), isNull);
        expect(
          await container.read(ringtonePageProvider).use('chime'),
          'chime ringtone on',
        );
        expect(await store.readRingtone(), 'chime');
        expect(container.read(ringtoneChoiceProvider).value, 'chime');

        expect(
          await container.read(ringtonePageProvider).use(phoneRingtoneId),
          '$phoneRingtoneLabel on',
        );
        expect(await store.readRingtone(), isNull);
      },
    );

    test('a sound this device does not hold is refused the choice', () async {
      final container = soundContainer();
      final said = await container.read(ringtonePageProvider).use('chime');
      expect(said, 'That ringtone is not on this phone.');
      expect(
        await container.read(deviceSettingsStoreProvider).readRingtone(),
        isNull,
      );
    });

    test(
      'the ringtone and the theme are the device\'s, and keep each other',
      () async {
        // One file holds both choices, so choosing one must not forget the
        // other.
        final store = const FileDeviceSettingsStore();
        await store.writeRingtone('chime');
        await store.writeTheme('night');
        expect(await store.readRingtone(), 'chime');
        expect(await store.readTheme(), 'night');
        await store.writeRingtone(null);
        expect(await store.readRingtone(), isNull);
        expect(await store.readTheme(), 'night');
      },
    );

    test(
      'a choice that names no pack this device holds is still a choice',
      () async {
        final container = soundContainer(
          source: FakePackSource([await signedSoundPack(by: publisherKey)]),
        );
        final actions = container.read(soundPackActionsProvider);
        await actions.install('chime');
        await container.read(ringtonePageProvider).use('chime');
        expect(await actions.remove('chime'), 'chime ringtone deleted.');

        // The choice outlives the pack, as a chosen theme's does: re-downloading
        // brings the ringtone back. Meanwhile the phone's own sound answers.
        expect(container.read(ringtoneChoiceProvider).value, 'chime');
        expect(
          rowsById(
            (await gallery(container)).ringtones,
          )[phoneRingtoneId]!.inUse,
          isTrue,
        );
        expect(container.read(ringtoneLabelProvider), phoneRingtoneLabel);
      },
    );

    test('a re-download that cannot be set up keeps the phone\'s own sound '
        'chosen', () async {
      // Android's copy lives outside the app folder, which a test can only
      // reach through the platform hooks.
      final external = Directory.systemTemp.createTempSync('helix_ringtones');
      addTearDown(() {
        AppPaths.isAndroid = () => Platform.isAndroid;
        AppPaths.externalStorageDirectory = getExternalStorageDirectory;
        external.deleteSync(recursive: true);
      });
      AppPaths.isAndroid = () => true;
      AppPaths.externalStorageDirectory = () async => external;

      final container = soundContainer(
        source: FakePackSource([
          await signedSoundPack(by: publisherKey),
          await signedSoundPack(by: publisherKey, revision: 2),
        ]),
      );
      final actions = container.read(soundPackActionsProvider);
      await actions.install('chime', revision: 1);
      await container.read(ringtonePageProvider).use('chime');
      expect(container.read(ringtoneLabelProvider), 'chime');

      // The folder Android would read the new copy from cannot be made (storage
      // full, or a file where the folder belongs).
      final ringtoneDir = Directory(p.join(external.path, 'ringtones'));
      ringtoneDir.deleteSync(recursive: true);
      File(ringtoneDir.path).writeAsStringSync('not a dir');

      expect(
        await actions.install('chime'),
        'chime ringtone downloaded, but it could not be set up on this phone.',
      );
      expect(container.read(ringtoneLabelProvider), phoneRingtoneLabel);
      expect(
        await container.read(deviceSettingsStoreProvider).readRingtone(),
        isNull,
      );
    });
  });

  group('the Ringtones page', () {
    test(
      'the phone\'s own sound heads the list, and the chosen one is in use',
      () async {
        final container = soundContainer(
          source: FakePackSource([await signedSoundPack(by: publisherKey)]),
          host: 'My server',
        );
        var model = await gallery(container);
        var byId = rowsById(model.ringtones);
        expect(model.host, 'My server');
        expect(byId.keys.first, phoneRingtoneId);
        expect(byId.keys.last, 'chime');
        expect(byId[phoneRingtoneId]!.phone, isTrue);
        expect(byId[phoneRingtoneId]!.inUse, isTrue);
        expect(byId['chime']!.place, ThemePackPlace.onTheServer);
        expect(byId['chime']!.name, 'chime');
        expect(byId['chime']!.detail, endsWith('to download'));

        await container.read(ringtonePageProvider).get('chime');
        await container.read(ringtonePageProvider).use('chime');
        model = await gallery(container);
        byId = rowsById(model.ringtones);
        expect(byId['chime']!.place, ThemePackPlace.onThisPhone);
        expect(byId['chime']!.inUse, isTrue);
        expect(byId[phoneRingtoneId]!.inUse, isFalse);
        expect(container.read(ringtoneLabelProvider), 'chime');
      },
    );

    test('a pack the server has revised is offered an update, not a second '
        'download', () async {
      final container = soundContainer(
        source: FakePackSource([
          await signedSoundPack(by: publisherKey),
          await signedSoundPack(by: publisherKey, revision: 3),
        ]),
      );
      await container
          .read(soundPackActionsProvider)
          .install('chime', revision: 1);
      var byId = rowsById((await gallery(container)).ringtones);
      expect(byId['chime']!.place, ThemePackPlace.onThisPhone);
      expect(byId['chime']!.updateAvailable, isTrue);

      expect(
        await container.read(ringtonePageProvider).update('chime'),
        'chime ringtone downloaded.',
      );
      byId = rowsById((await gallery(container)).ringtones);
      expect(byId['chime']!.updateAvailable, isFalse);
      expect(
        (await container.read(installedSoundsProvider.future)).single.revision,
        3,
      );
    });

    test('a download waits its own row, and no other', () async {
      final source = GatedPackSource(await signedSoundPack(by: publisherKey));
      final container = soundContainer(source: source);
      final page = container.read(ringtonePageProvider);
      final pending = page.get('chime');
      await pumpEventQueue();

      expect(container.read(packBusyProvider), 'chime');
      final byId = rowsById((await gallery(container)).ringtones);
      expect(byId['chime']!.busy, isTrue);
      expect(byId[phoneRingtoneId]!.busy, isFalse);

      source.open();
      expect(await pending, 'chime ringtone downloaded.');
      expect(container.read(packBusyProvider), isNull);
    });

    test('an offer this build cannot check is never listed, and the page says '
        'why', () async {
      final container = soundContainer(
        source: FakePackSource([await signedSoundPack(by: otherKey)]),
      );
      final model = await gallery(container);
      expect(model.status, ListStatus.ready);
      expect(rowsById(model.ringtones).length, BuiltInRingtones.all.length + 1);
      expect(model.emptyNote, contains('cannot check'));
    });

    test('a theme pack on the server is not offered as a ringtone', () async {
      final container = soundContainer(
        source: FakePackSource([await signedPack(by: publisherKey)]),
      );
      final model = await gallery(container);
      expect(rowsById(model.ringtones).length, BuiltInRingtones.all.length + 1);
      expect(model.emptyNote, contains('sound pack'));
    });

    test(
      'a server that cannot be reached still shows this phone\'s sounds',
      () async {
        final source = OfflinePackSource();
        final container = soundContainer(source: source, host: 'My server');
        final page = container.read(ringtonePageProvider);

        var model = await gallery(container);
        expect(source.listCalls, 1);
        expect(model.status, ListStatus.failed);
        expect(model.error, 'That did not work. Try again.');
        expect(
          rowsById(model.ringtones).length,
          BuiltInRingtones.all.length + 1,
        );

        page.retry();
        model = await gallery(container);
        expect(source.listCalls, 2);
        expect(model.status, ListStatus.failed);
      },
    );
  });

  group('the sounds this build carries', () {
    test(
      'they sit after the phone\'s own, before anything downloaded',
      () async {
        final container = soundContainer(
          source: FakePackSource([await signedSoundPack(by: publisherKey)]),
        );
        await container.read(soundPackActionsProvider).install('chime');

        final rows = (await gallery(container)).ringtones;
        expect(rows.first.id, phoneRingtoneId);
        expect(
          rows.skip(1).take(BuiltInRingtones.all.length).map((row) => row.id),
          BuiltInRingtones.all.map((ringtone) => ringtone.id),
        );
        expect(rows.last.id, 'chime');
        expect(rows[1].name, 'Helix Default');
        expect(rows[1].builtIn, isTrue);
        expect(rows[1].inUse, isFalse);
      },
    );

    test('choosing one names it on the Notifications row', () async {
      final container = soundContainer(source: FakePackSource([]));
      expect(
        await container.read(ringtonePageProvider).use('orbit.velvet-tone'),
        'Velvet Tone ringtone on',
      );
      expect(container.read(ringtoneChoiceProvider).value, 'orbit.velvet-tone');
      expect(container.read(ringtoneLabelProvider), 'Velvet Tone');

      final byId = rowsById((await gallery(container)).ringtones);
      expect(byId['orbit.velvet-tone']!.inUse, isTrue);
      expect(byId[phoneRingtoneId]!.inUse, isFalse);
    });

    test('a pack cannot take a built-in sound\'s name', () async {
      final container = soundContainer(
        source: FakePackSource([
          await signedSoundPack(by: publisherKey, id: 'orbit.helix-default'),
        ]),
      );
      expect(
        (await container.read(hostedSoundsProvider.future)).rows.single.id,
        'orbit.helix-default',
      );
      final named = rowsById((await gallery(container)).ringtones);
      expect(named.length, BuiltInRingtones.all.length + 1);
      expect(named['orbit.helix-default']!.name, 'Helix Default');
      expect(named['orbit.helix-default']!.builtIn, isTrue);
    });
  });

  group('the Notifications row', () {
    test('it names the phone\'s own sound until one is chosen', () async {
      final container = soundContainer(
        source: FakePackSource([await signedSoundPack(by: publisherKey)]),
      );
      expect(container.read(ringtoneLabelProvider), phoneRingtoneLabel);
      final actions = container.read(soundPackActionsProvider);
      await actions.install('chime');
      await container.read(ringtoneChoiceProvider.notifier).choose('chime');
      expect(container.read(ringtoneLabelProvider), 'chime');
      await container.read(ringtoneChoiceProvider.notifier).choose('');
      expect(container.read(ringtoneLabelProvider), phoneRingtoneLabel);
    });

    test('a device with no sound packs still has a ringtone row', () async {
      final container = soundContainer(source: OfflinePackSource());
      final model = await gallery(container);
      expect(model.ringtones.first.phone, isTrue);
      expect(model.ringtones.first.inUse, isTrue);
    });
  });
}

ProviderContainer soundContainer({
  PackSource? source,
  String? host,
  Map<String, List<int>>? publishers,
}) {
  final container = ProviderContainer(
    overrides: [
      packPublishersProvider.overrideWithValue(publishers ?? trusted),
      if (source != null) packSourceProvider.overrideWithValue(source),
      if (host != null) serverTitleProvider.overrideWithValue(host),
    ],
  );
  addTearDown(container.dispose);
  return container;
}
