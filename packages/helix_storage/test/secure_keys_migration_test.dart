import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:helix_domain/core/constants.dart';
import 'package:helix_domain/core/product_descriptor.dart';
import 'package:helix_storage/infrastructure/storage/flutter_profile_repository.dart';
import 'package:helix_storage/infrastructure/storage/flutter_secure_identity_store.dart';
import 'package:helix_storage/infrastructure/storage/secure_trust_repository.dart';

class FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  final IOSOptions iOptions = IOSOptions.defaultOptions;
  @override
  final AndroidOptions aOptions = AndroidOptions.defaultOptions;
  @override
  final LinuxOptions lOptions = LinuxOptions.defaultOptions;
  @override
  final WindowsOptions wOptions = WindowsOptions.defaultOptions;
  @override
  final WebOptions webOptions = WebOptions.defaultOptions;
  @override
  final AppleOptions mOptions = MacOsOptions.defaultOptions;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _data.remove(key);

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map.from(_data);

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _data.clear();

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _data.containsKey(key);

  @override
  Stream<bool>? get onCupertinoProtectedDataAvailabilityChanged => null;

  @override
  Future<bool?> isCupertinoProtectedDataAvailable() async => null;

  @override
  void registerListener({
    required String key,
    required ValueChanged<String?> listener,
  }) {}

  @override
  void unregisterListener({
    required String key,
    required ValueChanged<String?> listener,
  }) {}

  @override
  void unregisterAllListenersForKey({required String key}) {}

  @override
  void unregisterAllListeners() {}

  @override
  Map<String, List<ValueChanged<String?>>> get getListeners => {};
}

