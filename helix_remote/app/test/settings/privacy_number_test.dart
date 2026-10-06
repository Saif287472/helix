import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/settings/application/settings_models.dart';
import 'package:helix_remote/features/settings/presentation/privacy_page.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:helix_remote_api/v2.dart' show ApiException, NetworkException;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode;

import '../support/a3b_fakes.dart';

/// Turning "find me by phone number" back on: the server rebuilds the entry
/// from the account's own number (and checks it against the verified one), so
/// the number has to reach `setPrivacy`: from the engine when it knows it,
/// typed once when not, and the refusal is said.
void main() {
  Future<FakeSettingsGateway> open(
    WidgetTester tester,
    FakeSettingsGateway gateway,
  ) async {
    useTallWindow(tester);
    await pumpPage(
      tester,
      const PrivacyPage(),
      overrides: a3bOverrides(settingsGateway: gateway),
      stubs: [RoutePaths.blocked],
    );
    await settle(tester);
    return gateway;
  }

  FakeSettingsGateway discoveryOff() =>
      FakeSettingsGateway()
        ..prefs = const PrivacyPrefs(discoverableByPhone: false);

  Future<void> toggle(WidgetTester tester) async {
    await tester.tap(find.text('Find me by phone number'));
    await settle(tester);
  }

  bool isOn(WidgetTester tester) => tester
      .widget<Switch>(
        find.descendant(
          of: find.ancestor(
            of: find.text('Find me by phone number'),
            matching: find.byType(InkWell),
          ),
          matching: find.byType(Switch),
        ),
      )
      .value;

  testWidgets('a device that knows the number turns it on without asking', (
    tester,
  ) async {
    final g = await open(tester, discoveryOff());
    expect(isOn(tester), isFalse);

    await toggle(tester);

    expect(g.calls, contains('setPrivacy'));
    expect(g.savedPrefs?.discoverableByPhone, isTrue);
    expect(find.text('Your phone number'), findsNothing);
    expect(isOn(tester), isTrue);
  });

  testWidgets('a device without the number asks once, with the country code', (
    tester,
  ) async {
    final g = await open(tester, discoveryOff()..privacyNeedsNumber = true);

    await toggle(tester);
    // Nothing was saved, and the switch is still off.
    expect(find.text('Your phone number'), findsOneWidget);
    expect(g.savedPrefs, isNull);
    expect(isOn(tester), isFalse);

    // Not a number with a country code: asked again, nothing sent.
    await tester.enterText(find.byType(TextField), '01711000001');
    await tester.tap(find.text('Turn on'));
    await settle(tester);
    expect(find.textContaining('country code'), findsWidgets);
    expect(g.savedPrefs, isNull);
    expect(find.text('Your phone number'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '+88 01711 000001');
    await tester.tap(find.text('Turn on'));
    await settle(tester);
    expect(g.privacyNumber, '+8801711000001');
    expect(g.savedPrefs?.discoverableByPhone, isTrue);
    expect(isOn(tester), isTrue);
  });

  testWidgets('declining to give the number leaves it off', (tester) async {
    final g = await open(tester, discoveryOff()..privacyNeedsNumber = true);
    await toggle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(g.savedPrefs, isNull);
    expect(isOn(tester), isFalse);
    expect(find.text('Your phone number'), findsNothing);
  });

  testWidgets('the server refusing the number is said in plain words', (
    tester,
  ) async {
    final g = discoveryOff()
      ..privacyNeedsNumber = true
      ..privacySaveFails = const ApiException(
        status: 400,
        code: ErrorCode.invalidField,
      );
    await open(tester, g);
    await toggle(tester);
    await tester.enterText(find.byType(TextField), '+8801799999999');
    await tester.tap(find.text('Turn on'));
    await settle(tester);

    expect(find.textContaining('Helix did not turn this on'), findsOneWidget);
    expect(find.textContaining('verified with'), findsOneWidget);
    // The switch shows what the server has: off.
    expect(isOn(tester), isFalse);
  });

  testWidgets('being offline is not blamed on the number', (tester) async {
    final g = discoveryOff()..privacySaveFails = const NetworkException();
    await open(tester, g);
    await toggle(tester);
    expect(find.textContaining('You are offline'), findsOneWidget);
    expect(find.textContaining('did not turn this on'), findsNothing);
  });

  testWidgets('turning it off never asks for a number', (tester) async {
    final g = FakeSettingsGateway()..privacyNeedsNumber = true;
    await open(tester, g);
    expect(isOn(tester), isTrue);

    await toggle(tester);

    expect(find.text('Your phone number'), findsNothing);
    expect(g.savedPrefs?.discoverableByPhone, isFalse);
  });
}
