import 'package:helix_remote_crypto/v2.dart' show DeviceAddress;
import 'package:helix_remote_engine/src/backup/models.dart';
import 'package:helix_remote_engine/src/backup/state.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The inbound pipeline's hook for `device_transfer_offer` (called by the
/// content applier inside the envelope's transaction). It only records:
/// downloading and importing are `BackupService`'s, outside the transaction.
abstract final class TransferInbox {
  /// Applies [body] from [sender]. Returns false when it was ignored.
  ///
  /// Only this account's other devices count (the sender account is the
  /// server-attested one, and the content arrived under a pairwise session),
  /// an offer must name a relay manifest of a sane size, and a withdrawal is
  /// honoured only from the device that made the offer.
  static Future<bool> apply(
    EngineContext ctx,
    DeviceAddress sender,
    DeviceTransferOfferBody body,
    DateTime now,
  ) async {
    final self = ctx.identity;
    if (sender.account != self.accountId || sender.device == self.deviceId) {
      return false;
    }
    final audience = body.devices;
    if (audience != null && !audience.contains(self.deviceId)) return false;
    final ledger = TransferLedger(ctx.db);
    switch (body.state) {
      case DeviceTransferState.offer:
        final manifest = body.relayMedia;
        if (manifest == null ||
            manifest.size > TransferLedger.maxManifestBytes) {
          return false;
        }
        return ledger.recordOffer(
          transferId: body.transferId,
          fromDevice: sender.device,
          manifest: manifest,
          now: now,
        );
      case DeviceTransferState.done || DeviceTransferState.declined:
        await ledger.recordAnswer(body.transferId, sender.device, now: now);
        return true;
      case DeviceTransferState.cancelled:
        final updated = await ledger.updateIncoming(
          body.transferId,
          (o) => o.fromDevice == sender.device && !o.phase.isFinished
              ? o.copyWith(phase: HistoryTransferPhase.cancelled)
              : o,
          now: now,
        );
        return updated != null;
    }
  }
}
