import 'package:flutter/material.dart';

import 'package:orbit_ui/src/brand/orbit_mark.dart';
import 'package:orbit_ui/src/theme/motion.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// The "Opening Orbit…" screen (`startup`).
///
/// Drawn while the encrypted database opens, before the router has decided
/// between Chats, sign-in, the restore step and reset. It carries no model and
/// no actions: it is a picture with a moving bar.
///
/// The specification is `prototype/js/screens/states.js` (`startup`) and
/// `prototype/css/pages.css`:
///
/// - `.page`: the background is `--bg` and the content starts below the
///   status bar (`padding-top: 40px` there, the top inset here);
/// - `.startup`: a centred column with an 18px gap;
/// - `.su-mark`: the logo, 84×84, corner 24, shadow `0 16px 40px -18px
///   var(--accent)`;
/// - `.su-text`: mono, 12px, `letter-spacing: 0.08em`, upper case, `--ink-3`;
/// - a 120px `.prog.indet` bar: 4px tall, corner 4, `--line` track, a 36%
///   `--accent` block moving from -36% to 100% over 1.2s on `--ease`.
class OrbitStartup extends StatelessWidget {
  const OrbitStartup({super.key});

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Semantics(
      label: 'Opening Orbit',
      liveRegion: true,
      child: ColoredBox(
        color: t.bg,
        child: Padding(
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: t.accent,
                        offset: const Offset(0, 16),
                        blurRadius: orbitCssBlur(40),
                        spreadRadius: -18,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: const ExcludeSemantics(child: OrbitMark(size: 84)),
                ),
                const SizedBox(height: 18),
                ExcludeSemantics(
                  child: Text(
                    'Opening Orbit…'.toUpperCase(),
                    style: t.mono.style(
                      size: 12,
                      color: t.ink3,
                      letterSpacingEm: 0.08,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const SizedBox(width: 120, child: _IndeterminateBar()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.prog.indet`: a block that sweeps across the track and starts again.
///
/// With reduce motion on, the prototype switches the animation off and the
/// block rests at the start of the track; so does this.
class _IndeterminateBar extends StatefulWidget {
  const _IndeterminateBar();

  @override
  State<_IndeterminateBar> createState() => _IndeterminateBarState();
}

class _IndeterminateBarState extends State<_IndeterminateBar>
    with SingleTickerProviderStateMixin {
  // `@keyframes indet` runs 1.2s; it is the bar's own, not a motion token.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (OrbitMotion.allowed(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final moving = OrbitMotion.allowed(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 4,
        child: ColoredBox(
          color: t.line,
          child: LayoutBuilder(
            builder: (context, box) => AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final w = box.maxWidth;
                // -36% to 100% of the track; at rest, the static position (0).
                final left = moving
                    ? w * (-0.36 + 1.36 * t.motion.curve.transform(_c.value))
                    : 0.0;
                return Stack(
                  children: [
                    Positioned(
                      left: left,
                      top: 0,
                      bottom: 0,
                      width: w * 0.36,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: t.accent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
