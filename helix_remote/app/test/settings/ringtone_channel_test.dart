import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/sounds/orbit_ringtones.dart';
import 'package:helix_remote/core/sounds/orbit_sounds.dart';
import 'package:helix_remote/core/theme/orbit_app_theme.dart'
    show FileDeviceSettingsStore;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart'
    show getExternalStorageDirectory;

import '../support/pack_fixtures.dart';

/// Part C step 5's second half: the copy Android's system rings with, the
/// provider that serves it, and the channel that names it.
///
/// `flutter test` runs on Windows, so the two platform hooks
/// ([AppPaths.isAndroid], [AppPaths.externalStorageDirectory]) stand in for
/// the phone. What they exercise is the code that runs there, against folders
/// a test can see.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory external;

  setUpAll(makePublisherKeys);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('helix_ringtone_app');
    external = Directory.systemTemp.createTempSync('helix_ringtone_ext');
    AppPaths.localDataDirectory = () async => tmp;
    AppPaths.privateDataDirectory = () async => tmp;
    AppPaths.isWindows = () => true;
    AppPaths.isAndroid = () => true;
    AppPaths.externalStorageDirectory = () async => external;
  });

  tearDown(() {
    AppPaths.localDataDirectory = () async => throw StateError('unset');
    AppPaths.privateDataDirectory = () async => throw StateError('unset');
    AppPaths.isWindows = () => Platform.isWindows;
    AppPaths.isAndroid = () => Platform.isAndroid;
    AppPaths.externalStorageDirectory = getExternalStorageDirectory;
    tmp.deleteSync(recursive: true);
    external.deleteSync(recursive: true);
  });

  File copyOf(String id, String suffix) =>
      File(p.join(external.path, 'ringtones', '$id$suffix'));

  /// A signed sound pack installed on this device, the way the page downloads
  /// one, read back through the gate.
  Future<InstalledSound> installSound(String id, {int? fileBytes}) async {
    final store = SoundPackStore(trustedPublishers: trusted);
    final pack = await signedSoundPack(
      by: publisherKey,
      id: id,
      fileBytes: fileBytes,
    );
    await store.install(FakePackSource([pack]), id);
    return (await store.load(id))!;
  }

  group('the name and address a ringtone rings on', () {
    test('the channel id is the pack id and the audio kind', () {
      expect(
        Ringtones.channelId('chime', '.m4a'),
        'helix_incoming_calls_ringtone.chime.m4a',
      );
      expect(
        Ringtones.channelId('chime', '.m4a'),
        startsWith(Ringtones.channelPrefix),
      );
    });

    test('the address is the ringtone provider over the same name', () {
      expect(
        Ringtones.uri('chime', '.m4a'),
        'content://com.helix.remote.ringtones/ringtones/chime.m4a',
      );
    });
  });

  group('the provider the system reads a copy through', () {
    String manifest() =>
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    String provider() => File(
      'android/app/src/main/kotlin/com/helix/remote/RingtoneProvider.kt',
    ).readAsStringSync();

    test('is the app\'s own provider, under the authority Dart builds', () {
      final block = RegExp(r'<provider\b[\s\S]*?(?:/>|</provider>)')
          .allMatches(manifest())
          .map((match) => match.group(0)!)
          .firstWhere(
            (block) =>
                block.contains('android:authorities="${Ringtones.authority}"'),
            orElse: () => fail('no provider under ${Ringtones.authority}'),
          );
      expect(block, contains('android:name=".RingtoneProvider"'));
      // The system opens the URI without a per-URI grant, so the provider
      // must be exported - and that is exactly why it cannot be androidx's
      // FileProvider, which refuses to start when exported (2026-10-23).
      expect(block, contains('android:exported="true"'));
      expect(block, isNot(contains('androidx.core.content.FileProvider')));
    });

    test('serves the ringtone copies and nothing else of the app', () {
      final source = provider();
      expect(source, contains('getExternalFilesDir("ringtones")'));
      // One file name directly inside that folder: no nesting, no traversal,
      // and nothing that escapes it through a link.
      expect(source, contains('uri.pathSegments'));
      expect(source, contains('canonicalFile'));
    });
  });

  group('the copy the system rings with', () {
    test('publishing writes the pack\'s bytes under its id and kind', () async {
      final sound = await installSound('chime');
      expect(await Ringtones.publish(sound), isTrue);

      final copy = copyOf('chime', '.m4a');
      expect(await copy.exists(), isTrue);
      expect(await copy.readAsBytes(), await sound.file.readAsBytes());
      // Nothing half-written is left for a call to find.
      expect(File('${copy.path}.part').existsSync(), isFalse);
    });

    test(
      'publishing another ringtone leaves only the one that rings',
      () async {
        final chime = await installSound('chime');
        final bell = await installSound('bell', fileBytes: 640);
        expect(await Ringtones.publish(chime), isTrue);
        expect(await Ringtones.publish(bell), isTrue);

        final left = [
          for (final entry in Directory(
            p.join(external.path, 'ringtones'),
          ).listSync())
            if (entry is File) p.basename(entry.path),
        ];
        expect(left, ['bell.m4a']);
      },
    );

    test('forget removes one ringtone\'s copies, or every copy', () async {
      final chime = await installSound('chime');
      final bell = await installSound('bell', fileBytes: 640);
      await Ringtones.publish(chime);
      await Ringtones.publish(bell);
      // Both at once, as an update that changed the file kind would leave them.
      copyOf('chime', '.mp3').writeAsBytesSync([1, 2, 3]);

      await Ringtones.forget(id: 'chime');
      expect(copyOf('chime', '.m4a').existsSync(), isFalse);
      expect(copyOf('chime', '.mp3').existsSync(), isFalse);
      expect(copyOf('bell', '.m4a').existsSync(), isTrue);

      await Ringtones.forget();
      expect(copyOf('bell', '.m4a').existsSync(), isFalse);
    });

    test(
      'a storage that cannot be written refuses the copy, not the call',
      () async {
        final sound = await installSound('chime');
        // A file where the folder would go: the platform cannot make it.
        File(p.join(external.path, 'ringtones')).writeAsStringSync('not a dir');

        expect(await Ringtones.publish(sound), isFalse);
        expect(await Ringtones.chosen(publishers: trusted), isNull);
      },
    );

    test('a device without external storage has no copy to offer', () async {
      final sound = await installSound('chime');
      AppPaths.externalStorageDirectory = () async => null;

      expect(await Ringtones.publish(sound), isFalse);
      expect(await Ringtones.chosen(publishers: trusted), isNull);
    });

    test('off Android nothing is copied, and nothing is chosen', () async {
      final sound = await installSound('chime');
      await Ringtones.publish(sound);
      await const FileDeviceSettingsStore().writeRingtone('chime');
      AppPaths.isAndroid = () => false;

      expect(await Ringtones.publish(sound), isTrue);
      expect(copyOf('chime', '.m4a').existsSync(), isTrue);
      await Ringtones.forget();
      expect(copyOf('chime', '.m4a').existsSync(), isTrue);
      expect(await Ringtones.chosen(publishers: trusted), isNull);
    });
  });

  group('what the next call rings with', () {
    test(
      'a chosen pack is the ringtone, by its id, kind and address',
      () async {
        final sound = await installSound('chime');
        await Ringtones.publish(sound);
        await const FileDeviceSettingsStore().writeRingtone('chime');

        final ringtone = await Ringtones.chosen(publishers: trusted);
        expect(ringtone, isNotNull);
        expect(ringtone!.id, 'chime');
        expect(ringtone.name, 'chime');
        expect(ringtone.channelId, Ringtones.channelId('chime', '.m4a'));
        expect(ringtone.uri, Ringtones.uri('chime', '.m4a'));
      },
    );

    test('no choice, no pack, or no copy is the phone\'s own sound', () async {
      // Nothing chosen.
      expect(await Ringtones.chosen(publishers: trusted), isNull);

      // A choice whose pack this device does not hold.
      await const FileDeviceSettingsStore().writeRingtone('chime');
      expect(await Ringtones.chosen(publishers: trusted), isNull);

      // A held pack with no copy the system could read.
      final sound = await installSound('chime');
      expect(await Ringtones.chosen(publishers: trusted), isNull);

      // The copy, and then a pack deleted from under the choice.
      await Ringtones.publish(sound);
      expect(await Ringtones.chosen(publishers: trusted), isNotNull);
      await SoundPackStore(trustedPublishers: trusted).remove('chime');
      expect(await Ringtones.chosen(publishers: trusted), isNull);
    });

    test('a pack this build does not trust is not a ringtone', () async {
      final sound = await installSound('chime');
      await Ringtones.publish(sound);
      await const FileDeviceSettingsStore().writeRingtone('chime');

      expect(
        await Ringtones.chosen(publishers: {'helix': otherKey.publicKey}),
        isNull,
      );
    });

    test(
      'reading a choice that is not there leaves no folder behind',
      () async {
        expect(await Ringtones.chosen(publishers: trusted), isNull);
        expect(
          Directory(p.join(external.path, 'ringtones')).existsSync(),
          isFalse,
        );

        await Ringtones.forget();
        expect(
          Directory(p.join(external.path, 'ringtones')).existsSync(),
          isFalse,
        );
      },
    );
  });

  group('the sounds this build carries', () {
    test('every one loads, and no id or name is used twice', () async {
      final ids = <String>{};
      final names = <String>{};
      for (final ringtone in BuiltInRingtones.all) {
        expect(ids.add(ringtone.id), isTrue, reason: '${ringtone.id} twice');
        expect(
          names.add(ringtone.name),
          isTrue,
          reason: '${ringtone.name} twice',
        );
        expect(ringtone.suffix, '.mp3');
        final data = await rootBundle.load(ringtone.asset);
        expect(
          data.lengthInBytes,
          greaterThan(16 * 1024),
          reason: '${ringtone.asset} is missing or empty',
        );
      }
      // The owner's set from Helix Local, with its three names for one file
      // (Helix Default, Classic Call, Soft Whisper) listed once.
      expect(BuiltInRingtones.all.length, 10);
    });

    test('a built-in is copied from the build and rings', () async {
      final ringtone = BuiltInRingtones.byId('orbit.crystal-chime')!;
      expect(await Ringtones.publishBuiltIn(ringtone), isTrue);

      final copy = copyOf(ringtone.id, '.mp3');
      expect(await copy.exists(), isTrue);
      expect(File('${copy.path}.part').existsSync(), isFalse);
      final asset = await rootBundle.load(ringtone.asset);
      expect(
        await copy.readAsBytes(),
        asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
      );

      await const FileDeviceSettingsStore().writeRingtone(ringtone.id);
      final chosen = await Ringtones.chosen(publishers: trusted);
      expect(chosen, isNotNull);
      expect(chosen!.id, 'orbit.crystal-chime');
      // The system's own settings name it as the page does, not by its id.
      expect(chosen.name, 'Crystal Chime');
      expect(
        chosen.channelId,
        Ringtones.channelId('orbit.crystal-chime', '.mp3'),
      );
      expect(chosen.uri, Ringtones.uri('orbit.crystal-chime', '.mp3'));
    });

    test('a built-in replaces the copy a pack left behind', () async {
      final sound = await installSound('chime');
      await Ringtones.publish(sound);
      final ringtone = BuiltInRingtones.byId('orbit.echo-drop')!;

      expect(await Ringtones.publishBuiltIn(ringtone), isTrue);
      expect(copyOf('chime', '.m4a').existsSync(), isFalse);
      expect(copyOf(ringtone.id, '.mp3').existsSync(), isTrue);
    });

    test('a built-in choice with no copy is the phone\'s own sound', () async {
      await const FileDeviceSettingsStore().writeRingtone('orbit.velvet-tone');
      expect(await Ringtones.chosen(publishers: trusted), isNull);
    });

    test('off Android a built-in is not copied', () async {
      final ringtone = BuiltInRingtones.all.first;
      AppPaths.isAndroid = () => false;

      expect(await Ringtones.publishBuiltIn(ringtone), isTrue);
      expect(copyOf(ringtone.id, '.mp3').existsSync(), isFalse);
    });
  });
}
