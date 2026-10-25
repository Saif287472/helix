import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/diagnostics/anomaly_log.dart';
import 'package:helix_remote/core/engine/helix_runtime.dart';
import 'package:helix_remote/core/engine/local_settings.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/platform/account_slots.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/platform/attachment_picker.dart'
    show PickedFile, PickedKind;
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote/features/conversation/application/composer_notifier.dart'
    show AttachmentDraft, pendingAttachmentsProvider;
import 'package:helix_remote/features/profile/application/profile_providers.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show EmptyPhoneBook, EngineConfig;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show DevicePlatform;

/// Two accounts signed in on one phone: what the screens show, the settings
/// they write and the errors they report belong to the account on screen, and
/// to nothing else.
///
/// These run real engines over the two real encrypted files, because the thing
/// being proved is *which* engine a stream was opened on - a fake gateway
/// would answer either way.
void main() {
  late Directory tmp;
  late SecureKeyStore keys;
  final runtimes = <HelixRuntime>[];
  var tornDown = false;

  setUp(() {
    tornDown = false;
    tmp = Directory.systemTemp.createTempSync('helix_isolation');
    final local = Directory('${tmp.path}/local')..createSync();
    final private = Directory('${tmp.path}/private')..createSync();
    AppPaths.localDataDirectory = () async => local;
    AppPaths.privateDataDirectory = () async => private;
    AppPaths.isWindows = () => false;
    FlutterSecureStorage.setMockInitialValues({});
    keys = SecureKeyStore();
    AnomalyLog.resetForTest();
  });

  tearDown(() async {
    tornDown = true;
    final open = runtimes.toList();
    runtimes.clear();
    for (final runtime in open) {
      try {
        await runtime.close();
      } on Object {
        // Already closed when its account left the screen.
      }
    }
    AnomalyLog.resetForTest();
    AppPaths.localDataDirectory = () async => throw StateError('unset');
    AppPaths.isWindows = () => Platform.isWindows;
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // A file still held by the test run is not worth failing for.
    }
  });

  /// A signed-in account on this phone: its own database, holding its own name
  /// and number. Written before the engine opens it, because the engine owns
  /// the file.
  Future<void> seed(String account, String name, String e164) async {
    final tail = e164.substring(e164.length - 4).padLeft(12, '0');
    final file = await AppPaths.databaseFile(account);
    final key = await keys.keyFor(account, file);
    final db = await HelixDb.open(file, key: key);
    await db.accountDao.save(
      SelfAccountCompanion.insert(
        accountId: '0192a4f0-0000-7000-8000-$tail',
        deviceId: '0192a4f0-0000-7001-8000-$tail',
        serverDomain: 'helix.example',
        profileName: Value(name),
        phoneNumber: Value(e164),
        registeredAt: DateTime.utc(2026, 10, 25),
      ),
    );
    await db.close();
  }

  /// The factory the app would use: the runtime of the account asked for, on
  /// that account's own file.
  RuntimeFactory twoAccounts() => _ByAccount((account) async {
    final file = await AppPaths.databaseFile(account);
    final runtime = await HelixRuntime.open(
      account: account,
      dbFile: file,
      key: await keys.keyFor(account, file),
      serverUrl: Uri.parse('https://helix.example'),
      phoneBook: const EmptyPhoneBook(),
      config: const EngineConfig(
        deviceName: 'Test phone',
        platform: DevicePlatform.android,
      ),
      headless: true,
      keys: keys,
    );
    if (tornDown) {
      // The test ended while this engine was opening.
      await runtime.close();
      return runtime;
    }
    runtimes.add(runtime);
    return runtime;
  });

  ProviderContainer container(RuntimeFactory factory) {
    final c = ProviderContainer(
      overrides: [
        runtimeFactoryProvider.overrideWithValue(factory),
        accountSlotStoreProvider.overrideWithValue(AccountSlotStore()),
        secureKeyStoreProvider.overrideWithValue(keys),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Starts the engine of the account on screen and holds it open, which is
  /// what every screen does: the app closes it when another account is opened.
  void openRuntime(ProviderContainer c) => c.listen(runtimeProvider, (_, _) {});

  /// The engine of the account that left the screen closes asynchronously, so
  /// its lease is only free a moment later.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  /// Signs in "+880 1711 0000 01" (Aisha) and "+880 1711 0000 02" (Bilal), and
  /// leaves Bilal on screen; returns the two account ids.
  Future<(String, String)> signInBoth(ProviderContainer c) async {
    final accounts = c.read(accountsProvider.notifier);
    accounts.useServer(Uri.parse('https://helix.example'));
    await accounts.signedIn(e164: '+8801711000001');
    final first = c.read(activeAccountProvider)!.id;
    await seed(first, 'Aisha', '+8801711000001');
    accounts.leave();
    accounts.useServer(Uri.parse('https://helix.example'));
    await accounts.signedIn(e164: '+8801711000002');
    final second = c.read(activeAccountProvider)!.id;
    await seed(second, 'Bilal', '+8801711000002');
    return (first, second);
  }

  test(
    'the profile on screen is the account on screen, not the one before',
    () async {
      final c = container(twoAccounts());
      final (first, second) = await signInBoth(c);
      await c.read(accountsProvider.notifier).switchTo(first);
      openRuntime(c);
      // The stream the You page holds, opened on Aisha.
      c.listen(profileProvider, (_, _) {});
      expect((await c.read(profileProvider.future)).name, 'Aisha');

      await c.read(accountsProvider.notifier).switchTo(second);
      expect(
        (await c.read(profileProvider.future)).name,
        'Bilal',
        reason: 'the stream stayed on the engine Aisha closed',
      );
      expect(
        (await c.read(profileProvider.future)).phoneMasked,
        endsWith('02'),
      );
    },
  );

  test('a setting chosen on one account is not read by the other', () async {
    final c = container(twoAccounts());
    final (first, second) = await signInBoth(c);
    await c.read(accountsProvider.notifier).switchTo(first);
    openRuntime(c);
    await c.read(localSettingsProvider).set(AppSettings.profileAbout, 'Only A');
    expect(
      await c.read(localSettingsProvider).get(AppSettings.profileAbout),
      'Only A',
    );

    await c.read(accountsProvider.notifier).switchTo(second);
    expect(
      await c.read(localSettingsProvider).get(AppSettings.profileAbout),
      isEmpty,
      reason: 'the about line is Aisha\'s, in Aisha\'s database',
    );
    // And the other way round: what Bilal chooses cannot land in Aisha's file.
    await c.read(localSettingsProvider).set(AppSettings.profileAbout, 'Only B');
    await c.read(accountsProvider.notifier).switchTo(first);
    await settle();
    expect(
      await c.read(localSettingsProvider).get(AppSettings.profileAbout),
      'Only A',
    );
  });

  test(
    'each account reads the address book with its own number\'s prefix',
    () async {
      final c = container(twoAccounts());
      final (first, second) = await signInBoth(c);
      await c.read(accountsProvider.notifier).switchTo(first);
      openRuntime(c);
      c.read(phoneCountryProvider).setFromOwnNumber('+12025550123');
      expect(c.read(phoneCountryProvider).callingCode, '1');

      await c.read(accountsProvider.notifier).switchTo(second);
      expect(
        c.read(phoneCountryProvider).callingCode,
        isNull,
        reason: 'Bilal is not read with the country of the account before him',
      );
    },
  );

  test(
    'what one account left in the anomaly queue stays for its own server',
    () async {
      final c = container(twoAccounts());
      final (first, second) = await signInBoth(c);
      await c.read(accountsProvider.notifier).switchTo(first);
      openRuntime(c);
      c.listen(anomalyLogInstallProvider, (_, _) {});
      AnomalyLog.record('state', 'test.where', message: 'Aisha\'s trouble');
      expect(AnomalyLog.queued, hasLength(1));

      await c.read(accountsProvider.notifier).switchTo(second);
      await settle();
      // The switch does not empty it any more: each entry is tagged with the
      // server it was seen under and sent only there (the two accounts here
      // share one, so it is the same operator's). The server split itself is
      // `anomaly_log_test.dart`'s.
      expect(AnomalyLog.queued, hasLength(1));
      AnomalyLog.record('state', 'test.where', message: 'Bilal\'s trouble');
      expect(AnomalyLog.queued, hasLength(2));
    },
  );

  test(
    'files picked on one account are not waiting on the other\'s preview',
    () async {
      final c = container(twoAccounts());
      final (first, second) = await signInBoth(c);
      await c.read(accountsProvider.notifier).switchTo(first);
      // The same person is the same chat id on both accounts, so the same
      // family key - which is why the drafts are keyed on the account too.
      final drafts = c.read(pendingAttachmentsProvider('direct:peer').notifier);
      drafts.set(const [
        AttachmentDraft(
          PickedFile(
            path: 'a-photo.jpg',
            name: 'a-photo.jpg',
            mime: 'image/jpeg',
            size: 1024,
            kind: PickedKind.image,
          ),
        ),
      ]);
      expect(
        c.read(pendingAttachmentsProvider('direct:peer')),
        hasLength(1),
        reason: 'Aisha has a photo waiting to send',
      );

      await c.read(accountsProvider.notifier).switchTo(second);
      expect(
        c.read(pendingAttachmentsProvider('direct:peer')),
        isEmpty,
        reason: 'Bilal is not shown the file Aisha picked',
      );
    },
  );
}

/// Opens a runtime for the account asked for, on its own file.
final class _ByAccount implements RuntimeFactory {
  _ByAccount(this._open);

  final Future<HelixRuntime> Function(String account) _open;

  @override
  Future<HelixRuntime> open({
    required String account,
    required Uri serverUrl,
  }) => _open(account);
}
