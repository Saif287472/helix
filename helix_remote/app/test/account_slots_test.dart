import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/clock.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/engine/server_policy.dart';
import 'package:helix_remote/core/platform/account_slots.dart';
import 'package:helix_remote/core/platform/app_storage.dart';

/// The accounts on a device: the list in the keystore, and one folder and one
/// key per account.
void main() {
  late Directory tmp;
  late SecureKeyStore keys;
  final at = DateTime.utc(2026, 10, 21, 9);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('helix_accounts');
    final local = Directory('${tmp.path}/local')..createSync();
    final private = Directory('${tmp.path}/private')..createSync();
    AppPaths.localDataDirectory = () async => local;
    AppPaths.privateDataDirectory = () async => private;
    AppPaths.isWindows = () => false;
    FlutterSecureStorage.setMockInitialValues({});
    keys = SecureKeyStore();
  });

  tearDown(() {
    AppPaths.localDataDirectory = () async => throw StateError('unset');
    AppPaths.isWindows = () => Platform.isWindows;
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // A file still held by the test run is not worth failing for.
    }
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        accountSlotStoreProvider.overrideWithValue(AccountSlotStore()),
        secureKeyStoreProvider.overrideWithValue(keys),
        clockProvider.overrideWithValue(() => at),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('AccountSlotStore', () {
    test('the old saved server becomes the first account', () async {
      FlutterSecureStorage.setMockInitialValues({
        AccountSlotStore.legacyServerKey: 'https://helix.example',
      });
      final store = AccountSlotStore();
      final loaded = await store.load();
      expect(loaded.active, AppPaths.firstAccount);
      expect(loaded.current?.server, 'https://helix.example');
      expect(loaded.current?.signedIn, isTrue);

      const storage = FlutterSecureStorage();
      expect(await storage.read(key: AccountSlotStore.legacyServerKey), isNull);
      expect(await store.load(), loaded);
    });

    test('only signed-in accounts are written', () async {
      final store = AccountSlotStore();
      await store.save(
        AccountSlots(
          active: 'b',
          slots: [
            AccountSlot(
              id: 'a',
              server: 'https://one.example',
              signedIn: true,
              e164: '+8801711000001',
              name: 'Ada',
              lastUsed: at,
            ),
            const AccountSlot(id: 'b', server: 'https://two.example'),
          ],
        ),
      );
      final loaded = await store.load();
      expect(loaded.slots.map((s) => s.id), ['a']);
      expect(loaded.active, isNull, reason: 'the active one was not kept');
      expect(loaded.byId('a')?.name, 'Ada');
      expect(loaded.byId('a')?.e164, '+8801711000001');
      expect(loaded.byId('a')?.lastUsed, at.toLocal());
    });

    test('an empty list deletes the entry; garbage reads as none', () async {
      const storage = FlutterSecureStorage();
      final store = AccountSlotStore();
      await store.save(
        const AccountSlots(
          slots: [AccountSlot(id: 'a', server: 'https://x', signedIn: true)],
        ),
      );
      await store.save(const AccountSlots());
      expect(await storage.read(key: AccountSlotStore.keystoreKey), isNull);

      await storage.write(key: AccountSlotStore.keystoreKey, value: '{nope');
      expect(await store.load(), const AccountSlots());
    });
  });

  group('AccountSlots', () {
    test('the first id is the first account, then random ones', () {
      final random = Random(1);
      const empty = AccountSlots();
      expect(empty.newId(random), AppPaths.firstAccount);
      final one = empty.put(
        const AccountSlot(id: AppPaths.firstAccount, server: 'https://x'),
      );
      final id = one.newId(random);
      expect(id, matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('signed-in accounts are listed most recent first', () {
      final slots = AccountSlots(
        slots: [
          AccountSlot(id: 'a', server: 's', signedIn: true, lastUsed: at),
          const AccountSlot(id: 'b', server: 's'),
          AccountSlot(
            id: 'c',
            server: 's',
            signedIn: true,
            lastUsed: at.add(const Duration(minutes: 1)),
          ),
        ],
      );
      expect(slots.signedIn.map((s) => s.id), ['c', 'a']);
      expect(slots.activate('a').without('a').active, isNull);
    });
  });

  group('AccountsNotifier', () {
    test('a finished sign-in is kept and opened at the next start', () async {
      final c = container();
      final accounts = c.read(accountsProvider.notifier);
      accounts.useServer(Uri.parse('https://helix.example'));
      expect(c.read(activeAccountProvider)?.id, AppPaths.firstAccount);
      await accounts.signedIn(e164: '+8801711000001', name: 'Ada');

      final next = container();
      expect(await next.read(accountsProvider.notifier).restore(), isTrue);
      final current = next.read(accountsProvider).current!;
      expect(current.id, AppPaths.firstAccount);
      expect(current.e164, '+8801711000001');
      expect(current.lastUsed, at.toLocal());
      expect(next.read(serverUrlProvider), Uri.parse('https://helix.example'));
    });

    test('an unfinished sign-in is not kept', () async {
      final c = container();
      c.read(accountsProvider.notifier).useServer(Uri.parse('https://x.test'));
      expect(
        await container().read(accountsProvider.notifier).restore(),
        isFalse,
      );
    });

    test('changing server while signing in keeps the same slot', () {
      final c = container();
      final accounts = c.read(accountsProvider.notifier);
      accounts.useServer(Uri.parse('https://one.example'));
      final id = c.read(activeAccountProvider)!.id;
      accounts.useServer(Uri.parse('https://two.example'));
      expect(c.read(activeAccountProvider)?.id, id);
      expect(c.read(accountsProvider).slots, hasLength(1));
      expect(c.read(serverUrlProvider), Uri.parse('https://two.example'));
    });

    test('a second account after leaving gets its own id', () async {
      final c = container();
      final accounts = c.read(accountsProvider.notifier);
      accounts.useServer(Uri.parse('https://helix.example'));
      await accounts.signedIn();
      accounts.leave();
      expect(c.read(activeAccountProvider), isNull);
      accounts.useServer(Uri.parse('https://helix.example'));
      final second = c.read(activeAccountProvider)!.id;
      expect(second, isNot(AppPaths.firstAccount));
      expect(c.read(accountsProvider).slots, hasLength(2));
    });

    test('an address that is not https is refused', () {
      final c = container();
      expect(
        () => c
            .read(accountsProvider.notifier)
            .useServer(Uri.parse('http://helix.example')),
        throwsA(isA<InsecureServerUrl>()),
      );
      expect(c.read(activeAccountProvider), isNull);
    });

    test('a remembered address that is not https is not opened', () async {
      await AccountSlotStore().save(
        const AccountSlots(
          active: 'a',
          slots: [
            AccountSlot(
              id: 'a',
              server: 'http://helix.example',
              signedIn: true,
            ),
          ],
        ),
      );
      final c = container();
      expect(await c.read(accountsProvider.notifier).restore(), isFalse);
      expect(c.read(activeAccountProvider), isNull);
    });

    test('removing the account on screen forgets it', () async {
      final c = container();
      final accounts = c.read(accountsProvider.notifier);
      accounts.useServer(Uri.parse('https://helix.example'));
      await accounts.signedIn();
      await accounts.removeCurrent();
      expect(c.read(accountsProvider).slots, isEmpty);
      expect(
        await container().read(accountsProvider.notifier).restore(),
        isFalse,
      );
    });

    test('folders of unlisted accounts are deleted with their keys', () async {
      await AccountSlotStore().save(
        const AccountSlots(
          active: 'kept',
          slots: [
            AccountSlot(id: 'kept', server: 'https://x.test', signedIn: true),
          ],
        ),
      );
      for (final id in ['kept', 'stray']) {
        await keys.keyFor(id, await AppPaths.databaseFile(id));
        await (await AppPaths.databaseFile(id)).writeAsString('db');
      }

      await container().read(accountsProvider.notifier).restore();

      expect(await AppPaths.accountFolders(), ['kept']);
      expect(await keys.hasKey('kept'), isTrue);
      expect(await keys.hasKey('stray'), isFalse);
    });
  });

  group('per-account files', () {
    test('each account has its own folder and key', () async {
      final first = await AppPaths.databaseFile(AppPaths.firstAccount);
      final second = await AppPaths.databaseFile('abc123');
      expect(first.parent.path, endsWith('helix_remote'));
      expect(
        second.parent.path,
        endsWith('accounts${Platform.pathSeparator}abc123'),
      );

      final a = await keys.keyFor(AppPaths.firstAccount, first);
      final b = await keys.keyFor('abc123', second);
      expect(a.bytes, isNot(b.bytes));
      expect(
        () => AppPaths.databaseFile('../escape'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test("wiping one account leaves the other's files", () async {
      final firstAvatar = await AppPaths.profileAvatarFile(
        AppPaths.firstAccount,
      );
      await firstAvatar.writeAsBytes([1]);
      final secondAvatar = await AppPaths.profileAvatarFile('abc123');
      await secondAvatar.writeAsBytes([2]);
      await (await AppPaths.databaseFile('abc123')).writeAsString('db');

      await AppPaths.wipeLocalFiles('abc123', includeDatabase: true);

      expect(await firstAvatar.exists(), isTrue);
      expect(await secondAvatar.exists(), isFalse);
      expect(await AppPaths.accountFolders(), isEmpty);
    });
  });
}
