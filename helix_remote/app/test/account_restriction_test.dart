import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/account_restriction.dart';
import 'package:helix_remote/widgets/account_restriction_gate.dart';

void main() {
  group('AccountRestrictionGate', () {
    final navigatorKey = GlobalKey<NavigatorState>();

    Future<void> pumpGate(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) =>
            AccountRestrictionGate(navigatorKey: navigatorKey, child: child!),
        home: const Scaffold(body: Text('home screen')),
      ),
    );

    tearDown(() {
      AccountRestrictionState.restriction.value = AccountRestriction.none;
      AccountRestrictionState.serverIsGlobal = true;
    });

    testWidgets('suspended keeps the app usable under a banner', (
      tester,
    ) async {
      await pumpGate(tester);
      AccountRestrictionState.restriction.value = AccountRestriction.suspended;
      await tester.pump();

      expect(find.text('home screen'), findsOneWidget);
      expect(
        find.textContaining(
          "Your account is suspended. You can still read messages, but you can't send messages, add contacts or make calls.",
        ),
        findsOneWidget,
      );
      expect(find.text('Contact support'), findsOneWidget);
    });

    testWidgets('a refused action explains the suspension in a dialog', (
      tester,
    ) async {
      await pumpGate(tester);
      AccountRestrictionState.restriction.value = AccountRestriction.suspended;
      AccountRestrictionState.refusedAttempts.value++;
      await tester.pumpAndSettle();

      expect(find.text('Account suspended'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Account suspended'), findsNothing);
    });

    testWidgets('blocked offers exactly the three ways forward', (
      tester,
    ) async {
      await pumpGate(tester);
      AccountRestrictionState.restriction.value = AccountRestriction.blocked;
      await tester.pump();

      expect(find.text('home screen'), findsNothing);
      expect(find.text('This number is blocked'), findsOneWidget);
      expect(find.text('Contact support'), findsOneWidget);
      expect(find.text('Leave the app'), findsOneWidget);

      await tester.tap(find.text('Sign in with a different number'));
      await tester.pump();
      expect(
        AccountRestrictionState.restriction.value,
        AccountRestriction.none,
      );
      expect(find.text('home screen'), findsOneWidget);
    });

    testWidgets('a personal server points at its admin, not Helix support', (
      tester,
    ) async {
      AccountRestrictionState.serverIsGlobal = false;
      await pumpGate(tester);
      AccountRestrictionState.restriction.value = AccountRestriction.blocked;
      await tester.pump();

      expect(find.text('Contact support'), findsNothing);
      expect(
        find.textContaining(
          'Contact the admin of this server to find out why and how to get access back.',
        ),
        findsOneWidget,
      );
    });
  });
}
