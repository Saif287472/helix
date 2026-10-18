import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';
import 'package:orbit_ui/src/theme/pattern_painter.dart';

/// The parts the prototype's design-system sheets are built from
/// (`kit-primitives` and the others in `js/screens/states.js`): a You-style
/// page with no back arrow, an intro line, and labelled dashed frames.
///
/// These are for the sheets only, which exist to compare components with the
/// prototype; no app screen uses them.
class OrbitKitPage extends StatelessWidget {
  const OrbitKitPage({
    super.key,
    required this.title,
    required this.intro,
    required this.children,
  });

  final String title;
  final String intro;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return OrbitPageBackground(
      child: Padding(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // `Kit.youPage(..., { back: false })`: `.appbar.flat.you-bar`,
            // 60px, 4px 6px in; an 8px spacer, a 2px gap, then the title 6px
            // in, in the display face at --t-title.
            SizedBox(
              height: 60,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6 + 8 + 2 + 6, 4, 6, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    orbitTransform(title, t.displayTransform),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.display(size: OrbitType.title),
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // `.sec-foot` with `margin-top: 4px`.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        OrbitSpace.gutter + 6,
                        4,
                        OrbitSpace.gutter + 6,
                        0,
                      ),
                      child: Text(
                        intro,
                        style: t.font.style(
                          size: OrbitType.caption,
                          color: t.ink3,
                          height: 1.5,
                        ),
                      ),
                    ),
                    ...children,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.kit-label`: mono 10.5px, tracked 0.08em, upper case, `--ink-3`, 18px
/// above and 6px below, 4px further in than the gutter.
class OrbitKitLabel extends StatelessWidget {
  const OrbitKitLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OrbitSpace.gutter + 4,
        18,
        OrbitSpace.gutter + 4,
        6,
      ),
      child: Text(
        text.toUpperCase(),
        style: t.mono.style(size: 10.5, color: t.ink3, letterSpacingEm: 0.08),
      ),
    );
  }
}

/// `.kit-frame`: inset by the gutter, a 1px dashed `--line` edge, corner
/// `--r-lg`, and [padding], on [background] (the sheets mostly set
/// `background: var(--surface)` inline; the class's own is `--bg`).
class OrbitKitFrame extends StatelessWidget {
  const OrbitKitFrame({
    super.key,
    required this.padding,
    required this.child,
    this.background,
  });

  final EdgeInsets padding;
  final Widget child;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final radius = BorderRadius.circular(t.rLg);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: OrbitSpace.gutter),
      child: CustomPaint(
        foregroundPainter: _DashedEdge(color: t.line, radius: t.rLg),
        child: ClipRRect(
          borderRadius: radius,
          child: ColoredBox(
            color: background ?? t.surface,
            child: Padding(
              // The 1px edge sits inside the box, as CSS's border-box does.
              padding: padding + const EdgeInsets.all(1),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A 1px dashed rounded edge: 3px dashes and 3px gaps, Chrome's pattern for
/// a 1px `dashed` border.
class _DashedEdge extends CustomPainter {
  const _DashedEdge({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final edge = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.5),
      Radius.circular(radius - 0.5),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final PathMetric metric in (Path()..addRRect(edge)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 6) {
        canvas.drawPath(metric.extractPath(d, d + 3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedEdge old) =>
      old.color != color || old.radius != radius;
}
