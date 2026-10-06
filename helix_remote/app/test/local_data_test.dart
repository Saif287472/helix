import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/notifications/call_notifications.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/platform/engine_lease.dart';
import 'package:helix_remote/core/platform/picker_cleanup.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show NotificationVisibility;

/// M4, M5 and the lows about what is kept on disk and who may open it.
void main() {
  late Directory tmp;
  late Directory local;
  late Directory private;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('helix_local_data');
    local = Directory('${tmp.path}/local')..createSync();
    private = Directory('${tmp.path}/private')..createSync();
    AppPaths.localDataDirectory = () async => local;
    AppPaths.privateDataDirectory = () async => private;
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() {
    AppPaths.localDataDirectory = () async => throw StateError('unset');
    AppPaths.isWindows = () => Platform.isWindows;
    tmp.deleteSync(recursive: true);
  });

  group('where the data lives (M4)', () {
    test(
      'Windows keeps it in the local app-data folder, not Documents',
      () async {
        AppPaths.isWindows = () => true;
        final db = await AppPaths.databaseFile();
        expect(
          db.path.replaceAll(r'\', '/'),
          startsWith('${local.path.replaceAll(r'\', '/')}/helix_remote/'),
        );
        expect(db.path, isNot(contains('private')));
      },
    );

    test('Android keeps its private files directory', () async {
      AppPaths.isWindows = () => false;
      final db = await AppPaths.databaseFile();
      expect(db.path.replaceAll(r'\', '/'), contains('/private/helix_remote/'));
    });
  });

  group('plaintext leftovers (M5)', () {
    Future<File> seed() async {
      AppPaths.isWindows = () => false;
      final avatar = await AppPaths.profileAvatarFile();
      avatar.writeAsBytesSync([1, 2, 3]);
      final attachments = await AppPaths.attachmentCache();
      File('${attachments.path}/photo.jpg').writeAsBytesSync([9]);
      (await AppPaths.databaseFile()).writeAsBytesSync([7]);
      return avatar;
    }

    test(
      'wiping removes the avatar and the attachments, keeps the database',
      () async {
        final avatar = await seed();
        await AppPaths.wipeLocalFiles();
        expect(avatar.existsSync(), isFalse);
        expect((await AppPaths.attachmentCache()).listSync(), isEmpty);
        expect((await AppPaths.databaseFile()).existsSync(), isTrue);
      },
    );

    test('the destructive reset wipes the database too', () async {
      await seed();
      await AppPaths.wipeLocalFiles(includeDatabase: true);
      expect((await AppPaths.databaseFile()).existsSync(), isFalse);
    });

    test(
      'the destructive reset finishes when the runtime already failed',
      () async {
        final avatar = await seed();
        var pickerCleared = 0;
        PickerTemporaryFiles.clearer = () async => pickerCleared++;
        addTearDown(() => PickerTemporaryFiles.clearer = () async {});
        final container = ProviderContainer(
          overrides: [runtimeFactoryProvider.overrideWithValue(_Broken())],
        );
        addTearDown(container.dispose);
        container
            .read(serverUrlProvider.notifier)
            .use(Uri.parse('https://chat.example.org'));
        await expectLater(
          container.read(runtimeProvider.future),
          throwsA(isA<StateError>()),
        );

        await container.read(destructiveResetProvider)();

        expect(avatar.existsSync(), isFalse);
        expect((await AppPaths.databaseFile()).existsSync(), isFalse);
        expect(container.read(serverUrlProvider), isNull);
        expect(pickerCleared, 1);
      },
    );

    test('the picker clearer never throws', () async {
      PickerTemporaryFiles.clearer = () async => throw StateError('no plugin');
      addTearDown(() => PickerTemporaryFiles.clearer = () async {});
      await PickerTemporaryFiles.clear();
    });
  });

  group('one engine at a time', () {
    late File file;
    var now = DateTime(2026, 1, 1, 12);
    Future<EngineLease> take(
      LeaseRole role, {
      int processId = 100,
      Duration wait = Duration.zero,
    }) => EngineLease.acquire(
      file,
      role: role,
      now: () => now,
      processId: processId,
      waitForHeadless: wait,
      settle: Duration.zero,
    );

    setUp(() {
      file = File('${tmp.path}/db.lease');
      now = DateTime(2026, 1, 1, 12);
    });

    test(
      'the push isolate stands aside while the app has the database',
      () async {
        final app = await take(LeaseRole.foreground);
        await expectLater(
          take(LeaseRole.headless),
          throwsA(isA<EngineAlreadyRunning>()),
        );
        await app.release();
        final push = await take(LeaseRole.headless);
        await push.release();
      },
    );

    test('a second window in another process is refused', () async {
      final first = await take(LeaseRole.foreground);
      await expectLater(
        take(LeaseRole.foreground, processId: 200),
        throwsA(isA<EngineAlreadyRunning>()),
      );
      await first.release();
    });

    test(
      'a runtime in the same process replaces the one that is closing',
      () async {
        final old = await take(LeaseRole.foreground);
        final next = await take(LeaseRole.foreground);
        await old.release(); // no longer the owner: leaves the file alone
        expect(file.existsSync(), isTrue);
        await next.release();
        expect(file.existsSync(), isFalse);
      },
    );

    test('the app takes over from a push pass that never ends', () async {
      await take(LeaseRole.headless);
      final app = await take(LeaseRole.foreground);
      await app.release();
    });

    test('a dead lease is taken over once its heartbeat is old', () async {
      await take(LeaseRole.foreground, processId: 200);
      now = now.add(EngineLease.staleAfter + const Duration(seconds: 1));
      final lease = await take(LeaseRole.headless);
      await lease.release();
    });

    test('a corrupt lease file does not lock anybody out', () async {
      file.writeAsStringSync('not json');
      final lease = await take(LeaseRole.foreground);
      await lease.release();
    });
  });

  test('the shared-link intent filter matches /open exactly, not a prefix', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:path="/open"'));
    expect(manifest, contains('android:path="/open/"'));
    expect(manifest, isNot(contains('pathPrefix')));
  });

  group('defaults and notifications', () {
    test('images download over Wi-Fi only until the person says otherwise', () {
      expect(AppSettings.mediaImages.defaultValue, MediaDownloadPolicy.wifi);
    });

    test('with previews off the caller is not named and the lock screen is '
        'told nothing', () {
      final off = CallNotifications.incomingPresentation(
        callerName: 'Alice',
        showCaller: false,
      );
      expect(off.title, isNot(contains('Alice')));
      expect(off.visibility, NotificationVisibility.private);

      final on = CallNotifications.incomingPresentation(
        callerName: 'Alice',
        showCaller: true,
      );
      expect(on.title, 'Alice');
      expect(on.visibility, NotificationVisibility.public);
    });
  });
}

final class _Broken implements RuntimeFactory {
  @override
  Future<Never> open({required Uri serverUrl}) =>
      Future.error(StateError('the database cannot be opened'));
}
