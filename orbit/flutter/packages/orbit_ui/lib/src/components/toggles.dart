import 'package:flutter/material.dart';

import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/theme/motion.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// `.switch` (`css/components.css`): a 44×26 pill in `--switch-off`, or
/// `--accent` when [on], with a 20px `--switch-knob` knob 3px in that slides
/// 18px, both over `--dur` on `--ease`.
///
/// Drawn at 44×26 and tappable across 48px. Inside a settings row the row is
/// the target and passes no [onChanged].
class OrbitSwitch extends StatelessWidget {
  const OrbitSwitch({super.key, required this.on, this.onChanged, this.label});

  final bool on;
  final ValueChanged<bool>? onChanged;

  /// What it switches, for screen readers when nothing beside it says so.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final duration = OrbitMotion.allowed(context)
        ? t.motion.short
        : Duration.zero;
    final track = AnimatedContainer(
      duration: duration,
      curve: t.motion.curve,
      width: 44,
      height: 26,
      decoration: BoxDecoration(
        color: on ? t.accent : t.switchOff,
        borderRadius: BorderRadius.circular(99),
      ),
      child: AnimatedAlign(
        duration: duration,
        curve: t.motion.curve,
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.all(3),
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: t.switchKnob,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0x33000000),
                offset: const Offset(0, 1),
                blurRadius: orbitCssBlur(3),
              ),
            ],
          ),
        ),
      ),
    );
    final toggle = onChanged;
    final control = Semantics(toggled: on, label: label, child: track);
    if (toggle == null) return control;
    // The tap area is outermost, so a tap just outside the drawn 44×26 counts.
    return OrbitTapArea(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => toggle(!on),
        child: control,
      ),
    );
  }
}

/// `Kit.check` (`js/kit.js`; `.chk` in `css/pages.css`): a full-width row at
/// least 48px tall, 8px 2px in, a 22px box (corner 7, a 1.5px
/// `--control-line` edge; `--accent` with a bold tick when [on]) 12px before
/// its label at `--t-small` in `--ink-2`, line height 1.45.
class OrbitCheckbox extends StatelessWidget {
  const OrbitCheckbox({
    super.key,
    required this.label,
    required this.on,
    required this.onChanged,
  });

  final String label;
  final bool on;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final duration = OrbitMotion.allowed(context)
        ? t.motion.short
        : Duration.zero;
    final change = onChanged;
    return Semantics(
      checked: on,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: change == null ? null : () => change(!on),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: OrbitSpace.target,
            minWidth: double.infinity,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: AnimatedContainer(
                    duration: duration,
                    curve: t.motion.curve,
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on ? t.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: on ? t.accent : t.controlLine,
                        width: 1.5,
                      ),
                    ),
                    child: on
                        ? OrbitIcon(
                            OrbitIcons.check,
                            weight: OrbitIconWeight.bold,
                            size: 14,
                            color: t.onAccent,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: t.font.style(
                      size: OrbitType.small,
                      color: t.ink2,
                      height: 1.45,
                    ),
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
