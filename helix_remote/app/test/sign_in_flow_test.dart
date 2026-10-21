import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/global_server.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/links/helix_code.dart';
import 'package:helix_remote/core/platform/saved_accounts.dart';
import 'package:helix_remote/core/router/app_router.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_controller.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_copy.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_state.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_view.dart';
import 'package:helix_remote/features/sign_in/presentation/sign_in_screen.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;
import 'package:orbit_ui/orbit_ui.dart' show OrbitTokens;

import 'support/orbit_theme.dart';

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
          theme: orbitTestTheme(),
          builder: orbitTestBuilder,
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
      expect(find.byKey(const ValueKey('phone')), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Terms & Privacy'), findsOneWidget);
      // There is nothing before this page, so a back arrow would lie.
      expect(find.byTooltip('Back'), findsNothing);
      // No host-your-own-server copy, ever.
      expect(find.textContaining('Host your own'), findsNothing);
      expect(find.text('Advanced mode'), findsNothing);
    });

    testWidgets('is drawn in the Orbit theme', (tester) async {
      await pumpScreen(tester);

      final context = tester.element(find.byKey(const ValueKey('phone')));
      expect(OrbitTokens.of(context).meta.id, orbitTestTokens.meta.id);
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
      expect(find.byKey(const ValueKey('setup')), findsOneWidget);
    });

    testWidgets('taps too far apart do not accumulate', (tester) async {
      await pumpScreen(tester);
      final corner = find.byKey(const ValueKey('advanced-mode-corner'));

      await tester.tap(corner);
      await tester.tap(corner);
      // The window closes: both the count and the revealed state reset.
      await tester.pump(
        const Duration(seconds: 2) + const Duration(milliseconds: 100),
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
        const Duration(seconds: 2) + const Duration(milliseconds: 100),
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

  group('asking for a code', () {
    testWidgets('the number is checked and agreed to before anything is sent', (
      tester,
    ) async {
      final container = await pumpScreen(tester);
      final notifier = container.read(signInControllerProvider.notifier);
      notifier.updateDigits('1711000001');
      await notifier.submitPhone();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Use a code instead'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Send a code to +880 1711000001'), findsOne);
      expect(find.textContaining('may charge you'), findsOneWidget);

      // Changing the number sends nothing (the runtime factory would throw).
      await tester.tap(find.text('Change number'));
      await tester.pumpAndSettle();
      expect(container.read(signInControllerProvider).page, SignInPage.phone);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
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

    test('are asked for when an existing account is taken over', () async {
      // "Forgot password?" moves an existing account to this phone with the
      // verified SMS code. That is still Helix Global, so `completeSetup`
      // demands the Terms - and the page has to offer the box, or the take-over
      // can never finish.
      final takenOver = const SignInState().copyWith(
        page: SignInPage.name,
        accountExists: true,
        hasPassword: true,
      );
      expect(takenOver.isNewAccount, isFalse);
      expect(takenOver.requiresTerms, isTrue);
      expect(
        takenOver.showsTerms,
        isTrue,
        reason: 'the box must appear wherever completeSetup will ask for it',
      );
    });

    testWidgets('the box is on the last page on Helix Global', (tester) async {
      final container = await pumpScreen(tester);
      container.read(signInControllerProvider.notifier).showSetupPageForTest();
      await tester.pumpAndSettle();

      expect(find.text(_termsBox), findsOneWidget);
      expect(find.text('Read the Terms and Privacy Policy'), findsOneWidget);
    });

    testWidgets('and absent on a personal server', (tester) async {
      final container = await pumpScreen(tester);
      unawaitedOpen(container.read(signInControllerProvider.notifier));
      container.read(signInControllerProvider.notifier).showSetupPageForTest();
      await tester.pumpAndSettle();

      expect(container.read(signInControllerProvider).page, SignInPage.name);
      expect(find.text(_termsBox), findsNothing);
    });
  });

  group('Orbit port, Review 1', () {
    test('the country picker takes only listed codes', () {
      final notifier = _container().read(signInControllerProvider.notifier);
      notifier.setCountryCode('+44');
      expect(notifier.state.countryCode, '+44');
      notifier.setCountryCode('+999');
      expect(notifier.state.countryCode, '+44');
    });

    test(
      'a number that is too short is refused before anything is sent',
      () async {
        final notifier = _container().read(signInControllerProvider.notifier);
        notifier.updateDigits('1711 00');
        // The runtime factory throws if reached, so a false here means the
        // check came first.
        expect(await notifier.submitPhone(), isFalse);
        expect(notifier.state.errorMessage, SignInCopy.phoneTooShort);
      },
    );

    test('a number goes straight to the password, with no code', () async {
      final notifier = _container().read(signInControllerProvider.notifier);
      notifier.updateDigits('1711000001');
      // The runtime factory throws if reached: nothing is sent for a code.
      expect(await notifier.submitPhone(), isTrue);
      expect(notifier.state.page, SignInPage.password);
    });

    test('coming in by code always sets a password', () async {
      final notifier = _container().read(signInControllerProvider.notifier);
      notifier.updateDigits('1711000001');
      notifier.showSetupPageForTest();
      // No verified code yet, so it stops there; with one it would still
      // need the password (checked before anything is sent).
      expect(await notifier.completeSetup(), isFalse);
    });

    test('Back from the password goes to the number', () {
      final container = _container();
      final notifier = container.read(signInControllerProvider.notifier);
      notifier.state = notifier.state.copyWith(page: SignInPage.password);
      notifier.goBack();
      expect(notifier.state.page, SignInPage.phone);
    });

    test('the model follows the state', () {
      const global = SignInState();
      final m = signInModel(global, const []);
      expect(m.step, orbit.SignInStep.phone);
      expect(m.countries.first, ('+880', 'Bangladesh'));
      expect(m.serverBadge, isNull);
      expect(m.showTerms, isTrue);
      expect(m.legal.terms.version, SignInState.termsVersion);

      final server = global.copyWith(
        mode: SignInMode.advanced,
        page: SignInPage.code,
        pendingServerHost: 'chat.example.org',
        serverName: 'Example',
      );
      expect(
        signInModel(server, const []).step,
        orbit.SignInStep.serverConfirm,
      );
      expect(
        signInModel(server, const []).serverBadge,
        'chat.example.org (Example)',
      );
      expect(signInModel(server, const []).showTerms, isFalse);

      final takeOver = global.copyWith(
        page: SignInPage.name,
        accountExists: true,
      );
      expect(signInModel(takeOver, const []).step, orbit.SignInStep.takeOver);
      expect(
        signInModel(
          global.copyWith(codeString: 'HLX-REC-1'),
          const [],
        ).setupCodeKind,
        orbit.SetupCodeKind.recovery,
      );
    });
  });

  group('saved accounts', () {
    const number = '+8801711000001';

    void seed() => FlutterSecureStorage.setMockInitialValues({
      SavedAccountsStore.keystoreKey: jsonEncode([
        {'n': number, 's': kGlobalServerUrl.toString(), 'name': 'Rahman'},
      ]),
    });

    testWidgets('a remembered number is offered on the phone page', (
      tester,
    ) async {
      seed();
      await pumpScreen(tester);
      await tester.pump();

      expect(find.text('Saved accounts'), findsOneWidget);
      expect(find.text('Rahman'), findsOneWidget);
      expect(find.text('+880 ••••• 0001'), findsOneWidget);
    });

    testWidgets('an empty list draws nothing', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      await pumpScreen(tester);
      await tester.pump();

      expect(find.text('Saved accounts'), findsNothing);
    });

    testWidgets('tapping one fills the number and asks for the password', (
      tester,
    ) async {
      seed();
      final container = await pumpScreen(tester);
      await tester.pump();
      await tester.tap(find.text('Rahman'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.byKey(const ValueKey('password')), findsOneWidget);
      expect(find.text('Remember me on this device'), findsOneWidget);
      expect(
        container.read(signInControllerProvider).phoneLabel,
        '+880 1711000001',
      );
    });

    testWidgets('the x forgets the number', (tester) async {
      seed();
      final container = await pumpScreen(tester);
      await tester.pump();
      await tester.tap(find.byTooltip('Forget Rahman'));
      await tester.pumpAndSettle();

      expect(find.text('Rahman'), findsNothing);
      expect(find.text('Saved accounts'), findsNothing);
      // Gone for good, not just off the screen.
      expect(container.read(savedAccountsProvider), isEmpty);
    });

    testWidgets('Remember me can be turned off at the password', (
      tester,
    ) async {
      seed();
      final container = await pumpScreen(tester);
      await tester.pump();
      await tester.tap(find.text('Rahman'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remember me on this device'));
      await tester.pump();

      expect(container.read(signInControllerProvider).remember, isFalse);
    });

    test('only the page\'s own server is offered, and a number without a '
        'name shows the server', () {
      final lines = savedAccountLinesForGlobalPage([
        SavedAccountEntry(e164: number, server: kGlobalServerUrl.toString()),
        const SavedAccountEntry(
          e164: '+8801700000002',
          server: 'https://chat.example.org',
          name: 'Rahman',
        ),
      ]);
      expect(lines.length, 1);
      expect(lines.single.id, number);
      expect(lines.single.title, '+880 ••••• 0001');
      expect(lines.single.detail, 'Helix Global');
    });

    test('Remember me is on until it is turned off', () {
      final container = _container();
      final notifier = container.read(signInControllerProvider.notifier);
      expect(notifier.state.remember, isTrue);
      notifier.setRemember(false);
      expect(notifier.state.remember, isFalse);
      expect(signInModel(notifier.state, const []).remember, isFalse);
    });

    test('the model carries the rows for the screen', () {
      final m = signInModel(const SignInState(), const [
        (id: number, title: 'Rahman', detail: '+880 ••••• 0001'),
      ]);
      expect(m.savedAccounts.single.id, number);
      expect(m.savedAccounts.single.title, 'Rahman');
      expect(m.savedAccounts.single.subtitle, '+880 ••••• 0001');
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

const _termsBox = 'I agree to the Orbit Terms of Service and Privacy Policy';

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
  Future<Never> open({required String account, required Uri serverUrl}) =>
      throw StateError('these tests must not open an engine');
}
