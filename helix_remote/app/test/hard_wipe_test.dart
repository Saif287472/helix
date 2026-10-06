import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/helix_runtime.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/platform/picker_cleanup.dart';
import 'package:helix_remote_crypto/v2.dart'
    show DeviceAddress, Ed25519KeyPair, LocalDeviceKeys, SecureCryptoRandom;
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show EmptyPhoneBook, EngineConfig, EngineStatus;

/// The app's half of the engine's hard wipe (`Engine(hardWipe:)`): sign-out
/// and a wiping revocation leave no database file, no key and no plaintext
/// file behind. These tests run a real engine on a real encrypted file, which
/// is the only way to prove the hook is wired and runs at the right time.
void main() {
  late Directory tmp;
  late Directory local;
  late Directory private;
  late File dbFile;
  late SecureKeyStore keys;
  var pickerCleared = 0;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('helix_hard_wipe');
    local = Directory('${tmp.path}/local')..createSync();
    private = Directory('${tmp.path}/private')..createSync();
    AppPaths.localDataDirectory = () async => local;
    AppPaths.privateDataDirectory = () async => private;
    AppPaths.isWindows = () => false;
    FlutterSecureStorage.setMockInitialValues({});
    keys = SecureKeyStore();
    dbFile = await AppPaths.databaseFile();
    pickerCleared = 0;
    PickerTemporaryFiles.clearer = () async => pickerCleared++;
  });

  tearDown(() {
    AppPaths.localDataDirectory = () async => throw StateError('unset');
    AppPaths.isWindows = () => Platform.isWindows;
    PickerTemporaryFiles.clearer = () async {};
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // A file still held by the test run is not worth failing for.
    }
  });

  /// A database that already belongs to a signed-in device, written the way
  /// the engine's account service does (minus the server, which needs none to
  /// be signed in), plus the plaintext files the app keeps beside it.
  Future<DatabaseKey> seedSignedInDevice() async {
    final key = await keys.keyFor(dbFile);
    final db = await HelixDb.open(dbFile, key: key);
    final random = SecureCryptoRandom();
    final aik = await Ed25519KeyPair.generate(random);
    final address = DeviceAddress(
      '0192a4f0-0000-7000-8000-00000000000a',
      '0192a4f0-0000-7000-8000-00000000000b',
    );
    final now = DateTime(2026, 10, 5, 9);
    final device = await LocalDeviceKeys.create(
      accountIdentityKey: aik,
      address: address,
      createdAt: now,
      random: random,
    );
    await db.cryptoDao.saveIdentity(
      IdentityCompanion.insert(
        id: const Value(1),
        accountId: address.account,
        deviceId: address.device,
        aikPublic: aik.publicKey,
        aikPrivate: aik.seed,
        dikPublic: device.identityKey.publicKey,
        dikPrivate: device.identityKey.privateKey,
        dskPublic: device.signingKey.publicKey,
        dskPrivate: device.signingKey.seed,
        deviceCertificate: utf8.encode(jsonEncode(device.certificate.toJson())),
        createdAt: now,
      ),
    );
    await db.accountDao.save(
      SelfAccountCompanion.insert(
        accountId: address.account,
        deviceId: address.device,
        serverDomain: '127.0.0.1:9',
        registeredAt: now,
      ),
    );
    await db.close();
    // The plaintext leftovers sign-out must not keep.
    (await AppPaths.profileAvatarFile()).writeAsBytesSync([1, 2, 3]);
    File(
      '${(await AppPaths.attachmentCache()).path}/photo.jpg',
    ).writeAsBytesSync([9]);
    return key;
  }

  Future<HelixRuntime> open(DatabaseKey key) => HelixRuntime.open(
    dbFile: dbFile,
    key: key,
    serverUrl: Uri.parse('http://127.0.0.1:9'),
    phoneBook: const EmptyPhoneBook(),
    config: const EngineConfig(),
    headless: true,
    keys: keys,
  );

  Future<void> expectNothingLeft() async {
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      expect(
        File('${dbFile.path}$suffix').existsSync(),
        isFalse,
        reason: 'database file$suffix',
      );
    }
    expect(await keys.hasKey(), isFalse, reason: 'the SQLCipher key');
    expect((await AppPaths.profileAvatarFile()).existsSync(), isFalse);
    expect((await AppPaths.attachmentCache()).listSync(), isEmpty);
    expect(pickerCleared, greaterThan(0));
  }

  test(
    'the engine opened by the runtime is signed in and has the hook',
    () async {
      final key = await seedSignedInDevice();
      final runtime = await open(key);
      addTearDown(runtime.close);
      expect(runtime.engine.account.isSignedIn, isTrue);
      expect(runtime.wasWiped, isFalse);
      // Nothing is wiped just by opening.
      expect(dbFile.existsSync(), isTrue);
      expect(await keys.hasKey(), isTrue);
    },
  );

  test('Engine.signOut closes the database, destroys the file, deletes the '
      'key and the plaintext files', () async {
    final key = await seedSignedInDevice();
    final runtime = await open(key);

    await runtime.engine.signOut();

    expect(runtime.engine.status, EngineStatus.signedOut);
    expect(runtime.wasWiped, isTrue);
    await expectNothingLeft();
    // Closing a wiped runtime must not trip over the database that is gone.
    await runtime.close();
  });

  test(
    'the next account on this device gets a new file and a new key',
    () async {
      final key = await seedSignedInDevice();
      final runtime = await open(key);
      await runtime.engine.signOut();
      await runtime.close();

      // What sign-in does next: a key is made because there is no file, and an
      // empty database opens with it.
      final fresh = await keys.keyFor(dbFile);
      expect(fresh.bytes, isNot(key.bytes));
      final next = await open(fresh);
      addTearDown(next.close);
      expect(next.engine.account.isSignedIn, isFalse);
    },
  );

  test('the app sign-out runs the hook (and finishes the wipe for an engine '
      'that had nothing to sign out)', () async {
    // No account in this database: Engine.signOut returns at once, so only the
    // app's own step can leave the file and key gone.
    final key = await keys.keyFor(dbFile);
    (await AppPaths.profileAvatarFile()).writeAsBytesSync([1]);
    final first = await open(key);
    expect(first.engine.account.isSignedIn, isFalse);

    final container = ProviderContainer(
      overrides: [
        runtimeFactoryProvider.overrideWithValue(_Single(first)),
        secureKeyStoreProvider.overrideWithValue(keys),
        serverUrlStoreProvider.overrideWithValue(ServerUrlStore()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    container
        .read(serverUrlProvider.notifier)
        .use(Uri.parse('http://127.0.0.1:9'));
    await container.read(runtimeProvider.future);

    await container.read(signOutProvider)();

    expect(first.wasWiped, isTrue);
    await expectNothingLeft();
    expect(container.read(serverUrlProvider), isNull);
  });

  test(
    'the app sign-out of a signed-in device leaves nothing behind',
    () async {
      final key = await seedSignedInDevice();
      final runtime = await open(key);
      final container = ProviderContainer(
        overrides: [
          runtimeFactoryProvider.overrideWithValue(_Single(runtime)),
          secureKeyStoreProvider.overrideWithValue(keys),
          serverUrlStoreProvider.overrideWithValue(ServerUrlStore()),
        ],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);
      container
          .read(serverUrlProvider.notifier)
          .use(Uri.parse('http://127.0.0.1:9'));
      await container.read(runtimeProvider.future);

      await container.read(signOutProvider)();

      expect(runtime.wasWiped, isTrue);
      await expectNothingLeft();
    },
  );

  test('a deletion the server did not accept wipes nothing', () async {
    final key = await seedSignedInDevice();
    final runtime = await open(key);
    addTearDown(runtime.close);

    // No server answers on this address: the proof cannot be made.
    await expectLater(runtime.engine.deleteAccount(), throwsA(anything));

    expect(runtime.wasWiped, isFalse);
    expect(runtime.engine.account.isSignedIn, isTrue);
    expect(dbFile.existsSync(), isTrue);
    expect(await keys.hasKey(), isTrue);
    expect((await AppPaths.profileAvatarFile()).existsSync(), isTrue);
  });

  test('a failing step does not stop the others, and is reported', () async {
    final key = await seedSignedInDevice();
    final db = await HelixDb.open(dbFile, key: key);
    var afterRan = false;
    await expectLater(
      HelixRuntime.hardWipe(
        db: db,
        dbFile: dbFile,
        afterWipe: () async {
          afterRan = true;
          throw StateError('keystore unavailable');
        },
      ),
      throwsA(isA<StateError>()),
    );
    expect(afterRan, isTrue);
    expect(dbFile.existsSync(), isFalse);
  });

  test('after a revocation wipe the app opens a new runtime', () async {
    final key = await seedSignedInDevice();
    final first = await open(key);
    // What the engine's revocation path runs (it cannot be provoked without a
    // server): the hook, then the status.
    await first.ensureWiped();
    final opened = <HelixRuntime>[];
    final status = StreamController<AppAuthState>();
    addTearDown(status.close);
    final container = ProviderContainer(
      overrides: [
        runtimeFactoryProvider.overrideWithValue(
          _Recording(first, opened, () async {
            final fresh = await keys.keyFor(dbFile);
            return open(fresh);
          }),
        ),
        authStateProvider.overrideWith((ref) => status.stream),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    container
        .read(serverUrlProvider.notifier)
        .use(Uri.parse('http://127.0.0.1:9'));
    await container.read(runtimeProvider.future);
    container.listen(authStateProvider, (_, _) {});
    container.read(wipedRuntimeResetProvider);

    status.add(AppAuthState.revoked);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final second = await container.read(runtimeProvider.future);

    expect(opened, hasLength(2));
    expect(identical(second, first), isFalse);
    expect(second.engine.account.isSignedIn, isFalse);
  });
}

/// Hands out one prepared runtime.
final class _Single implements RuntimeFactory {
  _Single(this._runtime);

  final HelixRuntime _runtime;

  @override
  Future<HelixRuntime> open({required Uri serverUrl}) async => _runtime;
}

/// The first open gives [first]; later ones call [again].
final class _Recording implements RuntimeFactory {
  _Recording(this.first, this.opened, this.again);

  final HelixRuntime first;
  final List<HelixRuntime> opened;
  final Future<HelixRuntime> Function() again;

  @override
  Future<HelixRuntime> open({required Uri serverUrl}) async {
    final runtime = opened.isEmpty ? first : await again();
    opened.add(runtime);
    return runtime;
  }
}
