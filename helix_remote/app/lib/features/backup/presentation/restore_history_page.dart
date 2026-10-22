import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/backup/application/backup_copy.dart';
import 'package:helix_remote/features/backup/application/backup_models.dart';
import 'package:helix_remote/features/backup/application/backup_providers.dart';
import 'package:helix_remote/features/backup/application/restore_step.dart';
import 'package:helix_remote/features/backup/application/transfer_rows.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Restores the history backup onto this phone: the Orbit `RestoreScreen`
/// on the app's restore flow and history offers.
///
/// Shown in two places. With [afterSignIn] it is the last step of signing in on
/// a new device: restore, or skip, and then the home tabs. Without it, it is
/// You > Backup > Restore history, and it simply goes back when done.
/// Either way a restore adds what is missing and never replaces what is here,
/// so running it twice is safe.
class RestoreHistoryPage extends ConsumerWidget {
  const RestoreHistoryPage({super.key, this.afterSignIn = false});

  final bool afterSignIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(restoreFlowProvider);
    final offers = [
      for (final o
          in ref.watch(incomingOffersProvider).value ?? const <TransferView>[])
        if (!o.isFinished) o,
    ];
    final offerActions = ref.watch(offerActionsProvider);

    void leave() {
      if (afterSignIn) {
        // Leaving the step clears it, or the router keeps sending you back.
        ref.read(restoreStepProvider).finish();
        context.go(RoutePaths.home);
      } else {
        context.pop();
      }
    }

    void onOffer(String id, String action) {
      final offer = ref.read(offerActionsProvider.notifier);
      switch (action) {
        case 'Accept' || 'Resume' || 'Try again':
          offer.accept(id);
        case 'Decline':
          offer.decline(id);
        case 'Pause':
          offer.pause(id);
      }
    }

    return PopScope(
      // System Back does nothing on the step after sign-in.
      canPop: !afterSignIn,
      child: RestoreScreen(
        model: restoreModel(
          flow,
          afterSignIn: afterSignIn,
          offers: [
            for (final o in offers)
              (
                transferRow(o, error: offerActions.errorFor(o.id)),
                offerActions.busy.contains(o.id),
              ),
          ],
        ),
        actions: RestoreActions(
          onRestore: () => ref.read(restoreFlowProvider.notifier).restore(),
          onRecoverySecret: () =>
              context.push('${RoutePaths.backupRecovery}?tab=restore'),
          onSkip: leave,
          onContinue: leave,
          onBack: afterSignIn ? null : () => context.pop(),
          onOfferAction: onOffer,
        ),
      ),
    );
  }
}

/// The screen's model for [flow] (`orbit/contracts/signin.md`, Restore).
@visibleForTesting
RestoreModel restoreModel(
  RestoreFlowState flow, {
  required bool afterSignIn,
  List<(TransferRow, bool)> offers = const [],
}) {
  final problem = flow.problem;
  final status = switch (flow.stage) {
    RestoreStage.idle => RestoreStatus.idle,
    RestoreStage.running => RestoreStatus.running,
    RestoreStage.done when flow.added == 0 => RestoreStatus.nothing,
    RestoreStage.done => RestoreStatus.done,
    RestoreStage.failed
        when problem == BackupProblem.wrongKey ||
            problem == BackupProblem.accountMismatch =>
      RestoreStatus.locked,
    RestoreStage.failed => RestoreStatus.failed,
  };
  return RestoreModel(
    afterSignIn: afterSignIn,
    status: status,
    step: flow.step,
    addedSoFar: flow.added > 0 || flow.existing > 0
        ? '${messageCount(flow.added)} messages added so far'
        : null,
    doneTitle: 'Restored ${messageCount(flow.added)} messages',
    failureTitle: problem == null
        ? 'The restore did not finish'
        : backupProblemTitle(problem),
    failureText: flow.error ?? 'That did not work. Try again.',
    offers: [
      for (final (row, busy) in offers)
        RestoreOfferModel(
          id: row.id,
          title: row.title,
          status: row.status,
          progress: row.progress,
          buttons: row.buttons,
          busy: busy,
        ),
    ],
  );
}
