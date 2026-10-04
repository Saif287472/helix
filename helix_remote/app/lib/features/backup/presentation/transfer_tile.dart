import 'package:flutter/material.dart';
import 'package:helix_remote/features/backup/application/backup_copy.dart';
import 'package:helix_remote/features/backup/application/backup_models.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// One device-to-device transfer: who, where it has got to, a progress bar
/// and the buttons that make sense for that moment.
///
/// Sending: Cancel while it is preparing or waiting for the other device.
/// Receiving: Accept and Decline while it waits, Pause while it runs, and
/// Resume (the same Accept) after a pause or a failure - what was fetched is
/// kept, so resuming does not start again.
class TransferTile extends StatelessWidget {
  const TransferTile({
    super.key,
    required this.view,
    this.error,
    this.busy = false,
    this.onAccept,
    this.onDecline,
    this.onPause,
    this.onCancel,
    this.onDismiss,
  });

  final TransferView view;

  /// A sentence about why the last action failed.
  final String? error;

  /// An accept or decline is in flight.
  final bool busy;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onPause;
  final VoidCallback? onCancel;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sending = view.direction == TransferDirection.sending;
    final device = view.deviceName;
    final title = sending
        ? 'Sending your history'
        : device == null
        ? 'History from another device'
        : 'History from $device';
    final fraction = view.fraction;
    final running =
        view.stage == TransferStage.preparing ||
        view.stage == TransferStage.downloading ||
        view.stage == TransferStage.importing;

    return Semantics(
      container: true,
      label: '$title. ${_status(view)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: HelixSpace.md,
          vertical: HelixSpace.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: HelixSpace.xxs),
            Text(
              _status(view),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (running) ...[
              const SizedBox(height: HelixSpace.xs),
              LinearProgressIndicator(value: fraction),
            ],
            if (view.problem != null && view.stage == TransferStage.failed) ...[
              const SizedBox(height: HelixSpace.xs),
              Text(
                backupProblemText(view.problem!),
                style: TextStyle(color: scheme.error),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: HelixSpace.xs),
              Text(error!, style: TextStyle(color: scheme.error)),
            ],
            Wrap(
              spacing: HelixSpace.xs,
              children: [
                if (!sending && view.stage == TransferStage.waiting) ...[
                  FilledButton(
                    onPressed: busy ? null : onAccept,
                    child: Text(
                      view.problem != null
                          ? 'Try again'
                          : view.done > 0
                          ? 'Resume'
                          : 'Accept',
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : onDecline,
                    child: const Text('Decline'),
                  ),
                ],
                if (!sending &&
                    (view.stage == TransferStage.downloading ||
                        view.stage == TransferStage.importing))
                  TextButton(onPressed: onPause, child: const Text('Pause')),
                if (!sending && view.stage == TransferStage.failed)
                  TextButton(
                    onPressed: busy ? null : onAccept,
                    child: const Text('Resume'),
                  ),
                if (sending &&
                    (view.stage == TransferStage.preparing ||
                        view.stage == TransferStage.offered))
                  TextButton(onPressed: onCancel, child: const Text('Cancel')),
                if (view.isFinished && onDismiss != null)
                  TextButton(
                    onPressed: onDismiss,
                    child: const Text('Dismiss'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _status(TransferView v) {
    final progress = v.total > 0 ? ' (${v.done} of ${v.total})' : '';
    return switch (v.stage) {
      TransferStage.preparing => 'Getting your history ready$progress',
      TransferStage.offered =>
        'Waiting for your other device to accept. It will appear there '
            'under Backup.',
      TransferStage.waiting =>
        'Ready to receive. Nothing is downloaded until '
            'you accept.',
      TransferStage.downloading => 'Receiving$progress',
      TransferStage.importing => 'Adding messages$progress',
      TransferStage.done => 'Done',
      TransferStage.declined => 'Declined',
      TransferStage.cancelled => 'Cancelled',
      TransferStage.failed => 'Stopped',
    };
  }
}
