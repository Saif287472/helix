import 'package:helix_remote/features/backup/application/backup_copy.dart';
import 'package:helix_remote/features/backup/application/backup_models.dart';

/// One device-to-device transfer as a row: its words, its bar and the
/// buttons that make sense at that moment. Settled here so the restore step
/// and Backup's transfers page say the same thing (`orbit/contracts`, the
/// shared transfer row).
///
/// Sending: Cancel while it is preparing or waiting for the other device.
/// Receiving: Accept and Decline while it waits, Pause while it runs, and
/// Resume (the same Accept) after a pause or a failure - what was fetched is
/// kept, so resuming does not start again.
final class TransferRow {
  const TransferRow({
    required this.id,
    required this.title,
    required this.status,
    this.outgoing = false,
    this.progress,
    this.buttons = const [],
  });

  final String id;
  final String title;

  /// Where it has got to, or the sentence about why it stopped.
  final String status;
  final bool outgoing;

  /// 0..1 while it runs and the size is known.
  final double? progress;

  /// Button labels: Accept, Resume, Try again, Decline, Pause, Cancel,
  /// Dismiss.
  final List<String> buttons;
}

/// [view] as a row. [error] is why the last action on it failed;
/// [dismissible] offers Dismiss once it is finished.
TransferRow transferRow(
  TransferView view, {
  String? error,
  bool dismissible = false,
}) {
  final sending = view.direction == TransferDirection.sending;
  final device = view.deviceName;
  final running =
      view.stage == TransferStage.preparing ||
      view.stage == TransferStage.downloading ||
      view.stage == TransferStage.importing;
  final problem = view.problem;
  return TransferRow(
    id: view.id,
    title: sending
        ? 'Sending your history'
        : device == null
        ? 'History from another device'
        : 'History from $device',
    status:
        error ??
        (problem != null && view.stage == TransferStage.failed
            ? backupProblemText(problem)
            : transferStatus(view)),
    outgoing: sending,
    progress: running ? view.fraction : null,
    buttons: [
      if (!sending && view.stage == TransferStage.waiting) ...[
        problem != null
            ? 'Try again'
            : view.done > 0
            ? 'Resume'
            : 'Accept',
        'Decline',
      ],
      if (!sending &&
          (view.stage == TransferStage.downloading ||
              view.stage == TransferStage.importing))
        'Pause',
      if (!sending && view.stage == TransferStage.failed) 'Resume',
      if (sending &&
          (view.stage == TransferStage.preparing ||
              view.stage == TransferStage.offered))
        'Cancel',
      if (view.isFinished && dismissible) 'Dismiss',
    ],
  );
}

/// Where a transfer has got to, in a sentence.
String transferStatus(TransferView v) {
  final progress = v.total > 0 ? ' (${v.done} of ${v.total})' : '';
  return switch (v.stage) {
    TransferStage.preparing => 'Getting your history ready$progress',
    TransferStage.offered =>
      'Sent. Your other device chooses whether to add it; it shows there '
          'under Backup.',
    TransferStage.waiting =>
      'Ready to receive. Nothing is downloaded until you accept.',
    TransferStage.downloading => 'Receiving$progress',
    TransferStage.importing => 'Adding messages$progress',
    TransferStage.done => 'Done',
    TransferStage.declined => 'Your other device declined it.',
    TransferStage.cancelled => 'Cancelled',
    TransferStage.failed => 'Stopped',
  };
}
