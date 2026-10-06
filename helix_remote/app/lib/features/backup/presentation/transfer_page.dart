import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/backup/application/backup_providers.dart';
import 'package:helix_remote/features/backup/presentation/transfer_tile.dart';
import 'package:helix_remote/shared/widgets/inline_notice.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Settings > Backup > Send to my other devices.
///
/// Both sides of a device-to-device transfer live on this one page, because a
/// phone is usually both at different times: it sends its history to a new
/// device, and receives one when it is the new device. Everything that moves is
/// encrypted before it leaves, and the other device must accept before
/// anything is downloaded.
class TransferPage extends ConsumerWidget {
  const TransferPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(transfersProvider);
    final offers = ref.watch(incomingOffersProvider);
    final offerActions = ref.watch(offerActionsProvider);
    final theme = Theme.of(context);
    final outgoing = transfers.outgoing.values.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Send to my other devices')),
      body: ListView(
        children: [
          const PageIntro(
            text:
                'Copy your chat history straight to another device signed in '
                'to your account. It is encrypted on this phone before it '
                'leaves, so the server only carries data it cannot read, and '
                'the other device has to accept it. Photos, videos and files '
                'are not included.',
          ),
          if (transfers.error != null)
            InlineNotice(
              kind: InlineNoticeKind.error,
              message: transfers.error!,
            ),
          BusyFilledButton(
            label: 'Send my history',
            icon: Icons.send_to_mobile_outlined,
            busy: transfers.starting,
            onPressed: () => ref.read(transfersProvider.notifier).send(),
          ),
          for (final view in outgoing)
            TransferTile(
              view: view,
              onCancel: () =>
                  ref.read(transfersProvider.notifier).cancel(view.id),
              onDismiss: () =>
                  ref.read(transfersProvider.notifier).dismiss(view.id),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HelixSpace.md,
              HelixSpace.lg,
              HelixSpace.md,
              HelixSpace.xs,
            ),
            child: Semantics(
              header: true,
              child: Text(
                'Waiting for this phone',
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
          switch (offers) {
            AsyncData(:final value) when value.isEmpty => const PageIntro(
              text:
                  'Nothing is waiting. When another of your devices sends '
                  'its history, it shows up here.',
            ),
            AsyncData(:final value) => Column(
              children: [
                for (final offer in value)
                  TransferTile(
                    view: offer,
                    busy: offerActions.busy.contains(offer.id),
                    error: offerActions.errorFor(offer.id),
                    onAccept: () => ref
                        .read(offerActionsProvider.notifier)
                        .accept(offer.id),
                    onDecline: () => ref
                        .read(offerActionsProvider.notifier)
                        .decline(offer.id),
                    onPause: () =>
                        ref.read(offerActionsProvider.notifier).pause(offer.id),
                  ),
              ],
            ),
            AsyncError() => const InlineNotice(
              kind: InlineNoticeKind.error,
              message: 'Transfers could not be loaded.',
            ),
            _ => const Padding(
              padding: EdgeInsets.all(HelixSpace.md),
              child: LinearProgressIndicator(),
            ),
          },
          const SizedBox(height: HelixSpace.lg),
        ],
      ),
    );
  }
}
