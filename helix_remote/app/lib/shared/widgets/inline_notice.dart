import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

enum InlineNoticeKind { info, success, error }

/// A short message set into a page: a failure under the control that caused
/// it, a result after a long operation, or a note about what a switch means.
///
/// Announced to a screen reader when it appears. Colours come from the theme
/// and the status tokens, never literals.
class InlineNotice extends StatelessWidget {
  const InlineNotice({
    super.key,
    required this.message,
    this.kind = InlineNoticeKind.info,
    this.action,
  });

  final String message;
  final InlineNoticeKind kind;

  /// A button under the message ("Try again").
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (kind) {
      InlineNoticeKind.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline,
      ),
      InlineNoticeKind.success => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.check_circle_outline,
      ),
      InlineNoticeKind.info => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        Icons.info_outline,
      ),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: HelixSpace.md,
          vertical: HelixSpace.xs,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: HelixRadius.card,
          ),
          child: Padding(
            padding: const EdgeInsets.all(HelixSpace.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(child: Icon(icon, color: foreground)),
                const SizedBox(width: HelixSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(message, style: TextStyle(color: foreground)),
                      ?action,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small heading over a block of body text, for the explanatory paragraphs
/// of a settings page.
class PageIntro extends StatelessWidget {
  const PageIntro({super.key, required this.text, this.title});

  final String? title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HelixSpace.md,
        HelixSpace.md,
        HelixSpace.md,
        HelixSpace.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: HelixSpace.xxs),
              child: Text(title!, style: theme.textTheme.titleMedium),
            ),
          Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A full-width button row with a busy state: the label stays, a spinner
/// replaces the tap.
class BusyFilledButton extends StatelessWidget {
  const BusyFilledButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.tonal = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy)
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (icon != null)
          Icon(icon, size: 18),
        if (busy || icon != null) const SizedBox(width: HelixSpace.xs),
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
    final handler = busy ? null : onPressed;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: HelixSpace.md,
        vertical: HelixSpace.xs,
      ),
      child: tonal
          ? FilledButton.tonal(onPressed: handler, child: child)
          : FilledButton(onPressed: handler, child: child),
    );
  }
}
