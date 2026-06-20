import 'package:flutter/material.dart';
import 'package:helix/ui/app_theme.dart';

/// Standardized dialog for destructive (irreversible) actions.
///
/// Shows:
///  - A warning icon coloured with the error palette.
///  - The action [title] and an [impactText] explaining exactly what is lost.
///  - A confirm button labelled [confirmLabel] styled in error colour.
///  - A cancel button.
///
/// Returns `true` when the user confirms, `false` or `null` otherwise.
class HelixDestructiveDialog extends StatelessWidget {
  const HelixDestructiveDialog({
    super.key,
    required this.title,
    required this.impactText,
    this.confirmLabel = 'Delete',
    this.cancelLabel = 'Cancel',
    this.barrierDismissible = false,
  });

  final String title;
  final String impactText;
  final String confirmLabel;
  final String cancelLabel;
  final bool barrierDismissible;

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String impactText,
    String confirmLabel = 'Delete',
    String cancelLabel = 'Cancel',
    bool barrierDismissible = false,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => HelixDestructiveDialog(
        title: title,
        impactText: impactText,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: Icon(
        Icons.warning_amber_rounded,
        size: HelixTokens.iconXl,
        color: theme.colorScheme.error,
      ),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(impactText, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
