import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/post_sign_in.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote/features/backup/application/backup_copy.dart';
import 'package:helix_remote/features/backup/application/backup_models.dart';
import 'package:helix_remote/features/backup/application/backup_providers.dart';
import 'package:helix_remote/features/backup/presentation/backup_page.dart';
import 'package:helix_remote/features/backup/presentation/recovery_backup_page.dart';
import 'package:helix_remote/features/backup/presentation/restore_history_page.dart';
import 'package:helix_remote/features/backup/presentation/transfer_page.dart';
import 'package:helix_remote/shared/format.dart';
import 'package:helix_remote/shared/route_paths.dart';

import '../support/a3b_fakes.dart';

/// Settings > Backup, the restore step, device-to-device transfer and the
/// recovery backup: the real pages and notifiers over a fake gateway.
void main() {
  group('Backup page', () {
    testWidgets('says when the last backup was and how big it is', (
      tester,
    ) async {
      final backup = FakeBackupGateway();
      await pumpPage(
        tester,
        const BackupPage(),
        overrides: a3bOverrides(backup: backup),
      );
      await settle(tester);

      expect(find.text('Last backup'), findsOneWidget);
      expect(
        find.textContaining('1 hour ago. 1,204 messages, 2.3 MB'),
        findsOneWidget,
      );
      // It says what a backup holds, and what it does not.
      expect(find.textContaining('not the files themselves'), findsOneWidget);
      // The schedule is the engine's, so it is stated, not offered.
      expect(find.textContaining('once a day'), findsOneWidget);
    });

    testWidgets('the automatic switch and the mobile-data switch write', (
      tester,
    ) async {
      final backup = FakeBackupGateway();
      final settings = FakeLocalSettings();
      await pumpPage(
        tester,
        const BackupPage(),
        overrides: a3bOverrides(backup: backup, settings: settings),
      );
      await settle(tester);

      await tester.tap(find.text('Back up automatically'));
      await settle(tester);
      expect(backup.calls, contains('setAutoBackup:false'));

      expect(settings.read(AppSettings.backupOverMobile), isFalse);
      await tester.tap(find.text('Use mobile data'));
      await settle(tester);
      expect(settings.read(AppSettings.backupOverMobile), isTrue);
    });

    testWidgets('Back up now shows progress, then confirms', (tester) async {
      final backup = FakeBackupGateway()..holdBackUp = Completer<void>();
      await pumpPage(
        tester,
        const BackupPage(),
        overrides: a3bOverrides(backup: backup),
      );
      await settle(tester);

      await tester.tap(find.text('Back up now'));
      await settle(tester);
      expect(find.text('Backing up...'), findsOneWidget);

      backup.backupEvents.add(
        const BackupRunProgress(RunPhase.preparing, messages: 400),
      );
      await settle(tester);
      expect(find.text('Backing up... 400 messages'), findsOneWidget);

      backup.holdBackUp!.complete();
      await settle(tester);
      expect(find.text('Your history is backed up.'), findsOneWidget);
      expect(find.text('Backing up...'), findsNothing);
    });

    testWidgets('a failed backup says why, in words', (tester) async {
      final backup = FakeBackupGateway()..backUpFails = BackupProblem.offline;
      await pumpPage(
        tester,
        const BackupPage(),
        overrides: a3bOverrides(backup: backup),
      );
      await settle(tester);

      await tester.tap(find.text('Back up now'));
      await settle(tester);
      expect(
        find.text(backupProblemText(BackupProblem.offline)),
        findsOneWidget,
      );
    });

    testWidgets('a refused upload on mobile data points at the switch', (
      tester,
    ) async {
      final backup = FakeBackupGateway()
        ..backUpFails = BackupProblem.notAllowed;
      await pumpPage(
        tester,
        const BackupPage(),
        overrides: a3bOverrides(backup: backup),
      );
      await settle(tester);

      await tester.tap(find.text('Back up now'));
      await settle(tester);
      expect(find.textContaining('mobile data'), findsWidgets);
      expect(find.textContaining('connect to Wi-Fi'), findsOneWidget);
    });

    testWidgets('the last failure from a scheduled backup is shown', (
      tester,
    ) async {
      final backup = FakeBackupGateway();
      backup.summary.set(
        BackupSummary(
          lastBackupAt: DateTime(2026, 10, 2, 9),
          lastProblem: BackupProblem.tooLarge,
        ),
      );
      await pumpPage(
        tester,
        const BackupPage(),
        overrides: a3bOverrides(backup: backup),
      );
      await settle(tester);

      expect(
        find.textContaining('The last backup did not finish'),
        findsOneWidget,
      );
      expect(find.textContaining('too large'), findsOneWidget);
    });

    testWidgets('deleting the server backup asks first', (tester) async {
      final backup = FakeBackupGateway();
      await pumpPage(
        tester,
        const BackupPage(),
        overrides: a3bOverrides(backup: backup),
      );
      await settle(tester);

      await reveal(tester, find.text('Delete my server backup'));
      await tester.tap(find.text('Delete my server backup'));
      await settle(tester);
      expect(find.text('Delete the server backup?'), findsOneWidget);
      expect(backup.calls, isNot(contains('deleteServerBackup')));

      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(backup.calls, isNot(contains('deleteServerBackup')));

      await tester.tap(find.text('Delete my server backup'));
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      expect(backup.calls, contains('deleteServerBackup'));
    });

    testWidgets('links open the restore, transfer and recovery pages', (
      tester,
    ) async {
      final router = await pumpPage(
        tester,
        const BackupPage(),
        overrides: a3bOverrides(backup: FakeBackupGateway()),
        stubs: [
          RoutePaths.backupRestore,
          RoutePaths.backupTransfer,
          RoutePaths.backupRecovery,
        ],
      );
      await settle(tester);

      await reveal(tester, find.text('Restore history'));
      await tester.tap(find.text('Restore history'));
      await settle(tester);
      expect(find.text('stub:${RoutePaths.backupRestore}'), findsOneWidget);
      expect(router, isNotNull);
    });

    testWidgets('shows how many transfers are waiting', (tester) async {
      final backup = FakeBackupGateway();
      backup.offers.set(const [
        TransferView(
          id: 'o1',
          direction: TransferDirection.receiving,
          stage: TransferStage.waiting,
          deviceName: 'Office laptop',
        ),
      ]);
      await pumpPage(
        tester,
        const BackupPage(),
        overrides: a3bOverrides(backup: backup),
      );
      await settle(tester);
      await reveal(tester, find.text('Send to my other devices'));
      expect(find.text('1 waiting to be received'), findsOneWidget);
    });
  });

  group('Restore history', () {
    Future<FakeBackupGateway> open(
      WidgetTester tester, {
      bool afterSignIn = false,
      FakeBackupGateway? gateway,
      ProviderContainer? container,
    }) async {
      final backup = gateway ?? FakeBackupGateway();
      await pumpPage(
        tester,
        RestoreHistoryPage(afterSignIn: afterSignIn),
        overrides: a3bOverrides(backup: backup),
        stubs: [RoutePaths.home, RoutePaths.backupRecovery],
      );
      await settle(tester);
      return backup;
    }

    testWidgets('restores, with progress, then continues', (tester) async {
      final backup = FakeBackupGateway()..holdRestore = Completer<void>();
      await open(tester, gateway: backup, afterSignIn: true);

      expect(find.text('Restore your chats'), findsOneWidget);
      await tester.tap(find.text('Restore from my backup'));
      await settle(tester);
      expect(find.text('Looking for your backup...'), findsOneWidget);

      backup.restoreEvents.add(
        const RestoreRunProgress(RestorePhase.decrypting),
      );
      await settle(tester);
      expect(find.text('Unlocking it...'), findsOneWidget);
      backup.restoreEvents.add(
        const RestoreRunProgress(
          RestorePhase.importing,
          added: 60,
          existing: 1,
        ),
      );
      await settle(tester);
      expect(find.text('Adding messages...'), findsOneWidget);
      expect(find.text('60 messages added so far'), findsOneWidget);

      backup.holdRestore!.complete();
      await settle(tester);
      expect(find.text('Restored 120 messages.'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    for (final problem in [
      BackupProblem.wrongKey,
      BackupProblem.corrupt,
      BackupProblem.newerFormat,
      BackupProblem.offline,
      BackupProblem.noBackup,
      BackupProblem.rolledBack,
    ]) {
      testWidgets('${problem.name}: says what happened and offers a retry', (
        tester,
      ) async {
        final backup = FakeBackupGateway()..restoreFails = problem;
        await open(tester, gateway: backup, afterSignIn: true);

        await tester.tap(find.text('Restore from my backup'));
        await settle(tester);
        expect(find.text(backupProblemText(problem)), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
        // Whatever went wrong, the person can still carry on.
        expect(find.text('Skip for now'), findsOneWidget);

        backup.restoreFails = null;
        await tester.tap(find.text('Try again'));
        await settle(tester);
        expect(find.text('Restored 120 messages.'), findsOneWidget);
      });
    }

    testWidgets('an empty restore says there was nothing new', (tester) async {
      final backup = FakeBackupGateway()
        ..restoreOutcome = const RestoreOutcome(added: 0, existing: 10);
      await open(tester, gateway: backup);
      await tester.tap(find.text('Restore from my backup'));
      await settle(tester);
      expect(find.textContaining('Nothing new to add'), findsOneWidget);
    });

    testWidgets('skipping clears the post-sign-in step', (tester) async {
      final container = ProviderContainer(
        overrides: a3bOverrides(backup: FakeBackupGateway()),
      );
      addTearDown(container.dispose);
      container.read(postSignInProvider.notifier).offerRestore();
      final router = await pumpPage(
        tester,
        const RestoreHistoryPage(afterSignIn: true),
        container: container,
        stubs: [RoutePaths.home, RoutePaths.backupRecovery],
      );
      await settle(tester);

      await tester.tap(find.text('Skip for now'));
      await settle(tester);
      expect(container.read(postSignInProvider), PostSignInStep.none);
      expect(router.routeInformationProvider.value.uri.path, RoutePaths.home);
    });

    testWidgets(
      'after sign-in there is no back button; from Settings there is',
      (tester) async {
        await open(tester, afterSignIn: true);
        expect(find.byType(BackButton), findsNothing);
        expect(find.text('Skip for now'), findsOneWidget);
      },
    );

    testWidgets('lists offers from other devices with accept and decline', (
      tester,
    ) async {
      final backup = FakeBackupGateway();
      backup.offers.set(const [
        TransferView(
          id: 'o1',
          direction: TransferDirection.receiving,
          stage: TransferStage.waiting,
          deviceName: 'Office laptop',
        ),
      ]);
      await open(tester, gateway: backup, afterSignIn: true);

      expect(find.text('History from Office laptop'), findsOneWidget);
      await tester.tap(find.text('Accept'));
      await settle(tester);
      expect(backup.calls, contains('acceptOffer:o1'));

      await tester.tap(find.text('Decline'));
      await settle(tester);
      expect(backup.calls, contains('declineOffer:o1'));
    });
  });

  group('Transfer page', () {
    testWidgets('sending shows an offer with a cancel button', (tester) async {
      final backup = FakeBackupGateway();
      await pumpPage(
        tester,
        const TransferPage(),
        overrides: a3bOverrides(backup: backup),
      );
      await settle(tester);

      await tester.tap(find.text('Send my history'));
      await settle(tester);
      expect(backup.calls, contains('sendHistory'));
      expect(find.text('Sending your history'), findsOneWidget);
      expect(
        find.textContaining('Waiting for your other device'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(backup.calls, contains('cancelSend:t1'));
      expect(find.text('Cancelled'), findsOneWidget);
    });

    testWidgets('progress follows the engine', (tester) async {
      final backup = FakeBackupGateway();
      await pumpPage(
        tester,
        const TransferPage(),
        overrides: a3bOverrides(backup: backup),
      );
      await settle(tester);
      await tester.tap(find.text('Send my history'));
      await settle(tester);

      backup.transferEvents.add(
        const TransferView(
          id: 't1',
          direction: TransferDirection.sending,
          stage: TransferStage.preparing,
          done: 1,
          total: 4,
        ),
      );
      await settle(tester);
      expect(find.text('Getting your history ready (1 of 4)'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsWidgets);
    });

    testWidgets('a lone device gets a plain explanation', (tester) async {
      final backup = FakeBackupGateway()
        ..sendFails = BackupProblem.noOtherDevices;
      await pumpPage(
        tester,
        const TransferPage(),
        overrides: a3bOverrides(backup: backup),
      );
      await settle(tester);
      await tester.tap(find.text('Send my history'));
      await settle(tester);
      expect(
        find.text(backupProblemText(BackupProblem.noOtherDevices)),
        findsOneWidget,
      );
    });

    testWidgets('receiving: accept, pause and resume keep the same offer', (
      tester,
    ) async {
      final backup = FakeBackupGateway();
      backup.offers.set(const [
        TransferView(
          id: 'o1',
          direction: TransferDirection.receiving,
          stage: TransferStage.downloading,
          done: 2,
          total: 5,
          deviceName: 'Office laptop',
        ),
      ]);
      await pumpPage(
        tester,
        const TransferPage(),
        overrides: a3bOverrides(backup: backup),
      );
      await settle(tester);

      expect(find.text('Receiving (2 of 5)'), findsOneWidget);
      await tester.tap(find.text('Pause'));
      await settle(tester);
      expect(backup.calls, contains('pauseOffer:o1'));

      // The engine puts a paused offer back to waiting; what was fetched is
      // kept, so the button says Resume rather than Accept.
      backup.offers.set(const [
        TransferView(
          id: 'o1',
          direction: TransferDirection.receiving,
          stage: TransferStage.waiting,
          done: 2,
          total: 5,
          deviceName: 'Office laptop',
        ),
      ]);
      await settle(tester);
      await tester.tap(find.text('Resume'));
      await settle(tester);
      expect(backup.calls, contains('acceptOffer:o1'));
    });

    testWidgets('a failed accept is shown on that offer', (tester) async {
      final backup = FakeBackupGateway()..acceptFails = BackupProblem.expired;
      backup.offers.set(const [
        TransferView(
          id: 'o1',
          direction: TransferDirection.receiving,
          stage: TransferStage.waiting,
        ),
      ]);
      await pumpPage(
        tester,
        const TransferPage(),
        overrides: a3bOverrides(backup: backup),
      );
      await settle(tester);

      await tester.tap(find.text('Accept'));
      await settle(tester);
      expect(
        find.text(backupProblemText(BackupProblem.expired)),
        findsOneWidget,
      );
    });

    testWidgets('empty state says nothing is waiting', (tester) async {
      await pumpPage(
        tester,
        const TransferPage(),
        overrides: a3bOverrides(backup: FakeBackupGateway()),
      );
      await settle(tester);
      expect(find.textContaining('Nothing is waiting'), findsOneWidget);
    });
  });

  group('Recovery backup', () {
    testWidgets('shows a secret once, asks for confirmation, then creates', (
      tester,
    ) async {
      final backup = FakeBackupGateway();
      await pumpPage(
        tester,
        const RecoveryBackupPage(),
        overrides: a3bOverrides(backup: backup),
      );
      await settle(tester);

      // Six groups of four, no lookalike characters.
      final secretFinder = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            RegExp(r'^([A-Z2-9]{4}-){5}[A-Z2-9]{4}$').hasMatch(w.data ?? ''),
      );
      expect(secretFinder, findsOneWidget);
      final secret = (tester.widget<Text>(secretFinder)).data!;

      // Not creatable until the person says they wrote it down.
      final create = find.widgetWithText(
        FilledButton,
        'Create recovery backup',
      );
      expect(tester.widget<FilledButton>(create).onPressed, isNull);

      await tester.tap(find.text('I have written it down'));
      await settle(tester);
      expect(tester.widget<FilledButton>(create).onPressed, isNotNull);
      await tester.tap(create);
      await settle(tester);

      expect(backup.calls, contains('createRecoveryBackup'));
      expect(backup.lastSecret, secret);
      expect(find.text('Recovery backup created.'), findsOneWidget);
      expect(find.textContaining('not stored anywhere'), findsOneWidget);
    });

    testWidgets('the secret is never offered for copying', (tester) async {
      await pumpPage(
        tester,
        const RecoveryBackupPage(),
        overrides: a3bOverrides(backup: FakeBackupGateway()),
      );
      await settle(tester);
      expect(find.byTooltip('Copy'), findsNothing);
      expect(find.textContaining('Copy'), findsNothing);
      expect(find.textContaining('written'), findsWidgets);
    });

    testWidgets('a secret the engine refuses is explained', (tester) async {
      final backup = FakeBackupGateway()
        ..recoveryCreateFails = BackupProblem.weakSecret;
      await pumpPage(
        tester,
        const RecoveryBackupPage(),
        overrides: a3bOverrides(backup: backup),
      );
      await settle(tester);

      await tester.tap(find.text('Type my own instead'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'short');
      await tester.tap(find.text('I have written it down'));
      await settle(tester);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Create recovery backup'),
      );
      await settle(tester);
      expect(
        find.text(backupProblemText(BackupProblem.weakSecret)),
        findsOneWidget,
      );
    });

    testWidgets('restoring with the wrong secret says so', (tester) async {
      final backup = FakeBackupGateway()
        ..recoveryRestoreFails = BackupProblem.wrongKey;
      await pumpPage(
        tester,
        const RecoveryBackupPage(),
        overrides: a3bOverrides(backup: backup),
      );
      await settle(tester);

      await tester.tap(find.text('Restore'));
      await settle(tester);
      final restore = find.widgetWithText(
        FilledButton,
        'Restore from recovery backup',
      );
      expect(tester.widget<FilledButton>(restore).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'AAAA-BBBB');
      await settle(tester);
      await tester.tap(restore);
      await settle(tester);
      expect(backup.lastSecret, 'AAAA-BBBB');
      expect(
        find.text(backupProblemText(BackupProblem.wrongKey)),
        findsOneWidget,
      );
    });

    testWidgets('restoring with the right secret adds the messages', (
      tester,
    ) async {
      final backup = FakeBackupGateway();
      await pumpPage(
        tester,
        const RecoveryBackupPage(),
        overrides: a3bOverrides(backup: backup),
      );
      await settle(tester);
      await tester.tap(find.text('Restore'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), '  AAAA-BBBB-CCCC-DDDD  ');
      await settle(tester);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Restore from recovery backup'),
      );
      await settle(tester);
      // Only the surrounding whitespace is forgiven.
      expect(backup.lastSecret, 'AAAA-BBBB-CCCC-DDDD');
      expect(find.text('Restored 120 messages.'), findsOneWidget);
    });
  });

  group('helpers', () {
    test('a generated recovery secret meets the engine\'s policy', () {
      final secret = generateRecoverySecret(_Counter());
      expect(secret.length, greaterThanOrEqualTo(16));
      expect(
        RegExp(r'^([A-Z2-9]{4}-){5}[A-Z2-9]{4}$').hasMatch(secret),
        isTrue,
      );
      // No lookalikes.
      expect(secret.contains(RegExp('[01OIL]')), isFalse);
    });

    test('two generated secrets differ', () {
      final a = generateRecoverySecret(_Counter(0));
      final b = generateRecoverySecret(_Counter(7));
      expect(a, isNot(b));
    });

    test('sizes and times read the way a person says them', () {
      final now = DateTime(2026, 10, 3, 12);
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2400000), '2.3 MB');
      expect(formatAgo(null, now), 'Never');
      expect(
        formatAgo(now.subtract(const Duration(seconds: 5)), now),
        'Just now',
      );
      expect(
        formatAgo(now.subtract(const Duration(minutes: 5)), now),
        '5 minutes ago',
      );
      expect(
        formatAgo(now.subtract(const Duration(days: 1)), now),
        'Yesterday',
      );
    });
  });
}

/// A deterministic [Random] for the secret generator.
class _Counter implements Random {
  _Counter([this._n = 0]);

  int _n;

  @override
  int nextInt(int max) => (_n++ * 7 + 3) % max;

  @override
  bool nextBool() => nextInt(2) == 0;

  @override
  double nextDouble() => nextInt(1000) / 1000;
}
