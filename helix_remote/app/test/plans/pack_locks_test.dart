import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/push/push_wake_tick.dart';
import 'package:helix_remote/core/theme/orbit_app_theme.dart';
import 'package:helix_remote/core/theme/packs_locked.dart';
import 'package:helix_remote/features/plans/application/plans_gateway.dart';
import 'package:helix_remote/features/plans/application/plans_providers.dart';
import 'package:helix_remote/features/settings/application/sound_packs.dart';
import 'package:helix_remote/features/settings/application/theme_packs.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

import '../support/orbit_theme.dart';
import 'plans_page_test.dart' show FakePlansGateway, aPlan;

/// What Free gets and Premium keeps (ADR-035): the two built-in themes and the
/// ringtones the app carries stay free; a downloaded pack is Premium's.
final class _MemoryDeviceSettings implements DeviceSettingsStore {
  _MemoryDeviceSettings({this.ringtone});

  String? ringtone;

  @override
  Future<String?> readRingtone() async => ringtone;

  @override
  Future<void> writeRingtone(String? id) async => ringtone = id;

  @override
  Future<String?> readTheme() async => null;

  @override
  Future<void> writeTheme(String id) async {}
}

ProviderContainer _container(List<Override> overrides) {
  final c = ProviderContainer(overrides: overrides);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('the theme on screen', () {
    List<Override> themes(String chosen) => [
      themeLibraryProvider.overrideWithValue({
        ...orbitTestThemes,
        'synthwave': orbitTestThemes['night']!,
      }),
      initialThemeIdProvider.overrideWithValue(chosen),
    ];

    test('is a downloaded pack while packs are not locked', () {
      final c = _container(themes('synthwave'));
      expect(
        identical(c.read(orbitTokensProvider), orbitTestThemes['night']),
        isTrue,
      );
    });

    test('falls back to Orbit while they are, and the choice is kept', () {
      final c = _container(themes('synthwave'));
      c.read(packsLockedProvider.notifier).set(true);
      expect(
        identical(c.read(orbitTokensProvider), orbitTestThemes['orbit']),
        isTrue,
      );
      expect(c.read(themeChoiceProvider), 'synthwave');

      c.read(packsLockedProvider.notifier).set(false);
      expect(
        identical(c.read(orbitTokensProvider), orbitTestThemes['night']),
        isTrue,
      );
    });

    test('keeps a built-in theme even when packs are locked', () {
      final c = _container(themes('night'));
      c.read(packsLockedProvider.notifier).set(true);
      expect(
        identical(c.read(orbitTokensProvider), orbitTestThemes['night']),
        isTrue,
      );
    });
  });

  group('the pack pages', () {
    test(
      'will not download or use a downloadable theme while locked',
      () async {
        final c = _container(const []);
        c.read(packsLockedProvider.notifier).set(true);
        final page = c.read(themePackPageProvider);

        expect(await page.get('synthwave'), packsLockedThemes);
        expect(await page.update('synthwave'), packsLockedThemes);
        expect(await page.use('synthwave'), packsLockedThemes);
      },
    );

    test(
      'will not download or use a downloadable ringtone while locked',
      () async {
        final c = _container(const []);
        c.read(packsLockedProvider.notifier).set(true);
        final page = c.read(ringtonePageProvider);

        expect(await page.get('rain'), packsLockedSounds);
        expect(await page.update('rain'), packsLockedSounds);
        expect(await page.use('rain'), packsLockedSounds);
      },
    );

    test('a ringtone pack already chosen is dropped when packs lock', () async {
      final store = _MemoryDeviceSettings(ringtone: 'rain');
      final c = _container([
        deviceSettingsStoreProvider.overrideWithValue(store),
      ]);

      expect(await c.read(ringtoneChoiceProvider.future), 'rain');
      c.read(packsLockedProvider.notifier).set(true);
      expect(await c.read(ringtoneChoiceProvider.future), isNull);
      expect(store.ringtone, isNull, reason: 'the phone rings with its own');
    });
  });

  group('the plan decides', () {
    Future<bool> lockedBy(BillingPlan plan) async {
      final c = _container([
        plansGatewayProvider.overrideWithValue(FakePlansGateway(plan)),
      ]);
      c.listen(billingPlanProvider, (_, _) {});
      await c.read(billingPlanProvider.future);
      return c.read(packsLockedProvider);
    }

    test('Free with plans on locks packs', () async {
      expect(await lockedBy(aPlan()), isTrue);
    });

    test('Premium, the trial and plans off do not', () async {
      expect(await lockedBy(aPlan(plan: PlanId.premium)), isFalse);
      expect(await lockedBy(aPlan(plan: PlanId.premium, trial: true)), isFalse);
      expect(await lockedBy(aPlan(enabled: false)), isFalse);
    });

    test('a wake-up while the app is in front reads the plan again', () async {
      final gateway = FakePlansGateway(aPlan());
      final c = _container([plansGatewayProvider.overrideWithValue(gateway)]);
      c.listen(billingPlanProvider, (_, _) {});
      expect((await c.read(billingPlanProvider.future)).isPremium, isFalse);

      gateway.current = aPlan(plan: PlanId.premium);
      c.read(pushWakeTickProvider.notifier).bump();
      expect((await c.read(billingPlanProvider.future)).isPremium, isTrue);
      expect(c.read(packsLockedProvider), isFalse);
    });
  });
}
