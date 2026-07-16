import 'package:flutter/material.dart';

/// Standard confirmation dialog.
///
/// Returns `true` when the user confirms, `false` when they cancel, and `null`
/// when the dialog is dismissed by tapping outside.
class HelixConfirmDialog extends StatelessWidget {
  const HelixConfirmDialog({
    super.key,
    required this.title,
    required this.body,
    this.confirmLabel = 'OK',
    this.cancelLabel = 'Cancel',
    this.isDangerous = false,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final String cancelLabel;

  /// If true, the confirm button is styled with the error color.
  final bool isDangerous;

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String body,
    String confirmLabel = 'OK',
    String cancelLabel = 'Cancel',
    bool isDangerous = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => HelixConfirmDialog(
        title: title,
        body: body,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        isDangerous: isDangerous,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confirmStyle = isDangerous
        ? TextButton.styleFrom(foregroundColor: theme.colorScheme.error)
        : null;

    return AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        TextButton(
          style: confirmStyle,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
