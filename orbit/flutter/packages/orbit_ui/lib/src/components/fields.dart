import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:orbit_ui/src/components/icon_button.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// `Kit.field` (`js/kit.js`; `.fld` in `css/pages.css`): a label, a box, and
/// the helper or error under it, 6px apart, with 14px under the whole field.
///
/// - The label is `--t-caption` at weight 560 in `--ink-2`, 2px in.
/// - The box is at least 52px, corner `--r-md`, `--surface` with a 1px
///   `--line` edge, 14px in on the left and 4px on the right; the text is
///   `--t-body` in `--ink` with 14px above and below. Focused, the edge is
///   `--accent` with a 3px `--accent-soft` ring; with an [error], `--danger`
///   with a `--danger-soft` ring.
/// - [prefix]: mono in `--ink-2`, a `--line` rule 10px after it, the text
///   8px after that (`+880`, `~`).
/// - [mono]: the text in mono, tracked 0.04em.
/// - [eye] and [onPaste]: 44px icon buttons at the end, 19px, `--ink-3`.
/// - [counter]: `5/50` in mono 10.5px at the top right, over the label row.
/// - [rows]: a text area that tall.
class OrbitTextField extends StatefulWidget {
  const OrbitTextField({
    super.key,
    this.label = '',
    this.initialValue = '',
    this.controller,
    this.hint = '',
    this.helper = '',
    this.helperOk = false,
    this.error = '',
    this.prefix = '',
    this.obscure = false,
    this.eye = false,
    this.onPaste,
    this.mono = false,
    this.maxLength,
    this.counter = false,
    this.rows,
    this.keyboardType,
    this.enabled = true,
    this.onChanged,
    this.autofocus = false,
    this.bottom = 14,
    this.big = false,
    this.onPrefixTap,
  });

  final String label;
  final String initialValue;
  final TextEditingController? controller;
  final String hint;
  final String helper;

  /// The helper is good news: `--success` with a filled tick (the ~name
  /// that looks right).
  final bool helperOk;
  final String error;
  final String prefix;

  /// `type="password"`.
  final bool obscure;

  /// The show/hide button of a password field.
  final bool eye;
  final VoidCallback? onPaste;
  final bool mono;
  final int? maxLength;
  final bool counter;
  final int? rows;
  final TextInputType? keyboardType;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  /// Focused when it opens (a dialog's field).
  final bool autofocus;

  /// The space under the field: 14px, or none where the margin collapses
  /// into a larger one below it (a dialog's buttons).
  final double bottom;

  /// `.fld.big`: a one-time code, mono 26px tracked 0.5em, centred, 12px
  /// above and below.
  final bool big;

  /// The prefix is a button (`.fld-country`: the country code with a 12px
  /// bold caret in `--ink-3`, at least 48px tall).
  final VoidCallback? onPrefixTap;

  @override
  State<OrbitTextField> createState() => _OrbitTextFieldState();
}

class _OrbitTextFieldState extends State<OrbitTextField> {
  late final TextEditingController _own = TextEditingController(
    text: widget.initialValue,
  );
  final _focus = FocusNode();
  var _shown = false;

