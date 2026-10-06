import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/backup/application/backup_models.dart';
import 'package:helix_remote/features/backup/application/backup_providers.dart';
import 'package:helix_remote/features/backup/application/restore_step.dart';
import 'package:helix_remote/features/backup/presentation/transfer_tile.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:helix_remote/shared/widgets/inline_notice.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Restores the history backup onto this phone.
///
/// Shown in two places. With [afterSignIn] it is the last step of signing in on
/// a new device: restore, or skip, and then the home tabs. Without it, it is
/// Settings > Backup > Restore history, and it simply goes back when done.
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
    final theme = Theme.of(context);
    final running = flow.stage == RestoreStage.running;

    void leave() {
      if (afterSignIn) {
        ref.read(restoreStepProvider).finish();
        context.go(RoutePaths.home);
      } else {
        context.pop();
      }
    }

    return PopScope(
      canPop: !afterSignIn,
      child: Scaffold(
        appBar: AppBar(
          title: Text(afterSignIn ? 'Restore your chats' : 'Restore history'),
          automaticallyImplyLeading: !afterSignIn,
        ),
        body: ListView(
          children: [
            PageIntro(
              title: afterSignIn ? 'Welcome back' : null,
              text:
                  'If you backed up on another phone, your text messages can '
                  'come back here. Photos, videos and files are not in the '
                  'backup. Messages already on this phone are kept as they '
                  'are.',
            ),
            if (offers.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HelixSpace.md,
                  HelixSpace.md,
                  HelixSpace.md,
                  0,
                ),
                child: Text(
                  'From your other devices',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              for (final offer in offers)
                TransferTile(
                  view: offer,
                  busy: offerActions.busy.contains(offer.id),
                  error: offerActions.errorFor(offer.id),
                  onAccept: () =>
                      ref.read(offerActionsProvider.notifier).accept(offer.id),
                  onDecline: () =>
                      ref.read(offerActionsProvider.notifier).decline(offer.id),
                  onPause: () =>
                      ref.read(offerActionsProvider.notifier).pause(offer.id),
                ),
              const Divider(),
            ],
            if (running)
              Padding(
                padding: const EdgeInsets.all(HelixSpace.md),
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(flow.phase ?? 'Working...'),
                      const SizedBox(height: HelixSpace.xs),
                      const LinearProgressIndicator(),
                      if (flow.added > 0 || flow.existing > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: HelixSpace.xs),
                          child: Text('${flow.added} messages added so far'),
                        ),
                    ],
                  ),
                ),
              ),
            if (flow.stage == RestoreStage.failed)
              InlineNotice(kind: InlineNoticeKind.error, message: flow.error!),
            if (flow.stage == RestoreStage.done)
              InlineNotice(
                kind: InlineNoticeKind.success,
                message: flow.added == 0
                    ? 'Your backup is already on this phone. Nothing new to '
                          'add.'
                    : 'Restored ${flow.added} messages.',
              ),
            if (flow.stage == RestoreStage.done)
              BusyFilledButton(
                label: afterSignIn ? 'Continue' : 'Done',
                onPressed: leave,
              )
            else ...[
              BusyFilledButton(
                label: flow.stage == RestoreStage.failed
                    ? 'Try again'
                    : 'Restore from my backup',
                icon: Icons.download_for_offline_outlined,
                busy: running,
                onPressed: () =>
                    ref.read(restoreFlowProvider.notifier).restore(),
              ),
              BusyFilledButton(
                label: 'I have a recovery secret',
                tonal: true,
                onPressed: running
                    ? null
                    : () => context.push(RoutePaths.backupRecovery),
              ),
              if (afterSignIn)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HelixSpace.md,
                  ),
                  child: TextButton(
                    onPressed: running ? null : leave,
                    child: const Text('Skip for now'),
                  ),
                ),
            ],
            if (afterSignIn)
              const PageIntro(
                text: 'You can restore later from Settings, Backup.',
              ),
          ],
        ),
      ),
    );
  }
}
