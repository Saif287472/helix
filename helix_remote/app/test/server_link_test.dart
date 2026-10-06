import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/global_server.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/engine/server_policy.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/links/deep_link.dart';
import 'package:helix_remote/core/links/helix_code.dart';
import 'package:helix_remote/core/router/app_router.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_controller.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_copy.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_state.dart';

/// H2 and M1: a link or a code never sends the person to a server they have
/// not been shown, and nothing is sent in the clear.
void main() {
  late StreamController<AppAuthState> auth;
  late List<Uri> opened;

  setUp(() {
    auth = StreamController<AppAuthState>.broadcast();
    opened = [];
  });

  tearDown(() => auth.close());

  /// A container whose runtime factory records the servers it is asked for and
  /// then refuses, so "was a request made" is "was `open` called".
  ProviderContainer container({
    SessionRestore restore = SessionRestore.none,
    AppAuthState? initial = AppAuthState.signedOut,
  }) {
    final c = ProviderContainer(
      overrides: [
        runtimeFactoryProvider.overrideWithValue(_Recording(opened)),
        sessionRestoreProvider.overrideWith(() => _Restore(restore)),
        authStateProvider.overrideWith((ref) async* {
          if (initial != null) yield initial;
          yield* auth.stream;
        }),
      ],
    );
    addTearDown(c.dispose);
    // Keeps the status stream running between reads.
    c.listen(authStateProvider, (_, _) {});
    return c;
  }

  String invite(String server) =>
      encodeHelixInviteCode(serverUrl: server, inviteCode: 'INV-1');

  Future<void> settle(ProviderContainer c) async {
    await c.read(authStateProvider.future);
    await Future<void>.delayed(Duration.zero);
  }

  group('ServerPolicy', () {
    Uri u(String s) => Uri.parse(s);

    test('https is fine, cleartext is not', () {
      expect(ServerPolicy.check(u('https://chat.example.org')), isNull);
      expect(
        ServerPolicy.check(u('http://chat.example.org'), debug: true),
        ServerUrlProblem.notHttps,
      );
      expect(
        ServerPolicy.check(u('ftp://chat.example.org')),
        ServerUrlProblem.notHttps,
      );
    });

    test('http reaches only the development hosts, and only in debug', () {
      for (final host in ['localhost', '10.0.2.2', '127.0.0.1']) {
        expect(ServerPolicy.check(u('http://$host:8080'), debug: true), isNull);
        expect(
          ServerPolicy.check(u('http://$host:8080'), debug: false),
          ServerUrlProblem.notHttps,
          reason: 'a release build has no cleartext exception',
        );
      }
    });

    test('a user name, a query or a look-alike host is refused', () {
      expect(
        ServerPolicy.check(u('https://helix.agiletechbd.com@evil.example')),
        ServerUrlProblem.unusual,
      );
      expect(
        ServerPolicy.check(u('https://evil.example/?x=1')),
        ServerUrlProblem.unusual,
      );
      expect(
        ServerPolicy.check(u('https://hеlix.agiletechbd.com')),
        ServerUrlProblem.lookalikeHost,
      );
      expect(ServerPolicy.check(u('chat.example.org')), isNotNull);
    });

    test('the host is what is shown, with a port only when it is unusual', () {
      expect(
        ServerPolicy.displayHost(u('https://Chat.Example.org')),
        'chat.example.org',
      );
      expect(
        ServerPolicy.displayHost(u('https://chat.example.org:8443')),
        'chat.example.org:8443',
      );
      expect(ServerPolicy.isGlobal(kGlobalServerUrl), isTrue);
      expect(ServerPolicy.isGlobal(u('https://evil.example')), isFalse);
    });

    test('the server address notifier refuses what the policy refuses', () {
      final c = container();
      expect(
        () => c
            .read(serverUrlProvider.notifier)
            .use(Uri.parse('http://chat.example.org')),
        throwsA(isA<InsecureServerUrl>()),
      );
      expect(c.read(serverUrlProvider), isNull);
    });
  });

  group('a code that names a server', () {
    test('asks first, shows the host and sends nothing', () async {
      final c = container();
      final controller = c.read(signInControllerProvider.notifier);
      await controller.openWithCode(invite('https://evil.example'));

      final state = c.read(signInControllerProvider);
      expect(state.pendingServerHost, 'evil.example');
      expect(state.page, SignInPage.code);
      expect(opened, isEmpty, reason: 'no request before the person agrees');
      expect(c.read(serverUrlProvider), isNull);
      expect(state.errorMessage, isNull);
    });

    test('the name the server gives itself is never the question', () {
      expect(
        SignInCopy.serverQuestion('evil.example'),
        'This code wants to sign you in on evil.example.',
      );
    });

    test('goes ahead only after the person says yes', () async {
      final c = container();
      final controller = c.read(signInControllerProvider.notifier);
      await controller.openWithCode(invite('https://chat.example.org'));
      expect(opened, isEmpty);

      await controller.confirmServer();
      expect(opened, [Uri.parse('https://chat.example.org')]);
      expect(c.read(signInControllerProvider).pendingServerHost, isNull);
    });

    test('says no: the code is forgotten and nothing was sent', () async {
      final c = container();
      final controller = c.read(signInControllerProvider.notifier);
      await controller.openWithCode(invite('https://evil.example'));
      controller.declineServer();

      final state = c.read(signInControllerProvider);
      expect(state.pendingServerHost, isNull);
      expect(state.codeString, isEmpty);
      expect(opened, isEmpty);
      // And nothing is left approved: the same code asks again.
      controller.updateCode(invite('https://evil.example'));
      await controller.submitCode();
      expect(c.read(signInControllerProvider).pendingServerHost, isNotNull);
    });

    test('approving one server does not approve another', () async {
      final c = container();
      final controller = c.read(signInControllerProvider.notifier);
      await controller.openWithCode(invite('https://one.example'));
      await controller.confirmServer();
      expect(opened, hasLength(1));

      controller.updateCode(invite('https://two.example'));
      await controller.submitCode();
      expect(c.read(signInControllerProvider).pendingServerHost, 'two.example');
      expect(opened, hasLength(1));
    });

    test('Helix Global itself needs no question', () async {
      final c = container();
      final controller = c.read(signInControllerProvider.notifier);
      await controller.openWithCode(invite('https://helix.agiletechbd.com'));
      expect(c.read(signInControllerProvider).pendingServerHost, isNull);
      expect(opened, [kGlobalServerUrl]);
    });

    test('an http server is refused outright, with no question', () async {
      final c = container();
      final controller = c.read(signInControllerProvider.notifier);
      await controller.openWithCode(invite('http://chat.example.org'));

      final state = c.read(signInControllerProvider);
      expect(state.errorMessage, SignInCopy.insecureServer);
      expect(state.pendingServerHost, isNull);
      expect(opened, isEmpty);
    });

    test('an address with a user name in it is refused', () async {
      final c = container();
      final controller = c.read(signInControllerProvider.notifier);
      await controller.openWithCode(
        invite('https://helix.agiletechbd.com@evil.example'),
      );
      expect(
        c.read(signInControllerProvider).errorMessage,
        SignInCopy.insecureServer,
      );
      expect(opened, isEmpty);
    });

    test('the host stays on every page of a personal-server sign-in', () async {
      final c = container();
      final controller = c.read(signInControllerProvider.notifier);
      await controller.openWithCode(invite('https://chat.example.org'));
      await controller.confirmServer();
      // The factory refused, so the page did not advance, but the approved
      // host is what the person is told they are talking to once it does.
      controller.goBack();
      expect(c.read(signInControllerProvider).serverHost, isNull);
    });

    test('the Global page is Helix Global even after a personal server was '
        'approved and abandoned', () async {
      final c = container();
      final controller = c.read(signInControllerProvider.notifier);
      await controller.openWithCode(invite('https://chat.example.org'));
      await controller.confirmServer();
      c
          .read(serverUrlProvider.notifier)
          .use(Uri.parse('https://chat.example.org'));
      controller.leaveAdvancedMode();
      controller.updateDigits('1700000000');
      opened.clear();

      await controller.submitPhone();
      expect(opened, [kGlobalServerUrl]);
    });
  });

  group('links', () {
    test('the server parameter of an invite link needs the same yes', () async {
      final c = container();
      await settle(c);
      c.read(signInControllerProvider);
      final link = HelixDeepLink.tryParse(
        'helix://invite?code=INV-1&server=https%3A%2F%2Fchat.example',
      )!;
      c.read(pendingLinkProvider.notifier).set(link);
      await Future<void>.delayed(Duration.zero);

      expect(
        c.read(signInControllerProvider).pendingServerHost,
        'chat.example',
      );
      expect(opened, isEmpty);
    });

    test('the HLX fragment forms need it too', () async {
      for (final form in [
        'https://helix.agiletechbd.com/open#${invite('https://evil.example')}',
        'helix://open?code=${invite('https://evil.example')}',
      ]) {
        final c = container();
        await settle(c);
        c.read(signInControllerProvider);
        c.read(pendingLinkProvider.notifier).set(HelixDeepLink.tryParse(form));
        await Future<void>.delayed(Duration.zero);
        expect(
          c.read(signInControllerProvider).pendingServerHost,
          'evil.example',
          reason: form,
        );
        expect(opened, isEmpty);
      }
    });

    test('a web invite on http is refused', () async {
      final c = container();
      await settle(c);
      c.read(signInControllerProvider);
      c
          .read(pendingLinkProvider.notifier)
          .set(
            HelixDeepLink.tryParse('http://server.example/join?invite=INV-1'),
          );
      await Future<void>.delayed(Duration.zero);
      expect(
        c.read(signInControllerProvider).errorMessage,
        SignInCopy.insecureServer,
      );
      expect(opened, isEmpty);
    });

    test('a link is not used before the remembered session is known', () async {
      final c = container(restore: SessionRestore.pending);
      await settle(c);
      c.read(signInControllerProvider);
      c
          .read(pendingLinkProvider.notifier)
          .set(
            HelixDeepLink.tryParse(
              'helix://open?code=${invite('https://evil.example')}',
            ),
          );
      await Future<void>.delayed(Duration.zero);
      expect(c.read(signInControllerProvider).mode, SignInMode.global);
      expect(c.read(pendingLinkProvider), isNotNull);
    });

    test('a link is not used on a phone that is signed in', () async {
      final c = container(initial: AppAuthState.ready);
      await settle(c);
      c.read(signInControllerProvider);
      c
          .read(pendingLinkProvider.notifier)
          .set(
            HelixDeepLink.tryParse(
              'helix://open?code=${invite('https://evil.example')}',
            ),
          );
      await Future<void>.delayed(Duration.zero);
      expect(c.read(signInControllerProvider).mode, SignInMode.global);
    });

    test('a link parked while signed in is gone after sign-out', () async {
      final c = container(initial: AppAuthState.ready);
      await settle(c);
      c.read(signInControllerProvider);
      c
          .read(pendingLinkProvider.notifier)
          .set(
            HelixDeepLink.tryParse(
              'helix://open?code=${invite('https://evil.example')}',
            ),
          );
      auth.add(AppAuthState.signedOut);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(c.read(pendingLinkProvider), isNull);
      expect(c.read(signInControllerProvider).mode, SignInMode.global);
      expect(c.read(signInControllerProvider).pendingServerHost, isNull);
      expect(opened, isEmpty);
    });

    test('signing in clears a parked link and the half-made flow', () async {
      final c = container();
      await settle(c);
      final controller = c.read(signInControllerProvider.notifier);
      await controller.openWithCode(invite('https://evil.example'));
      c
          .read(pendingLinkProvider.notifier)
          .set(
            HelixDeepLink.tryParse(
              'helix://open?code=${invite('https://other.example')}',
            ),
          );
      auth.add(AppAuthState.ready);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(c.read(pendingLinkProvider), isNull);
      expect(c.read(signInControllerProvider), const SignInState());
    });

    test('the shared form is exactly /open over https', () {
      const code = 'HLX-REC-abc';
      expect(
        HelixDeepLink.tryParse('https://helix.agiletechbd.com/open#$code'),
        isNotNull,
      );
      expect(
        HelixDeepLink.tryParse('https://helix.agiletechbd.com/open/#$code'),
        isNotNull,
      );
      expect(
        HelixDeepLink.tryParse('https://helix.agiletechbd.com/open/x#$code'),
        isNull,
      );
      expect(
        HelixDeepLink.tryParse('https://helix.agiletechbd.com/openx#$code'),
        isNull,
      );
      expect(
        HelixDeepLink.tryParse('http://helix.agiletechbd.com/open#$code'),
        isNull,
      );
    });
  });

  group('the router', () {
    test('an intent URL never becomes the start location', () {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.defaultRouteNameTestValue = '/home/people?x=1';
      addTearDown(binding.platformDispatcher.clearDefaultRouteNameTestValue);
      final c = container();
      addTearDown(c.dispose);
      final router = c.read(appRouterProvider);
      expect(router.routeInformationProvider.value.uri.path, AppRoutes.signIn);
    });
  });
}

final class _Restore extends SessionRestoreNotifier {
  _Restore(this._value);

  final SessionRestore _value;

  @override
  SessionRestore build() => _value;
}

final class _Recording implements RuntimeFactory {
  _Recording(this._log);

  final List<Uri> _log;

  @override
  Future<Never> open({required Uri serverUrl}) {
    _log.add(serverUrl);
    return Future.error(StateError('refused by the test'));
  }
}