  TextEditingController get _controller => widget.controller ?? _own;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    _controller.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _own.dispose();
    _focus.dispose();
    super.dispose();
  }

  Widget _prefix(OrbitTokens t) {
    final w = widget;
    final label = Text(
      w.prefix,
      style: t.mono.style(size: OrbitType.body, color: t.ink2),
    );
    final tap = w.onPrefixTap;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: t.line)),
      ),
      child: tap == null
          ? label
          : Semantics(
              button: true,
              label: 'Country code ${w.prefix}',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: tap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: OrbitSpace.target,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      label,
                      const SizedBox(width: 4),
                      OrbitIcon(
                        OrbitIcons.caretDown,
                        weight: OrbitIconWeight.bold,
                        size: 12,
                        color: t.ink3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final w = widget;
    final hasError = w.error.isNotEmpty;
    final focused = _focus.hasFocus;
    final text = w.big
        ? t.mono.style(size: 26, color: t.ink, letterSpacingEm: 0.5)
        : w.mono
        ? t.mono.style(
            size: OrbitType.body,
            color: w.enabled ? t.ink : t.ink3,
            letterSpacingEm: 0.04,
          )
        : t.font.style(size: OrbitType.body, color: w.enabled ? t.ink : t.ink3);
    final rows = w.rows;
    final input = TextField(
      controller: _controller,
      focusNode: _focus,
      autofocus: w.autofocus,
      enabled: w.enabled,
      obscureText: w.obscure && !_shown,
      keyboardType: rows != null ? TextInputType.multiline : w.keyboardType,
      minLines: rows ?? 1,
      maxLines: rows ?? 1,
      inputFormatters: [
        if (w.maxLength != null) LengthLimitingTextInputFormatter(w.maxLength),
      ],
      onChanged: w.onChanged,
      textAlign: w.big ? TextAlign.center : TextAlign.start,
      style: text,
      cursorColor: t.accent,
      cursorHeight: OrbitType.body * 1.2,
      decoration: InputDecoration.collapsed(
        hintText: w.hint,
        hintStyle: text.copyWith(color: t.ink4),
      ).copyWith(isDense: true),
    );
    final edge = hasError
        ? t.danger
        : focused
        ? t.accent
        : t.line;
    final ring = hasError
        ? t.dangerSoft
        : focused
        ? t.accentSoft
        : null;
    final box = Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: edge),
        borderRadius: BorderRadius.circular(t.rMd),
        boxShadow: ring == null
            ? null
            : [BoxShadow(color: ring, spreadRadius: 3)],
      ),
      child: Row(
        children: [
          if (w.prefix.isNotEmpty) _prefix(t),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: w.big ? 12 : 14),
              child: input,
            ),
          ),
          if (w.eye)
            OrbitIconButton(
              icon: _shown ? OrbitIcons.eyeSlash : OrbitIcons.eye,
              tooltip: _shown ? 'Hide password' : 'Show password',
              onPressed: () => setState(() => _shown = !_shown),
              size: 44,
              iconSize: 19,
              color: t.ink3,
            ),
          if (w.onPaste != null)
            OrbitIconButton(
              icon: OrbitIcons.clipboardText,
              tooltip: 'Paste',
              onPressed: w.onPaste,
              size: 44,
              iconSize: 19,
              color: t.ink3,
            ),
        ],
      ),
    );
    final max = w.maxLength;
    return Padding(
      padding: EdgeInsets.only(bottom: w.bottom),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (w.label.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: OrbitText(
                    w.label,
                    style: t.font.style(
                      size: OrbitType.caption,
                      weight: 560,
                      color: t.ink2,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              box,
              if (hasError) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: OrbitIcon(
                          OrbitIcons.warningCircle,
                          weight: OrbitIconWeight.fill,
                          size: 15,
                          color: t.danger,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OrbitText(
                          w.error,
                          style: t.font.style(
                            size: OrbitType.caption,
                            color: t.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (w.helper.isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: OrbitText.rich(
                    TextSpan(
                      children: [
                        if (w.helperOk) ...[
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: OrbitIcon(
                              OrbitIcons.checkCircle,
                              weight: OrbitIconWeight.fill,
                              size: OrbitType.caption,
                              color: t.success,
                            ),
                          ),
                          const TextSpan(text: ' '),
                        ],
                        TextSpan(text: w.helper),
                      ],
                    ),
                    style: t.font.style(
                      size: OrbitType.caption,
                      color: w.helperOk ? t.success : t.ink3,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (w.counter && max != null)
            Positioned(
              top: 0,
              right: 4,
              child: OrbitText(
                '${_controller.text.characters.length}/$max',
                style: t.mono.style(size: 10.5, color: t.ink3),
              ),
            ),
        ],
      ),
    );
  }
}

/// `Kit.seg` (`.seg` in `css/pages.css`): options sharing the width, 4px
/// apart on `--field` 4px in, corner `--r-md`. Each is 40px tall, corner 10,
/// `--t-small` at weight 560 in `--ink-3`, an optional 17px icon 6px before
/// it; the chosen one is `--surface` in `--ink` with a faint shadow.
class OrbitSegmented<T> extends StatelessWidget {
  const OrbitSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.small = false,
  });

  final List<OrbitSegment<T>> options;
  final T value;
  final ValueChanged<T>? onChanged;

  /// `.seg.sm`: 36px segments at 12.5px (the choices under a setting).
  final bool small;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.field,
        borderRadius: BorderRadius.circular(t.rMd),
      ),
      child: Row(
        children: [
          for (final (i, o) in options.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(child: _segment(t, o)),
          ],
        ],
      ),
    );
  }

  Widget _segment(OrbitTokens t, OrbitSegment<T> o) {
    final on = o.value == value;
    final ink = on ? t.ink : t.ink3;
    final change = onChanged;
    return Semantics(
      selected: on,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: change == null ? null : () => change(o.value),
        child: Container(
          height: small ? 36 : 40,
          decoration: BoxDecoration(
            color: on ? t.surface : null,
            borderRadius: BorderRadius.circular(10),
            boxShadow: on
                ? [
                    BoxShadow(
                      // The prototype's own rgba(19, 23, 34, 0.1), in
                      // every theme.
                      color: const Color(0x1A131722),
                      offset: const Offset(0, 1),
                      blurRadius: orbitCssBlur(3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (o.icon != null) ...[
                OrbitIcon(o.icon!, size: 17, color: ink),
                const SizedBox(width: 6),
              ],
              OrbitText(
                o.label,
                style: t.font.style(
                  size: small ? 12.5 : OrbitType.small,
                  weight: 560,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One option of an [OrbitSegmented].
class OrbitSegment<T> {
  const OrbitSegment(this.value, this.label, {this.icon});

  final T value;
  final String label;
  final OrbitGlyph? icon;
}
