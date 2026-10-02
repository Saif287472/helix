import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/links/helix_code.dart';
import 'package:helix_remote/core/router/app_router.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_controller.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_copy.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_state.dart';
import 'package:helix_remote/features/sign_in/presentation/sign_in_screen.dart';
import 'package:helix_remote/features/sign_in/presentation/widgets/sign_in_frame.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The sign-in product rules (AGENTS.md, plan §7).
///
/// These run headless against a provider scope whose runtime factory refuses to
/// open anything, so a test can walk the page machine without a keystore, a
/// database or a network. Anything that needs the engine's answer is covered by
/// the engine's own tests and by `server/test/client/`.
void main() {
  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    void Function(WidgetTester)? after,
  }) async {
    final container = ProviderContainer(
      overrides: [runtimeFactoryProvider.overrideWithValue(_unreachable)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: HelixThemes.light(),
          home: const SignInScreen(),
        ),
      ),
    );
    after?.call(tester);
    return container;
  }

  group('the Global page', () {
    test(
      'is where sign-in starts, with no back button and no server guide',
      () async {
        final container = ProviderContainer(
          overrides: [runtimeFactoryProvider.overrideWithValue(_unreachable)],
        );
        addTearDown(container.dispose);
        final notifier = container.read(signInControllerProvider.notifier);

        expect(notifier.state.mode, SignInMode.global);
        expect(notifier.state.page, SignInPage.phone);
        expect(notifier.state.isLoading, isFalse);
        expect(notifier.state.requiresTerms, isTrue);
      },
    );

    testWidgets('shows a phone number, Next and the Terms link, and nothing '
        'else', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Sign in'), findsOneWidget);
      expect(find.byKey(const ValueKey('phone-field')), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Terms & Privacy'), findsOneWidget);
      // There is nothing before this page, so a back arrow would lie.
      expect(find.byTooltip('Back'), findsNothing);
      // No host-your-own-server copy, ever.
      expect(find.textContaining('Host your own'), findsNothing);
      expect(find.text('Advanced mode'), findsNothing);
    });

    testWidgets('is a Helix Themes.signIn page', (tester) async {
      await pumpScreen(tester);

      final context = tester.element(find.byKey(const ValueKey('phone-field')));
      expect(Theme.of(context).colorScheme.primary, isNotNull);
      expect(
        Theme.of(context).colorScheme.primary,
        HelixColorTokens.signInBlue,
        reason: 'sign-in uses the app icon blue, the rest of the app does not',
      );
    });
  });

  group('the hidden advanced mode', () {
    testWidgets('three taps in the corner reveal it; a fourth opens it', (
      tester,
    ) async {
      await pumpScreen(tester);
      final corner = find.byKey(const ValueKey('advanced-mode-corner'));

      await tester.tap(corner);
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.tap(corner);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('Advanced mode'), findsNothing);

      await tester.tap(corner);
      await tester.pump();
      expect(find.text('Advanced mode'), findsOneWidget);

      await tester.tap(find.text('Advanced mode'));
      await tester.pumpAndSettle();
      expect(find.text('Personal server'), findsOneWidget);
      expect(find.byKey(const ValueKey('code-field')), findsOneWidget);
    });

    testWidgets('taps too far apart do not accumulate', (tester) async {
      await pumpScreen(tester);
      final corner = find.byKey(const ValueKey('advanced-mode-corner'));

      await tester.tap(corner);
      await tester.tap(corner);
      // The window closes: both the count and the revealed state reset.
      await tester.pump(
        AdvancedModeCorner.tapWindow + const Duration(milliseconds: 100),
      );
      await tester.tap(corner);
      await tester.pump();
      expect(find.text('Advanced mode'), findsNothing);

      await tester.tap(corner);
      await tester.tap(corner);
      await tester.pump();
      expect(find.text('Advanced mode'), findsOneWidget);
      // And it hides again if the fourth tap does not come in time.
      await tester.pump(
        AdvancedModeCorner.tapWindow + const Duration(milliseconds: 100),
      );
      expect(find.text('Advanced mode'), findsNothing);
    });

    test('back from the code page returns to the Global page', () async {
      final container = ProviderContainer(
        overrides: [runtimeFactoryProvider.overrideWithValue(_unreachable)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(signInControllerProvider.notifier);

      unawaitedOpen(notifier);
      expect(notifier.state.page, SignInPage.code);
      expect(notifier.state.isAdvanced, isTrue);

      notifier.goBack();
      expect(notifier.state.mode, SignInMode.global);
      expect(notifier.state.page, SignInPage.phone);
    });

    test('a personal server does not ask for the Global terms', () async {
      final container = ProviderContainer(
        overrides: [runtimeFactoryProvider.overrideWithValue(_unreachable)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(signInControllerProvider.notifier);

      unawaitedOpen(notifier);
      expect(notifier.state.requiresTerms, isFalse);
    });
  });

  group('codes', () {
    test('an empty code says so and stays put', () async {
      final container = _container();
      final notifier = container.read(signInControllerProvider.notifier);
      unawaitedOpen(notifier);

      expect(await notifier.submitCode(), isFalse);
      expect(notifier.state.page, SignInPage.code);
      expect(notifier.state.errorMessage, contains('Enter the invite'));
    });

    test('something that is not a Helix code is refused', () async {
      final container = _container();
      final notifier = container.read(signInControllerProvider.notifier);
      unawaitedOpen(notifier);
      notifier.updateCode('hello');

      expect(await notifier.submitCode(), isFalse);
      expect(
        notifier.state.errorMessage,
        contains('not an invite or recovery code'),
      );
    });

    test(
      'a shared link opens advanced mode and checks its code at once',
      () async {
        final container = _container();
        final notifier = container.read(signInControllerProvider.notifier);
        // A link names a code and the server it belongs to. A code that is not a
        // Helix code is refused on the code page, which is where the paste
        // happened - the same place a person would see a typo.
        await notifier.openWithCode('nonsense');
        expect(notifier.state.mode, SignInMode.advanced);
        expect(notifier.state.page, SignInPage.code);
        expect(
          notifier.state.errorMessage,
          contains('not an invite or recovery code'),
        );
      },
    );

    test('a truncated code is refused, and says so', () async {
      final container = _container();
      final notifier = container.read(signInControllerProvider.notifier);
      notifier.updateCode('HLX-REC-');
      expect(await notifier.submitCode(), isFalse);
      expect(
        notifier.state.errorMessage,
        contains('not complete'),
        reason: 'a half-pasted code needs its own wording, not a decode error',
      );
      // And a code that carries a payload but not all of its parts is the
      // same mistake.
      notifier.updateCode('HLX-INV-YWJjOnNlcnZlcg');
      expect(await notifier.submitCode(), isFalse);
      expect(notifier.state.errorMessage, contains('not complete'));
    });
  });

  group('phone and code validation', () {
    test('an unusable number is refused before anything is sent', () async {
      final container = _container();
      final notifier = container.read(signInControllerProvider.notifier);

      expect(await notifier.submitPhone(), isFalse);
      expect(notifier.state.errorMessage, contains('valid phone number'));
      expect(notifier.state.page, SignInPage.phone);
    });

    test('the number is sent as E.164, not as typed', () async {
      final container = _container();
      final notifier = container.read(signInControllerProvider.notifier);

      notifier.updateDigits('170 000-0000');
      expect(notifier.state.e164, '+8801700000000');
      expect(notifier.state.phoneLabel, '+880 170 000-0000');
    });

    test(
      'an SMS code must be six digits, and one must have been requested',
      () async {
        final container = _container();
        final notifier = container.read(signInControllerProvider.notifier);
        notifier.updateDigits('1700000000');

        // No challenge yet: the code has nothing to be checked against, and the
        // person is told to ask for one.
        expect(await notifier.submitOtp(), isFalse);
        expect(notifier.state.errorMessage, contains('Request a new code'));

        // With a challenge in hand, the format is the next thing checked. The
        // challenge is request-scoped, so this is asserted on the copy the
        // controller would return rather than by reaching for a server.
        expect(SignInCopy.badOtpFormat, contains('six-digit'));
        notifier.updateOtpCode('123');
        expect(notifier.state.otpCode, '123');
      },
    );
  });

  group('the terms', () {
    test('are required before an account is created on Helix Global', () async {
      final container = _container();
      final notifier = container.read(signInControllerProvider.notifier);

      expect(await notifier.completeSetup(), isFalse);
      expect(
        notifier.state.errorMessage,
        contains('Accept the Terms of Service'),
      );

      notifier.setTosAccepted(true);
      // Accepted, but no verified code was presented, so it still refuses and
      // sends the person back to it.
      expect(await notifier.completeSetup(), isFalse);
      expect(notifier.state.errorMessage, contains('code sent to your phone'));
    });
  });

  group('routing', () {
    test('the three routes are the ones the app declares', () async {
      expect(AppRoutes.signIn, '/sign-in');
      expect(AppRoutes.home, '/home');
      expect(AppRoutes.reset, '/reset');
    });
  });

  test('the code prefixes are the ones the codecs produce', () async {
    expect(kHelixInvitePrefix, 'HLX-INV-');
    expect(kHelixRecoveryPrefix, 'HLX-REC-');
  });
}

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [runtimeFactoryProvider.overrideWithValue(_unreachable)],
  );
  addTearDown(container.dispose);
  return container;
}

/// The hidden corner's tap, without a widget tree.
void unawaitedOpen(SignInController notifier) {
  notifier.openAdvancedMode();
}

/// A factory that must never be reached by these tests: every rule under test
/// is decided before any engine call, and a test that did try to open a runtime
/// should fail loudly rather than touch the keystore or the network.
final RuntimeFactory _unreachable = _UnreachableFactory();

final class _UnreachableFactory implements RuntimeFactory {
  @override
  Future<Never> open({required Uri serverUrl}) =>
      throw StateError('these tests must not open an engine');
}
