import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// The type scale, `--t-*` in `prototype/css/tokens.css`.
///
/// The same in every theme: the prototype multiplies them by the person's text
/// size (`--text-scale`), which Flutter does through `MediaQuery.textScaler`,
/// so these are the sizes at 100%.
abstract final class OrbitType {
  /// Tab titles.
  static const double display = 30;

  /// Page titles.
  static const double title = 20;

  /// Row titles, names.
  static const double headline = 16;

  /// Messages, body text.
  static const double body = 15;

  /// Previews, subtitles, buttons.
  static const double small = 13.5;

  /// Helper text.
  static const double caption = 12;

  /// Mono times, status and labels.
  static const double meta = 11;
}

/// Spacing the whole design shares (`--gutter`, `--target`).
abstract final class OrbitSpace {
  /// Screen side padding.
  static const double gutter = 16;

  /// The smallest tap target (the accessibility rule).
  static const double target = 48;
}

/// Text in the theme's display face: what `css/pages.css` gives page titles,
/// sheet and dialog headings (`--font-display`, `--display-weight`,
/// `--display-tracking`). Apply [OrbitTokens.displayTransform] to the string
/// with [orbitTransform].
extension OrbitDisplayText on OrbitTokens {
  TextStyle display({
    required double size,
    Color? color,
    double height = 1.4,
  }) => fontDisplay.style(
    size: size,
    weight: displayWeight,
    color: color ?? ink,
    letterSpacingEm: displayTracking,
    height: height,
  );
}

/// CSS `text-transform`, which Flutter's [TextStyle] has no field for.
String orbitTransform(String text, OrbitTextTransform transform) =>
    switch (transform) {
      OrbitTextTransform.none => text,
      OrbitTextTransform.uppercase => text.toUpperCase(),
      OrbitTextTransform.lowercase => text.toLowerCase(),
      OrbitTextTransform.capitalize => text.replaceAllMapped(
        RegExp(r'\b\w'),
        (m) => m[0]!.toUpperCase(),
      ),
    };

/// Lays [child] out at its own size but answers taps across at least
/// [OrbitSpace.target] square, centred on it.
///
/// For controls the prototype draws smaller than a tap target (a 44×26
/// switch), so the 48px rule holds without moving anything on screen. The
/// extra area only works where the parent's own box reaches.
class OrbitTapArea extends SingleChildRenderObjectWidget {
  const OrbitTapArea({super.key, super.child, this.merge = false});

  /// Merges a child that makes its own semantics node (a text field) into
  /// the area's one node.
  final bool merge;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTapArea()..merge = merge;

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderTapArea).merge = merge;
}

class _RenderTapArea extends RenderProxyBox {
  bool _merge = false;

  set merge(bool value) {
    if (value == _merge) return;
    _merge = value;
    markNeedsSemanticsUpdate();
  }

  Rect get _area {
    final w = size.width < OrbitSpace.target ? OrbitSpace.target : size.width;
    final h = size.height < OrbitSpace.target ? OrbitSpace.target : size.height;
    return Rect.fromCenter(
      center: size.center(Offset.zero),
      width: w,
      height: h,
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_area.contains(position)) return false;
    // The child is hit at the nearest point inside it, so a tap just outside
    // still reaches its gesture detector.
    final inside = Offset(
      position.dx.clamp(0, size.width),
      position.dy.clamp(0, size.height),
    );
    if (hitTestChildren(result, position: inside) || hitTestSelf(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  /// The area a test can measure: the tap target, not the drawn size.
  Size get tapSize => _area.size;

  // One semantics node for the control, as large as the area that answers
  // taps, so a screen reader (and the 48px guideline check) is told what a
  // finger gets rather than what is drawn. The control's own semantics
  // (button, label, tap) merge into it.
  @override
  Rect get semanticBounds => _area;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
    if (_merge) config.isMergingSemanticsOfDescendants = true;
  }
}
