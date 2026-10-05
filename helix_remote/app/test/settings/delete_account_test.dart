import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/settings/application/settings_models.dart';
import 'package:helix_remote/features/settings/presentation/account_page.dart';
import 'package:helix_remote/features/settings/presentation/delete_account_page.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:helix_remote_api/v2.dart' show ApiException, NetworkException;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode;

import '../support/a3b_fakes.dart';

/// Deleting the account: the type-DELETE confirmation, then the proof the
/// account needs (password, a texted code, or this phone's own key), and what
/// the person sees when the server says no.
void main() {
  Future<FakeSettingsGateway> open(
    WidgetTester tester, {
    FakeSettingsGateway? gateway,
    FakeShareAdapter? share,
    double textScale = 1,
  }) async {
    useTallWindow(tester);
    final g = gateway ?? FakeSettingsGateway();
    await pumpRoutes(
      tester,
      initial: '/account',
      textScale: textScale,
      routes: [
        GoRoute(path: '/account', builder: (_, _) => const AccountPage()),
        GoRoute(
          path: RoutePaths.deleteAccount,
          builder: (_, _) => const DeleteAccountPage(),
        ),
        stubRoute(RoutePaths.changePassword),
        stubRoute(RoutePaths.profile),
        stubRoute(RoutePaths.devicesActivity),
      ],
      overrides: a3bOverrides(settingsGateway: g, share: share),
    );
    await settle(tester);
    return g;
  }

  /// From the Account page to the last step.
  Future<void> openDeletePage(WidgetTester tester) async {
    await reveal(tester, find.text('Delete my account'));
    await tester.tap(find.text('Delete my account'));
    await settle(tester);
    expect(find.text('Delete your account?'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await settle(tester);
    expect(find.text('This cannot be undone'), findsOneWidget);
  }

  Future<void> typeDelete(WidgetTester tester, [String word = 'DELETE']) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'Type DELETE to confirm'),
      word,
    );
  }

  Future<void> press(WidgetTester tester, String label) async {
    final button = find.widgetWithText(FilledButton, label);
    await reveal(tester, button);
    await tester.tap(button);
    await settle(tester);
  }

  testWidgets('delete can start with an export', (tester) async {
    final share = FakeShareAdapter();
    final g = await open(tester, share: share);
    await reveal(tester, find.text('Delete my account'));
    await tester.tap(find.text('Delete my account'));
    await settle(tester);
    await tester.tap(find.text('Export first'));
    await settle(tester);
    expect(g.calls, contains('export'));
    expect(share.shared, hasLength(1));
    expect(find.text('This cannot be undone'), findsOneWidget);
  });

  testWidgets('cancelling anywhere deletes nothing', (tester) async {
    final g = await open(tester);
    await reveal(tester, find.text('Delete my account'));
    await tester.tap(find.text('Delete my account'));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.text('Delete your account?'), findsNothing);
    expect(g.calls, isNot(contains('deleteAccount')));

    await openDeletePage(tester);
    await press(tester, 'Cancel');
    expect(find.text('This cannot be undone'), findsNothing);
    expect(g.calls, isNot(contains('deleteAccount')));
  });

  group('an account with a password', () {
    FakeSettingsGateway withPassword() => FakeSettingsGateway()
      ..accountPassword = 'correct horse'
      ..overview = const AccountOverview(
        phoneMasked: '+88017*****01',
        helixName: 'anna.k',
        hasPassword: true,
      );

    testWidgets('needs the word DELETE, and nothing is sent without it', (
      tester,
    ) async {
      final g = await open(tester, gateway: withPassword());
      await openDeletePage(tester);
      await typeDelete(tester, 'delete');
      await tester.enterText(
        find.widgetWithText(TextField, 'Your password'),
        'correct horse',
      );
      await press(tester, 'Delete my account');
      expect(g.calls, isNot(contains('deleteAccount')));
      expect(
        find.textContaining('Type DELETE in capital letters'),
        findsOneWidget,
      );
    });

    testWidgets('asks for the password, and an empty one is not sent', (
      tester,
    ) async {
      final g = await open(tester, gateway: withPassword());
      await openDeletePage(tester);
      expect(find.widgetWithText(TextField, 'Your password'), findsOneWidget);
      // The number is known on this phone: not asked.
      expect(find.widgetWithText(TextField, 'Your phone number'), findsNothing);

      await typeDelete(tester);
      await press(tester, 'Delete my account');
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(g.calls, isNot(contains('deleteAccount')));
    });

    testWidgets('a wrong password is said under the field', (tester) async {
      final g = await open(tester, gateway: withPassword());
      await openDeletePage(tester);
      await typeDelete(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Your password'),
        'wrong',
      );
      await press(tester, 'Delete my account');
      expect(find.text('That is not your password.'), findsOneWidget);
      expect(g.deletedWithPassword, isNull);
      // The page is still there to try again.
      expect(find.text('This cannot be undone'), findsOneWidget);
    });

    testWidgets('a locked account says to wait', (tester) async {
      final g = withPassword()
        ..deleteFails = const ApiException(
          status: 423,
          code: ErrorCode.passwordLocked,
        );
      await open(tester, gateway: g);
      await openDeletePage(tester);
      await typeDelete(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Your password'),
        'anything',
      );
      await press(tester, 'Delete my account');
      expect(find.textContaining('Too many wrong attempts'), findsOneWidget);
    });

    testWidgets('the right password deletes and signs out', (tester) async {
      final g = await open(tester, gateway: withPassword());
      await openDeletePage(tester);
      await typeDelete(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Your password'),
        'correct horse',
      );
      await press(tester, 'Delete my account');
      expect(g.deletedWithPassword, 'correct horse');
      expect(g.deletedWithNumber, isNull);
      expect(find.textContaining('Your account was deleted'), findsOneWidget);
    });

    testWidgets('a device that does not know the number asks for it once', (
      tester,
    ) async {
      final g = withPassword()
        ..overview = const AccountOverview(
          phoneMasked: '+88017*****01',
          hasPassword: true,
          phoneKnownOnDevice: false,
        );
      await open(tester, gateway: g);
      await openDeletePage(tester);
      expect(
        find.widgetWithText(TextField, 'Your phone number'),
        findsOneWidget,
      );

      await typeDelete(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Your password'),
        'correct horse',
      );
      // Without a country code the number is refused before anything is sent.
      await tester.enterText(
        find.widgetWithText(TextField, 'Your phone number'),
        '01711000001',
      );
      await press(tester, 'Delete my account');
      expect(find.textContaining('with its country code'), findsWidgets);
      expect(g.calls, isNot(contains('deleteAccount')));

      await tester.enterText(
        find.widgetWithText(TextField, 'Your phone number'),
        '+88 01711 000001',
      );
      await press(tester, 'Delete my account');
      expect(g.deletedWithNumber, '+8801711000001');
      expect(g.deletedWithPassword, 'correct horse');
    });

    testWidgets('the password is hidden until asked for', (tester) async {
      await open(tester, gateway: withPassword());
      await openDeletePage(tester);
      final field = find.widgetWithText(TextField, 'Your password');
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      await tester.tap(find.text('Show password'));
      await settle(tester);
      expect(tester.widget<TextField>(field).obscureText, isFalse);
    });
  });

  group('an account without a password', () {
    FakeSettingsGateway noPassword() => FakeSettingsGateway()
      ..overview = const AccountOverview(
        phoneMasked: '+88017*****01',
        helixName: 'anna.k',
      );

    testWidgets('proves it with this phone\'s key and asks for nothing', (
      tester,
    ) async {
      final g = await open(tester, gateway: noPassword());
      await openDeletePage(tester);
      expect(find.widgetWithText(TextField, 'Your password'), findsNothing);
      expect(find.widgetWithText(TextField, 'Code'), findsNothing);
      expect(
        find.textContaining('prove it is yours with its own key'),
        findsOne,
      );

      await typeDelete(tester);
      await press(tester, 'Delete my account');
      expect(g.deletedWithDeviceKey, isTrue);
      expect(find.textContaining('Your account was deleted'), findsOneWidget);
    });

    testWidgets('a server that texts asks for the code, then deletes', (
      tester,
    ) async {
      final g = noPassword()..serverWantsCode = true;
      await open(tester, gateway: g);
      await openDeletePage(tester);
      await typeDelete(tester);
      await press(tester, 'Delete my account');

      // The refusal named a code: one was requested, nothing is deleted yet.
      expect(g.calls, contains('requestDeletionCode'));
      expect(g.deletedWithDeviceKey, isFalse);
      expect(
        find.text('We sent a 6-digit code to +88017*****01.'),
        findsOneWidget,
      );

      await tester.enterText(find.widgetWithText(TextField, 'Code'), '000000');
      await press(tester, 'Delete my account');
      expect(find.textContaining('That code did not match'), findsOneWidget);
      expect(g.deletedWithToken, isNull);

      await tester.enterText(find.widgetWithText(TextField, 'Code'), '123456');
      await press(tester, 'Delete my account');
      expect(g.deletedWithToken, 'token-ok');
      expect(find.textContaining('Your account was deleted'), findsOneWidget);
    });

    testWidgets('a code that is not six digits is not sent', (tester) async {
      final g = noPassword()..serverWantsCode = true;
      await open(tester, gateway: g);
      await openDeletePage(tester);
      await typeDelete(tester);
      await press(tester, 'Delete my account');
      await tester.enterText(find.widgetWithText(TextField, 'Code'), '12');
      await press(tester, 'Delete my account');
      expect(find.text('The code is 6 digits.'), findsOneWidget);
      expect(g.calls, isNot(contains('verifyDeletionCode')));
    });

    testWidgets('a new code can be asked for', (tester) async {
      final g = noPassword()..serverWantsCode = true;
      await open(tester, gateway: g);
      await openDeletePage(tester);
      await typeDelete(tester);
      await press(tester, 'Delete my account');
      await tester.tap(find.text('Send a new code'));
      await settle(tester);
      expect(g.calls.where((c) => c == 'requestDeletionCode'), hasLength(2));
    });

    testWidgets('a device without the number asks for it before texting', (
      tester,
    ) async {
      final g = noPassword()
        ..serverWantsCode = true
        ..knownNumber = false;
      await open(tester, gateway: g);
      await openDeletePage(tester);
      await typeDelete(tester);
      await press(tester, 'Delete my account');

      expect(
        find.widgetWithText(TextField, 'Your phone number'),
        findsOneWidget,
      );
      expect(g.sentCodesTo, isEmpty);
      await tester.enterText(
        find.widgetWithText(TextField, 'Your phone number'),
        '+8801711000001',
      );
      await press(tester, 'Send me a code');
      expect(g.sentCodesTo, ['+8801711000001']);
      expect(find.textContaining('We sent a 6-digit code'), findsOneWidget);
    });

    testWidgets('a code that could not be sent is explained', (tester) async {
      final g = noPassword()
        ..serverWantsCode = true
        ..codeRequestFails = const ApiException(
          status: 429,
          code: ErrorCode.rateLimited,
        );
      await open(tester, gateway: g);
      await openDeletePage(tester);
      await typeDelete(tester);
      await press(tester, 'Delete my account');
      expect(find.textContaining('too often'), findsOneWidget);
      expect(g.deletedWithToken, isNull);
    });
  });

  group('when the server says no', () {
    testWidgets('offline says so and deletes nothing', (tester) async {
      final g = FakeSettingsGateway()
        ..overview = const AccountOverview(phoneMasked: '+88017*****01')
        ..deleteFails = const NetworkException();
      await open(tester, gateway: g);
      await openDeletePage(tester);
      await typeDelete(tester);
      await press(tester, 'Delete my account');
      expect(find.textContaining('You are offline'), findsOneWidget);
      expect(find.textContaining('Your account was deleted'), findsNothing);
    });

    testWidgets('a refused delete is explained', (tester) async {
      final g = FakeSettingsGateway()
        ..overview = const AccountOverview(phoneMasked: '+88017*****01')
        ..deleteFails = const ApiException(
          status: 503,
          code: ErrorCode.maintenance,
        );
      await open(tester, gateway: g);
      await openDeletePage(tester);
      await typeDelete(tester);
      await press(tester, 'Delete my account');
      expect(g.calls, contains('deleteAccount'));
      expect(find.textContaining('not available right now'), findsOneWidget);
    });
  });

  testWidgets('the page fits at 2x text', (tester) async {
    final g = FakeSettingsGateway();
    await open(tester, gateway: g, textScale: 2);
    await openDeletePage(tester);
    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(TextField, 'Your password'), findsOneWidget);
  });
}
