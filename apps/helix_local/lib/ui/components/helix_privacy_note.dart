import 'package:flutter/material.dart';
import 'package:helix/ui/app_theme.dart';

/// Inline privacy or security context note shown near sensitive settings.
///
/// Renders a small, subdued banner with a lock/shield icon and [text].
/// Use this to explain ephemerality, wipe scope, export risk, or key
/// verification expectations in the UI where the action lives — not in a
/// separate help page.
class HelixPrivacyNote extends StatelessWidget {
  const HelixPrivacyNote(this.text, {super.key, this.icon = Icons.lock_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurface.withAlpha(140);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: HelixTokens.space4,
        vertical: HelixTokens.space8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: HelixTokens.iconSm, color: color),
          const SizedBox(width: HelixTokens.space8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
