import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Text that takes the height CSS gives it.
///
/// Flutter rounds every line of a paragraph to a whole pixel: 12px text at
/// line height 1.4 is 17px tall, where the browser makes it 16.8. One line
/// is a fraction of a pixel, but a page stacks dozens of them, and the
/// prototype's layout drifts a pixel or more by the bottom of a screen.
///
/// [OrbitText] lays the text out as [Text] does, then takes `lines × size ×
/// height` as its own height, and centres the rounded lines on the CSS ones:
/// a single line sits exactly where CSS puts it, and in a block of several
/// the top and bottom lines are off by at most half the rounding each.
/// Nothing after the block moves.
///
/// [style] must set `fontSize` and `height`, which every
/// `OrbitFontStack.style` does.
class OrbitText extends StatelessWidget {
  const OrbitText(
    String this.data, {
    super.key,
    required this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
  }) : span = null;

  const OrbitText.rich(
    InlineSpan this.span, {
    super.key,
    required this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
  }) : data = null;

  final String? data;
  final InlineSpan? span;
  final TextStyle style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    final size = style.fontSize;
    final height = style.height;
    final text = span == null
        ? Text(
            data!,
            style: style,
            textAlign: textAlign,
            maxLines: maxLines,
            overflow: overflow,
            softWrap: softWrap,
          )
        : Text.rich(
            span!,
            style: style,
            textAlign: textAlign,
            maxLines: maxLines,
            overflow: overflow,
            softWrap: softWrap,
          );
    if (size == null || height == null) return text;
    final line = MediaQuery.textScalerOf(context).scale(size) * height;
    return _CssLines(line: line, child: text);
  }
}

class _CssLines extends SingleChildRenderObjectWidget {
  const _CssLines({required this.line, required super.child});

  final double line;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCssLines(line);

  @override
  void updateRenderObject(BuildContext context, _RenderCssLines r) =>
      r.line = line;
}

class _RenderCssLines extends RenderProxyBox {
  _RenderCssLines(this._line);

  double _line;
  set line(double v) {
    if (v == _line) return;
    _line = v;
    markNeedsLayout();
  }

  /// How far the text is moved, to centre the rounded lines on the CSS ones.
  double _shift = 0;

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    c.layout(constraints, parentUsesSize: true);
    final rounded = _line.roundToDouble();
    if (rounded <= 0) {
      size = c.size;
      _shift = 0;
      return;
    }
    final lines = (c.size.height / rounded).round().clamp(1, 1 << 20);
    size = constraints.constrain(Size(c.size.width, lines * _line));
    _shift = (_line - rounded) * lines / 2;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c != null) context.paintChild(c, offset + Offset(0, _shift));
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.translateByDouble(0, _shift, 0, 1);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null) return false;
    return result.addWithPaintOffset(
      offset: Offset(0, _shift),
      position: position,
      hitTest: (result, transformed) =>
          c.hitTest(result, position: transformed),
    );
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final b = child?.getDistanceToActualBaseline(baseline);
    return b == null ? null : b + _shift;
  }
}
