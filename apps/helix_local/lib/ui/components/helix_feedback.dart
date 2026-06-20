import 'package:flutter/material.dart';
import 'package:helix/ui/app_theme.dart';

/// Standardized snackbar / in-app feedback helpers.
///
/// Prefer these over raw [ScaffoldMessenger] calls so error, success, and
/// retry messages are visually consistent across the app.
abstract final class HelixFeedback {
  static void success(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: Icons.check_circle_outline,
      iconColor: HelixTokens.colorSuccess,
    );
  }

  static void error(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _show(
      context,
      message: message,
      icon: Icons.error_outline,
      iconColor: HelixTokens.colorError,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: const Duration(seconds: 6),
    );
  }

  static void warning(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: Icons.warning_amber_outlined,
      iconColor: HelixTokens.colorWarning,
      duration: const Duration(seconds: 5),
    );
  }

  static void info(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: Icons.info_outline,
      iconColor: HelixTokens.colorInfo,
    );
  }

  /// Shows an error snackbar with a Retry action button.
  static void retry(
    BuildContext context,
    String message,
    VoidCallback onRetry,
  ) {
    error(context, message, actionLabel: 'Retry', onAction: onRetry);
  }

  /// Shows progress feedback with an optional cancel action.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> progress(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    return messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        duration: const Duration(seconds: 30),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
      ),
    );
  }

  static void _show(
    BuildContext context, {
    required String message,
    required IconData icon,
    required Color iconColor,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        duration: duration,
        action: actionLabel != null && onAction != null
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
      ),
    );
  }
}
