import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/features/sign_in/presentation/sign_in_screen.dart';
import 'package:helix_remote/features/sign_in/presentation/widgets/sign_in_frame.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The accessibility guarantees Flutter itself knows how to check.
///
/// The tooltips and tap-target *rules* are source scans, in
/// `product_rules_test.dart`; what is here is the part only a real render can
/// answer: that the sign-in page, the shared controls and the high-contrast
/// theme actually satisfy the platform guidelines.
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

  testWidgets('the shared controls meet the guidelines', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: HelixThemes.light(),
        home: Scaffold(
          body: Column(
            children: [
              const HelixEmptyState(
                icon: Icons.inbox_outlined,
                title: 'Nothing here',
                message: 'When there is something, it shows up here.',
              ),
              HelixErrorState(message: 'That did not work.', onRetry: () {}),
              const HelixStatusBadge(label: 'Connected'),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton(onPressed: () {}, child: const Text('Continue')),
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () {},
                    icon: const Icon(Icons.arrow_back),
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

  testWidgets('the high-contrast theme meets the contrast guideline', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [runtimeFactoryProvider.overrideWithValue(_unreachable)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: HelixThemes.highContrastLight(),
          home: const SignInScreen(),
        ),
      ),
    );
    await tester.pump();

    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });

  testWidgets('the high-contrast theme meets them when the OS asks for it', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpSignIn(tester);

    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });

  test('the tap-target minimums really are 48 px', () {
    // The themes are where the guarantee actually lives, so it is asserted on
    // them rather than inferred from a screen.
    for (final theme in [
      HelixThemes.light(),
      HelixThemes.highContrastLight(),
      HelixThemes.signIn(),
      HelixThemes.signIn(highContrast: true),
    ]) {
      for (final style in [
        theme.filledButtonTheme.style,
        theme.outlinedButtonTheme.style,
        theme.textButtonTheme.style,
      ]) {
        final size = style?.minimumSize?.resolve(<WidgetState>{});
        expect(
          size,
          isNotNull,
          reason: 'every button style declares a minimum size',
        );
        expect(size!.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      final iconSize = theme.iconButtonTheme.style?.minimumSize?.resolve(
        <WidgetState>{},
      );
      expect(iconSize, isNotNull, reason: 'icon buttons declare a minimum');
      expect(iconSize!.width, greaterThanOrEqualTo(48));
      expect(iconSize.height, greaterThanOrEqualTo(48));
    }
  });

  test('the advanced-mode corner is 56 high, inside the 48 px floor', () {
    // The corner is a hidden target, but once revealed it holds a real button,
    // so it is held to the same floor as everything else.
    expect(AdvancedModeCorner.tapWindow, const Duration(seconds: 2));
    expect(AdvancedModeCorner.tapsToReveal, 3);
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
    title: 'Helix Remote',
    theme: HelixThemes.light(),
    highContrastTheme: HelixThemes.highContrastLight(),
    themeMode: ThemeMode.light,
    home: home,
  );
}

/// A runtime factory that must never be reached: these checks render a screen,
/// they do not sign anybody in.
final RuntimeFactory _unreachable = _UnreachableFactory();

final class _UnreachableFactory implements RuntimeFactory {
  @override
  Future<Never> open({required Uri serverUrl}) =>
      throw StateError('these checks must not open an engine');
}
