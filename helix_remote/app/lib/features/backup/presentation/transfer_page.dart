import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/backup/application/backup_models.dart';
import 'package:helix_remote/features/backup/application/backup_providers.dart';
import 'package:helix_remote/features/backup/application/transfer_rows.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Connector: Send to my other devices, drawn by `orbit_ui`'s
/// [TransferScreen].
///
/// Both sides of a device-to-device transfer live on this one page, because a
/// phone is usually both at different times: it sends its history to a new
/// device, and receives one when it is the new device. Everything that moves
/// is encrypted before it leaves, and the other device must accept before
/// anything is downloaded.
class TransferPage extends ConsumerWidget {
  const TransferPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(transfersProvider);
    final offers = ref.watch(incomingOffersProvider);
    final offerActions = ref.watch(offerActionsProvider);
    final controller = ref.read(transfersProvider.notifier);
    final offerController = ref.read(offerActionsProvider.notifier);

    void onAction(String id, String action) {
      switch (action) {
        case 'Accept' || 'Resume' || 'Try again':
          offerController.accept(id);
        case 'Decline':
          offerController.decline(id);
        case 'Pause':
          offerController.pause(id);
        case 'Cancel':
          controller.cancel(id);
        case 'Dismiss':
          controller.dismiss(id);
      }
    }

    return TransferScreen(
      model: transferModel(
        transfers,
        offers: offers,
        offerActions: offerActions,
      ),
      actions: TransferActions(
        onSend: controller.send,
        onAction: onAction,
        onRetry: () => ref.invalidate(incomingOffersProvider),
      ),
    );
  }
}

/// The screen's model for the two sides of a transfer
/// (`orbit/contracts/devices_backup.md`).
@visibleForTesting
TransferModel transferModel(
  TransfersState transfers, {
  required AsyncValue<List<TransferView>> offers,
  required OfferActionsState offerActions,
}) {
  TransferItem item(
    TransferView view, {
    String? error,
    bool dismissible = false,
  }) {
    final row = transferRow(view, error: error, dismissible: dismissible);
    return TransferItem(
      id: row.id,
      title: row.title,
      status: row.status,
      outgoing: row.outgoing,
      progress: row.progress,
      buttons: row.buttons,
    );
  }

  return TransferModel(
    sending: [
      for (final view in transfers.outgoing.values)
        item(view, dismissible: true),
    ],
    waiting: [
      for (final view in offers.value ?? const <TransferView>[])
        item(view, error: offerActions.errorFor(view.id)),
    ],
    error: transfers.error,
    busy: transfers.starting,
    incomingLoading: offers.isLoading && !offers.hasValue,
    incomingFailed: offers.hasError && !offers.hasValue,
  );
}
