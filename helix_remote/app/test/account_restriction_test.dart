import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/account_restriction.dart';
import 'package:helix_remote/l10n/helix_localizations.dart';
import 'package:helix_remote/widgets/account_restriction_gate.dart';

void main() {
  group('AccountRestrictionGate', () {
    final navigatorKey = GlobalKey<NavigatorState>();

    Future<void> pumpGate(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        localizationsDelegates: HelixLocalizations.localizationsDelegates,
        supportedLocales: HelixLocalizations.supportedLocales,
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
      final en = await HelixLocalizations.delegate.load(const Locale('en'));
      AccountRestrictionState.restriction.value = AccountRestriction.suspended;
      await tester.pump();

      expect(find.text('home screen'), findsOneWidget);
      expect(find.textContaining(en.accountSuspendedBanner), findsOneWidget);
      expect(find.text(en.accountRestrictionContactSupport), findsOneWidget);
    });

    testWidgets('a refused action explains the suspension in a dialog', (
      tester,
    ) async {
      await pumpGate(tester);
      final en = await HelixLocalizations.delegate.load(const Locale('en'));
      AccountRestrictionState.restriction.value = AccountRestriction.suspended;
      AccountRestrictionState.refusedAttempts.value++;
      await tester.pumpAndSettle();

      expect(find.text(en.accountSuspendedTitle), findsOneWidget);
      await tester.tap(find.text(en.accountRestrictionOk));
      await tester.pumpAndSettle();
      expect(find.text(en.accountSuspendedTitle), findsNothing);
    });

    testWidgets('blocked offers exactly the three ways forward', (
      tester,
    ) async {
      await pumpGate(tester);
      final en = await HelixLocalizations.delegate.load(const Locale('en'));
      AccountRestrictionState.restriction.value = AccountRestriction.blocked;
      await tester.pump();

      expect(find.text('home screen'), findsNothing);
      expect(find.text(en.accountBlockedTitle), findsOneWidget);
      expect(find.text(en.accountRestrictionContactSupport), findsOneWidget);
      expect(find.text(en.accountBlockedLeaveApp), findsOneWidget);

      await tester.tap(find.text(en.accountBlockedUseDifferentNumber));
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
      final en = await HelixLocalizations.delegate.load(const Locale('en'));
      AccountRestrictionState.restriction.value = AccountRestriction.blocked;
      await tester.pump();

      expect(find.text(en.accountRestrictionContactSupport), findsNothing);
      expect(
        find.textContaining(en.accountRestrictionContactPersonal),
        findsOneWidget,
      );
    });
  });
}
