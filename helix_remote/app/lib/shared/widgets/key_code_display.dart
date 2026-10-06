import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// A short code the person compares between two devices (a key code, a check
/// number): large, monospaced, in groups, read out digit by digit.
///
/// It is not a secret (it is derived from a public key or a one-time link), so
/// it may be selected and seen over a shoulder; what matters is that it is
/// legible and that a screen reader says it character by character.
class KeyCodeDisplay extends StatelessWidget {
  const KeyCodeDisplay({super.key, required this.label, required this.code});

  /// "Key code", "Check number".
  final String label;
  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      value: code.replaceAll(' ', '').split('').join(' '),
      child: ExcludeSemantics(
        child: Column(
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            const SizedBox(height: HelixSpace.xxs),
            Text(
              code,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontFamily: 'monospace',
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
