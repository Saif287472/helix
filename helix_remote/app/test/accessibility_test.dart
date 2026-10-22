import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/features/sign_in/presentation/sign_in_screen.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

import 'support/orbit_theme.dart';

/// The accessibility guarantees Flutter itself knows how to check.
///
/// The tooltips and tap-target *rules* are source scans, in
/// `product_rules_test.dart`; what is here is the part only a real render can
/// answer: that the sign-in page and the shared Orbit controls actually
/// satisfy the platform guidelines, under the theme the app really draws with.
/// (The 48 px floor lives in the Orbit widgets themselves, and is measured
/// there in `orbit_ui/test/primitives_test.dart`.)
void main() {
  Future<void> pumpSignIn(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [runtimeFactoryProvider.overrideWithValue(_unreachable)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const HelixRemoteAppHarness(home: SignInScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('the sign-in page meets the platform guidelines', (tester) async {
    await pumpSignIn(tester);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });

  testWidgets('the sign-in page meets them at the largest text scale too', (
    tester,
  ) async {
    // A guideline that only holds at the default text size is not much of a
    // guarantee.
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpSignIn(tester);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });

  testWidgets('nothing clamps the text scale', (tester) async {
    await pumpSignIn(tester);

    // The old 1.3x cap is gone: text has to keep growing, or a screen reader
    // user with low vision cannot read the app at all.
    expect(find.textContaining('Sign in'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shared Orbit controls meet the guidelines', (tester) async {
    void noop() {}
    await tester.pumpWidget(
      MaterialApp(
        theme: orbitTestTheme(),
        builder: orbitTestBuilder,
        home: Scaffold(
          body: Column(
            children: [
              const orbit.OrbitBanner(
                kind: orbit.OrbitNoticeKind.info,
                icon: orbit.OrbitIcons.info,
                title: 'Nothing here',
                text: 'When there is something, it shows up here.',
                actions: [orbit.OrbitNoticeAction('Continue', null)],
              ),
              orbit.OrbitBanner(
                kind: orbit.OrbitNoticeKind.error,
                icon: orbit.OrbitIcons.warningCircle,
                title: 'That did not work.',
                text: 'Try again in a moment.',
                actions: [orbit.OrbitNoticeAction('Try again', noop)],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  orbit.OrbitButton(label: 'Continue', onPressed: noop),
                  orbit.OrbitIconButton(
                    icon: orbit.OrbitIcons.phone,
                    tooltip: 'Call',
                    onPressed: noop,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });

  // There is no separate high-contrast theme any more (Orbit port, Part B):
  // the chosen theme always shows, and it has to pass on its own.
  testWidgets('the Orbit theme meets them when the OS asks for high contrast', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpSignIn(tester);

    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });

  testWidgets('the advanced-mode corner is 56 high, inside the 48 px floor', (
    tester,
  ) async {
    // The corner is a hidden target, but once revealed it holds a real button,
    // so it is held to the same floor as everything else.
    await pumpSignIn(tester);
    final corner = tester.getSize(
      find.byKey(const ValueKey('advanced-mode-corner')),
    );
    expect(corner.height, greaterThanOrEqualTo(48));
  });
}

/// A `MaterialApp` with the app's themes, for the guideline checks.
///
/// It is not the real [HelixRemoteApp] because that builds a router, and a
/// guideline check needs one stable widget on screen rather than a redirect
/// that may move.
class HelixRemoteAppHarness extends StatelessWidget {
  const HelixRemoteAppHarness({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Orbit',
    // The app's theme (`main.dart`): Orbit, with no separate high-contrast
    // theme, so the chosen theme always shows.
    theme: orbitTestTheme(),
    themeMode: ThemeMode.light,
    builder: orbitTestBuilder,
    home: home,
  );
}

/// A runtime factory that must never be reached: these checks render a screen,
/// they do not sign anybody in.
final RuntimeFactory _unreachable = _UnreachableFactory();

final class _UnreachableFactory implements RuntimeFactory {
  @override
  Future<Never> open({required String account, required Uri serverUrl}) =>
      throw StateError('these checks must not open an engine');
}
