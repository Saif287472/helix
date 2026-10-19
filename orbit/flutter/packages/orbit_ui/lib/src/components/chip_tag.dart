import 'package:flutter/material.dart';

import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// `.chip` (`css/components.css`): a 34px pill with a `--line` edge on
/// `--surface`, the label at 13px and weight 550 in `--ink-2`; `.on` is
/// `--inverse` with `--on-inverse` text. [count] is `.chip-n`, a mono 11px
/// count on `--field` (on the inverse colour at 18% when [on]).
///
/// The chip is 34px tall as drawn; it answers taps across 48px.
class OrbitChip extends StatelessWidget {
  const OrbitChip({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
    this.count,
    this.icon,
    this.height = 34,
  });

  /// 34, or 36 in the chat filters (`.chat-filters .chip`).
  final double height;

  final String label;
  final bool on;
  final VoidCallback? onTap;
  final int? count;
  final OrbitGlyph? icon;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final fg = on ? t.onInverse : t.ink2;
    final radius = BorderRadius.circular(t.rPill);
    // The tap area is outermost: anything above it would refuse a tap outside
    // the drawn 34px before it got here.
    return OrbitTapArea(
      child: Semantics(
        button: true,
        selected: on,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: on ? t.inverse : t.surface,
              borderRadius: radius,
              border: Border.all(color: on ? t.inverse : t.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  OrbitIcon(icon!, size: 16, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: t.font.style(size: 13, weight: 550, color: fg),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on ? t.onInverse.withValues(alpha: 0.18) : t.field,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$count',
                      style: t.mono.style(
                        size: 11,
                        weight: 600,
                        color: on ? t.onInverse : t.ink3,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum OrbitTagTone { plain, accent, success, warning, danger }

/// `.tag` (`css/components.css`): a 20px mono label, 10px, tracked 0.06em,
/// upper case, weight 500, corner 6, on `--field` in `--ink-3` or a tone's
/// soft colour. Used for E2E, VERIFIED, ADMIN and the like.
class OrbitTag extends StatelessWidget {
  const OrbitTag({
    super.key,
    required this.label,
    this.tone = OrbitTagTone.plain,
    this.icon,
  });

  final String label;
  final OrbitTagTone tone;
  final OrbitGlyph? icon;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final (bg, fg) = switch (tone) {
      OrbitTagTone.plain => (t.field, t.ink3),
      OrbitTagTone.accent => (t.accentSoft, t.accentInk),
      OrbitTagTone.success => (t.successSoft, t.success),
      OrbitTagTone.warning => (t.warningSoft, t.warning),
      OrbitTagTone.danger => (t.dangerSoft, t.danger),
    };
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            OrbitIcon(icon!, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          // Shrinks to an ellipsis rather than overflowing a narrow card.
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.mono.style(
                size: 10,
                weight: 500,
                color: fg,
                letterSpacingEm: 0.06,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