void main() {
  group('Secure keys migration', () {
    late FakeSecureStorage storage;

    setUp(() {
      storage = FakeSecureStorage();
    });

    test('profile repository migrates unprefixed keys when prefix is helix_local_v1_', () async {
      await storage.write(key: kKeyDisplayName, value: 'Alice');
      await storage.write(key: kKeyThemeMode, value: 'dark');

      final repo = FlutterProfileRepository(storage: storage, keyPrefix: 'helix_local_v1_');
      final profile = await repo.loadProfile();

      expect(profile, isNotNull);
      expect(profile!.displayName, equals('Alice'));
      expect(profile.themeMode, equals('dark'));

      // Verify old keys were deleted
      expect(await storage.read(key: kKeyDisplayName), isNull);
      expect(await storage.read(key: kKeyThemeMode), isNull);

      // Verify new prefixed keys exist
      expect(await storage.read(key: 'helix_local_v1_$kKeyDisplayName'), equals('Alice'));
      expect(await storage.read(key: 'helix_local_v1_$kKeyThemeMode'), equals('dark'));
    });

    test('profile repository does not migrate keys when prefix is helix_remote_v1_', () async {
      await storage.write(key: kKeyDisplayName, value: 'Alice');

      final repo = FlutterProfileRepository(storage: storage, keyPrefix: 'helix_remote_v1_');
      final profile = await repo.loadProfile();

      expect(profile, isNull);
      expect(await storage.read(key: kKeyDisplayName), equals('Alice'));
      expect(await storage.read(key: 'helix_remote_v1_$kKeyDisplayName'), isNull);
    });

    test('identity store migrates identity keys when prefix is helix_local_v1_', () async {
      await storage.write(key: kKeySecretCode, value: 'secret-code');
      await storage.write(key: kKeyFirstRunDone, value: '1');

      final store = FlutterSecureIdentityStore(storage: storage, keyPrefix: 'helix_local_v1_');

      expect(await store.loadSecretCode(), equals('secret-code'));
      expect(await store.isFirstRun(), isFalse);

      expect(await storage.read(key: kKeySecretCode), isNull);
      expect(await storage.read(key: kKeyFirstRunDone), isNull);
      expect(await storage.read(key: 'helix_local_v1_$kKeySecretCode'), equals('secret-code'));
      expect(await storage.read(key: 'helix_local_v1_$kKeyFirstRunDone'), equals('1'));
    });

    test('identity store does not migrate keys when prefix is helix_remote_v1_', () async {
      await storage.write(key: kKeySecretCode, value: 'secret-code');

      final store = FlutterSecureIdentityStore(storage: storage, keyPrefix: 'helix_remote_v1_');

      expect(await store.loadSecretCode(), isNull);
      expect(await storage.read(key: kKeySecretCode), equals('secret-code'));
      expect(await storage.read(key: 'helix_remote_v1_$kKeySecretCode'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Storage reset isolation
  // ---------------------------------------------------------------------------
  // Simulates the panic-wipe path in settings_screen.dart:
  // seed both Local and Remote namespaces, run the Local-scoped reset, verify
  // that only Local keys were removed and Remote keys remain intact.

  group('Storage reset isolation', () {
    const localPrefix = 'helix_local_v1_';
    const remotePrefix = 'helix_remote_v1_';

    late FakeSecureStorage storage;

    setUp(() {
      storage = FakeSecureStorage();
    });

    Future<void> seedNamespace(String prefix, String displayName) async {
      await storage.write(key: '${prefix}display_name', value: displayName);
      await storage.write(key: '${prefix}identity_cert_pem', value: 'cert-$prefix');
      await storage.write(key: '${prefix}last_session_id', value: 'sess-$prefix');
    }

    Future<void> runLocalScopedReset() async {
      // Mirrors what settings_screen.dart does after the scoped-delete fix.
      final allKeys = (await storage.readAll()).keys.toList();
      for (final key in allKeys) {
        if (key.startsWith(localPrefix)) {
          await storage.delete(key: key);
        }
      }
    }

    test('Local scoped reset removes only helix_local_v1_ keys', () async {
      await seedNamespace(localPrefix, 'Alice');
      await seedNamespace(remotePrefix, 'Bob');

      await runLocalScopedReset();

      // Local keys must be gone
      expect(await storage.read(key: '${localPrefix}display_name'), isNull);
      expect(await storage.read(key: '${localPrefix}identity_cert_pem'), isNull);
      expect(await storage.read(key: '${localPrefix}last_session_id'), isNull);

      // Remote keys must be untouched
      expect(
        await storage.read(key: '${remotePrefix}display_name'),
        equals('Bob'),
      );
      expect(
        await storage.read(key: '${remotePrefix}identity_cert_pem'),
        equals('cert-$remotePrefix'),
      );
      expect(
        await storage.read(key: '${remotePrefix}last_session_id'),
        equals('sess-$remotePrefix'),
      );
    });

    test('prefix-scoped prefixes are distinct so resets cannot collide', () {
      const local = LocalProductDescriptor();
      const remote = RemoteProductDescriptor();

      // Remote prefix must not be a substring prefix of Local prefix.
      expect(
        local.secureStoragePrefix,
        isNot(startsWith(remote.secureStoragePrefix)),
      );
      expect(
        remote.secureStoragePrefix,
        isNot(startsWith(local.secureStoragePrefix)),
      );
    });

    test('clear() on a scoped repository only deletes its own keys', () async {
      await seedNamespace(localPrefix, 'Alice');
      await seedNamespace(remotePrefix, 'Bob');

      // Clear just the Local profile repository
      final localRepo = FlutterProfileRepository(
        storage: storage,
        keyPrefix: localPrefix,
      );
      await localRepo.clear();

      // Local display_name key is gone
      expect(await storage.read(key: '${localPrefix}display_name'), isNull);

      // Remote display_name key survives
      expect(
        await storage.read(key: '${remotePrefix}display_name'),
        equals('Bob'),
      );

      // Identity and session keys from BOTH namespaces survive
      expect(
        await storage.read(key: '${localPrefix}identity_cert_pem'),
        isNotNull,
        reason: 'Identity store is separate from profile repository',
      );
      expect(
        await storage.read(key: '${remotePrefix}identity_cert_pem'),
        isNotNull,
      );

      // Trust repository clear test
      final localTrust = SecureTrustRepository(
        storage: storage,
        keyPrefix: localPrefix,
      );
      await localTrust.saveKnownPeers([]);  // write empty list
      // Remote trust key is untouched (we never wrote one via Remote prefix)
      expect(
        await storage.read(key: '${remotePrefix}known_peers'),
        isNull,
      );
    });
  });
}
