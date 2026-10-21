import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote/core/theme/orbit_app_theme.dart';
import 'package:helix_remote/features/backup/application/backup_models.dart';
import 'package:helix_remote/features/devices/application/devices_models.dart';
import 'package:helix_remote/features/settings/application/settings_models.dart';
import 'package:helix_remote/features/settings/presentation/appearance_page.dart';
import 'package:helix_remote/shared/you_checkup.dart';

import '../support/a3b_fakes.dart';
import '../support/orbit_theme.dart';

/// The You page's privacy checkup (`orbit/contracts/you.md`, the rules Review
/// 1 set), and the theme choice behind Appearance.
void main() {
  group('checkup', () {
    /// The checks once every fact has come.
    Future<(List<YouCheck>, bool)> checks({
      FakeBackupGateway? backup,
      FakeDevicesGateway? devices,
      FakeSettingsGateway? settingsGateway,
      bool lock = true,
    }) async {
      final settings = FakeLocalSettings();
      await settings.set(AppSettings.appLockEnabled, lock);
      final container = newContainer(
        a3bOverrides(
          settings: settings,
          backup: backup ?? FakeBackupGateway(),
          devices: devices ?? FakeDevicesGateway(),
          settingsGateway: settingsGateway ?? FakeSettingsGateway(),
        ),
      );
      addTearDown(container.dispose);
      container.listen(youChecksProvider, (_, _) {});
      container.listen(youNeedsAttentionProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return (
        container.read(youChecksProvider),
        container.read(youNeedsAttentionProvider),
      );
    }

    test('all in place: every check passes and says why', () async {
      final backup = FakeBackupGateway()
        ..summary.set(
          BackupSummary(
            lastBackupAt: DateTime(2026, 10, 3, 5),
            lastRecoveryBackupAt: DateTime(2026, 9, 20),
          ),
        );
      final (list, attention) = await checks(backup: backup);
      expect([for (final c in list) c.key], YouCheckKey.values);
      expect(list.every((c) => c.ok), isTrue);
      expect(list[0].text, 'Backed up 5 hours ago');
      expect(list[1].text, '2 devices, both used this month');
      expect(list[2].text, 'Set. You can sign in on a new phone');
      expect(list[4].text, startsWith('On. Locks'));
      expect(attention, isFalse);
    });

    test('each rule flags what Review 1 set', () async {
      final backup = FakeBackupGateway()
        ..summary.set(BackupSummary(lastBackupAt: DateTime(2026, 9, 25)));
      final devices = FakeDevicesGateway()
        ..devices.set([
          const DeviceItem(
            id: 'd1',
            name: 'Pixel 8',
            platform: 'android',
            isThisDevice: true,
          ),
          DeviceItem(
            id: 'd2',
            name: 'Old tablet',
            platform: 'android',
            isThisDevice: false,
            lastActiveAt: DateTime(2026, 9, 1),
          ),
        ]);
      final gateway = FakeSettingsGateway()
        ..overview = const AccountOverview(phoneMasked: '+88017*****01');
      final (list, attention) = await checks(
        backup: backup,
        devices: devices,
        settingsGateway: gateway,
        lock: false,
      );
      expect(list.any((c) => c.ok), isFalse);
      expect(
        [for (final c in list) c.text],
        [
          'No backup in the last 7 days',
          'A device has not been used for 30 days',
          'No password set',
          'No recovery backup yet',
          'App lock is off',
        ],
      );
      expect(attention, isTrue);
    });

    test('no backup at all, and this device never counts as unused', () async {
      final backup = FakeBackupGateway()..summary.set(const BackupSummary());
      final devices = FakeDevicesGateway()
        ..devices.set([
          DeviceItem(
            id: 'd1',
            name: 'Pixel 8',
            platform: 'android',
            isThisDevice: true,
            lastActiveAt: DateTime(2026, 1, 1),
          ),
        ]);
      final (list, _) = await checks(backup: backup, devices: devices);
      expect(list[0].text, 'No chat backup yet');
      expect(list[1].ok, isTrue);
      expect(list[1].text, 'Only this device');
    });
  });

  group('theme', () {
    test('a choice draws the app in it and is remembered', () async {
      final store = _MemoryDeviceSettings();
      final container = newContainer([
        orbitThemeLibraryProvider.overrideWithValue(orbitTestThemes),
        deviceSettingsStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container.dispose);
      expect(container.read(orbitTokensProvider).meta.id, 'orbit');

      await container.read(themeChoiceProvider.notifier).choose('night');
      expect(container.read(orbitTokensProvider).meta.id, 'night');
      expect(store.theme, 'night');

      // A theme that is not built in (a pack not downloaded) changes nothing.
      await container.read(themeChoiceProvider.notifier).choose('ocean');
      expect(container.read(orbitTokensProvider).meta.id, 'night');
      expect(store.theme, 'night');
    });

    test('the app starts in the remembered theme', () {
      final container = newContainer([
        orbitThemeLibraryProvider.overrideWithValue(orbitTestThemes),
        initialThemeIdProvider.overrideWithValue('night'),
      ]);
      addTearDown(container.dispose);
      expect(container.read(orbitTokensProvider).meta.name, 'Orbit Night');
    });

    testWidgets('Appearance shows both themes and switches on a tap', (
      tester,
    ) async {
      useTallWindow(tester);
      final store = _MemoryDeviceSettings();
      final container = newContainer(
        a3bOverrides(
          extra: [deviceSettingsStoreProvider.overrideWithValue(store)],
        ),
      );
      addTearDown(container.dispose);
      await pumpPage(tester, const AppearancePage(), container: container);
      await settle(tester);

      expect(find.bySemanticsLabel('Orbit theme, selected'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Orbit Night theme'));
      await settle(tester);
      expect(container.read(themeChoiceProvider), 'night');
      expect(store.theme, 'night');
      expect(find.text('Orbit Night theme on'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  });
}

final class _MemoryDeviceSettings implements DeviceSettingsStore {
  String? theme;

  @override
  Future<String?> readTheme() async => theme;

  @override
  Future<void> writeTheme(String id) async => theme = id;
}
