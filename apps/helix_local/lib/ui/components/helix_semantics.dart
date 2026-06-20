// lib/ui/components/helix_semantics.dart
//
// Accessibility helpers (P9-02, P9-06).
//
// HelixSemanticButton   — icon-only button with required accessible label and
//                         48 × 48 dp minimum touch target.
// HelixLiveRegion       — announces runtime state changes to screen readers.
// HelixStatusLabel      — status indicator that conveys state via both color
//                         and text/icon, never color alone (P9-05).
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Icon-only button with mandatory accessible label (P9-02, P9-06)
// ─────────────────────────────────────────────────────────────────────────────

class HelixSemanticButton extends StatelessWidget {
  const HelixSemanticButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.tooltip,
    this.iconSize,
    this.color,
    this.style,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double? iconSize;
  final Color? color;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      enabled: onPressed != null,
      excludeSemantics: true,
      child: IconButton(
        icon: Icon(icon, size: iconSize, color: color),
        onPressed: onPressed,
        tooltip: tooltip ?? label,
        style: style,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live region — re-announces a value when it changes (P9-02)
// ─────────────────────────────────────────────────────────────────────────────

class HelixLiveRegion extends StatelessWidget {
  const HelixLiveRegion({
    super.key,
    required this.value,
    required this.child,
    this.polite = true,
  });

  final String value;
  final Widget child;
  final bool polite;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: value,
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status label — color + icon + text, never color alone (P9-05)
// ─────────────────────────────────────────────────────────────────────────────

class HelixStatusLabel extends StatelessWidget {
  const HelixStatusLabel({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.semanticsLabel,
    this.textStyle,
    this.iconSize = 14,
  });

  final String label;
  final IconData icon;
  final Color color;
  final String? semanticsLabel;
  final TextStyle? textStyle;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final style =
        textStyle ?? Theme.of(context).textTheme.labelSmall?.copyWith(color: color);

    return Semantics(
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: color),
          const SizedBox(width: 4),
          Text(label, style: style),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Minimum-size touch target wrapper (P9-06)
// Wraps any widget in a box that is at least 48 × 48 dp so it remains easy
// to tap even when the visible widget is smaller.
// ─────────────────────────────────────────────────────────────────────────────

class HelixMinTouchTarget extends StatelessWidget {
  const HelixMinTouchTarget({super.key, required this.child, this.alignment});

  final Widget child;
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      child: Align(
        alignment: alignment ?? Alignment.center,
        child: child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Decorative element — excluded from the semantic tree (P9-02)
// ─────────────────────────────────────────────────────────────────────────────

class HelixDecorativeWidget extends StatelessWidget {
  const HelixDecorativeWidget({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(child: child);
  }
}
