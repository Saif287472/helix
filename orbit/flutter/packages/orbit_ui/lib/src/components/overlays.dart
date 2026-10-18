import 'dart:async';

import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/fields.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/theme/motion.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// One row of a sheet or a menu (`items` in `App.sheet` and `App.menu`,
/// `js/app.js`), or a rule between rows ([OrbitMenuItem.divider]).
class OrbitMenuItem {
  const OrbitMenuItem({
    required this.icon,
    required this.label,
    this.sub = '',
    this.danger = false,
    this.on = false,
    this.onTap,
  }) : _divider = false;

  const OrbitMenuItem._divider()
    : icon = OrbitIcons.minus,
      label = '',
      sub = '',
      danger = false,
      on = false,
      onTap = null,
      _divider = true;

  /// The `'-'` between rows.
  static const divider = OrbitMenuItem._divider();

  final OrbitGlyph icon;
  final String label;

  /// A line under the label (`mr-sub`), sheets only.
  final String sub;
  final bool danger;

  /// The chosen one in a choice sheet: `--accent-ink`, weight 560 and a tick.
  final bool on;

  /// Runs after the overlay has closed.
  final VoidCallback? onTap;
  final bool _divider;

  bool get isDivider => _divider;
}

/// `.sheet` (`css/components.css`): the bottom sheet's panel. `--surface`,
/// corners 28 on top, `--shadow-sheet`, 10px above and 30px below; a 40×4
/// `--line` grab handle 10px over the head; the title in the display face at
/// 18px and the text at `--t-small` in `--ink-3` 6px under it, 6px 20px 12px
/// in; then the rows, 54px tall and 22px in, a 21px icon in `--ink-2` 16px
/// before the label at `--t-body`. At most 86% of the screen; the rows scroll.
class OrbitSheetPanel extends StatelessWidget {
  const OrbitSheetPanel({
    super.key,
    this.title = '',
    this.text = '',
    this.items = const [],
    this.body,
    this.onItem,
    this.heightFactor,
  });

  final String title;
  final String text;
  final List<OrbitMenuItem> items;

  /// A fixed height as a share of the screen (the legal sheet's 88%); by
  /// default the sheet is as tall as its content, up to 86%.
  final double? heightFactor;

  /// Content in place of the rows.
  final Widget? body;

  /// A row was tapped (the route closes the sheet, then runs it).
  final ValueChanged<OrbitMenuItem>? onItem;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final rows =
        body ??
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final it in items) _row(t, it)],
        );
    final screen = MediaQuery.sizeOf(context).height;
    final fixed = heightFactor;
    return ConstrainedBox(
      constraints: fixed == null
          ? BoxConstraints(maxHeight: screen * 0.86)
          : BoxConstraints.tightFor(height: screen * fixed),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: t.shadowSheet,
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 30),
          child: Column(
            mainAxisSize: fixed == null ? MainAxisSize.min : MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: t.line,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              if (title.isNotEmpty || text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (title.isNotEmpty)
                        Semantics(
                          header: true,
                          child: OrbitText(
                            orbitTransform(title, t.displayTransform),
                            style: t.display(size: 18),
                          ),
                        ),
                      if (text.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: title.isEmpty ? 0 : 6),
                          child: OrbitText(
                            text,
                            style: t.font.style(
                              size: OrbitType.small,
                              color: t.ink3,
                              height: 1.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              Flexible(child: SingleChildScrollView(child: rows)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(OrbitTokens t, OrbitMenuItem it) {
    if (it.isDivider) {
      return Container(
        height: 1,
        margin: const EdgeInsets.symmetric(vertical: 6),
        color: t.line2,
      );
    }
    final ink = it.danger
        ? t.danger
        : it.on
        ? t.accentInk
        : t.ink;
    final iconInk = it.danger
        ? t.danger
        : it.on
        ? t.accent
        : t.ink2;
    return Semantics(
      button: true,
      selected: it.on,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => onItem?.call(it),
          splashFactory: NoSplash.splashFactory,
          hoverColor: t.hover,
          highlightColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 54),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                children: [
                  OrbitIcon(it.icon, size: 21, color: iconInk),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OrbitText(
                          it.label,
                          style: t.font.style(
                            size: OrbitType.body,
                            weight: it.on ? 560 : 400,
                            color: ink,
                          ),
                        ),
                        if (it.sub.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: OrbitText(
                              it.sub,
                              style: t.font.style(
                                size: OrbitType.caption,
                                color: t.ink3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (it.on) ...[
                    const SizedBox(width: 16),
                    OrbitIcon(
                      OrbitIcons.check,
                      weight: OrbitIconWeight.bold,
                      size: 21,
                      color: iconInk,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.popmenu` (`css/components.css`): the menu under an app bar's ⋮, at
/// least 230 wide, `--surface` with a `--line` edge, corner `--r-md`,
/// `--shadow-float`, 6px in. Rows are 48px, 12px in, corner 10, a 19px icon
/// in `--ink-3` 12px before the label at 14.5px; rules are 1px `--line-2`,
/// 4px 6px apart.
class OrbitMenuPanel extends StatelessWidget {
  const OrbitMenuPanel({super.key, required this.items, this.onItem});

  final List<OrbitMenuItem> items;
  final ValueChanged<OrbitMenuItem>? onItem;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 230),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(t.rMd),
        boxShadow: t.shadowFloat,
      ),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final it in items)
              if (it.isDivider)
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  color: t.line2,
                )
              else
                Semantics(
                  button: true,
                  child: Material(
                    type: MaterialType.transparency,
                    borderRadius: BorderRadius.circular(10),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onItem?.call(it),
                      splashFactory: NoSplash.splashFactory,
                      hoverColor: t.field,
                      highlightColor: Colors.transparent,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: OrbitSpace.target,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              OrbitIcon(
                                it.icon,
                                size: 19,
                                color: it.danger ? t.danger : t.ink3,
                              ),
                              const SizedBox(width: 12),
                              OrbitText(
                                it.label,
                                style: t.font.style(
                                  size: 14.5,
                                  color: it.danger ? t.danger : t.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// One button of a dialog (`actions` in `App.dialog`): `.ghost` unless it
/// says otherwise.
class OrbitDialogAction {
  const OrbitDialogAction(
    this.label, {
    this.kind = OrbitButtonKind.ghost,
    this.onPressed,
  });

  final String label;
  final OrbitButtonKind kind;

  /// Runs after the dialog has closed.
  final VoidCallback? onPressed;
}

/// `.dialog` (`css/components.css`): 24px in from each side, centred,
/// `--surface`, corner `--r-xl`, 22px 22px 14px in, a deep shadow; the title
/// in the display face at 18px, 8px over the text at `--t-small` in
/// `--ink-3`, line height 1.5; the buttons 44px tall and 16px in, at the
/// right, 6px apart, 18px under the text. [body] is a dialog's field.
class OrbitDialogPanel extends StatelessWidget {
  const OrbitDialogPanel({
    super.key,
    required this.title,
    this.text = '',
    this.body,
    required this.actions,
    this.onAction,
  });

  final String title;
  final String text;
  final Widget? body;
  final List<OrbitDialogAction> actions;
  final ValueChanged<OrbitDialogAction>? onAction;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final content = body;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(t.rXl),
        boxShadow: [
          BoxShadow(
            // The prototype's own rgba(13, 16, 25, 0.3), in every theme.
            color: const Color(0x4D0D1019),
            offset: const Offset(0, 30),
            blurRadius: orbitCssBlur(80),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: OrbitText(
              orbitTransform(title, t.displayTransform),
              style: t.display(size: 18),
            ),
          ),
          const SizedBox(height: 8),
          if (text.isNotEmpty)
            OrbitText(
              text,
              style: t.font.style(
                size: OrbitType.small,
                color: t.ink3,
                height: 1.5,
              ),
            ),
          ?content,
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in actions)
                OrbitButton(
                  label: a.label,
                  kind: a.kind,
                  height: 44,
                  padding: 16,
                  onPressed: () => onAction?.call(a),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `#snackbar` (`.snackbar` in `css/components.css`): 16px in from each
/// side and 104px up, `--inverse` with `--on-inverse` text at `--t-small`,
/// corner `--r-md`, 13px 16px in, `--shadow-float`. An [error] toast keeps
/// the colours and adds a 4px `--danger` edge on the left, 18px in, and a
/// filled warning icon; an action is mono 12px upper case in
/// `--inverse-accent` at the right.
class OrbitToast extends StatelessWidget {
  const OrbitToast({
    super.key,
    required this.text,
    this.error = false,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final bool error;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final label = actionLabel;
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.rMd),
          boxShadow: t.shadowFloat,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(t.rMd),
          child: ColoredBox(
            color: t.inverse,
            child: Stack(
              children: [
                if (error)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 4,
                    child: ColoredBox(color: t.danger),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(error ? 18 : 16, 13, 16, 13),
                  child: Row(
                    children: [
                      if (error) ...[
                        OrbitIcon(
                          OrbitIcons.warningCircle,
                          weight: OrbitIconWeight.fill,
                          size: 18,
                          color: t.onInverse,
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: OrbitText(
                          text,
                          style: t.font.style(
                            size: OrbitType.small,
                            color: t.onInverse,
                          ),
                        ),
                      ),
                      if (label != null) ...[
                        const SizedBox(width: 12),
                        Semantics(
                          button: true,
                          child: OrbitTapArea(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onAction,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                child: OrbitText(
                                  label.toUpperCase(),
                                  style: t.mono.style(
                                    size: 12,
                                    weight: 600,
                                    color: t.inverseAccent,
                                    letterSpacingEm: 0.06,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
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

enum _OverlayKind { sheet, menu, dialog }

/// The route every overlay opens on: a `--scrim` (clear behind a menu) that
/// closes it when tapped, and the panel coming in as the prototype's does: a
/// sheet slides up over `--dur-page`; a dialog grows from 96% and rises a
/// little, and a menu grows from 92% at its top right, over `--dur`. All
/// fade in, and none move under reduce motion.
class _OrbitOverlayRoute<T> extends PopupRoute<T> {
  _OrbitOverlayRoute({
    required this.kind,
    required this.tokens,
    required this.reduceMotion,
    required this.builder,
    this.menuTop = 92,
  });

  final _OverlayKind kind;
  final OrbitTokens tokens;
  final bool reduceMotion;
  final WidgetBuilder builder;
  final double menuTop;

  @override
  Color? get barrierColor =>
      kind == _OverlayKind.menu ? Colors.transparent : tokens.scrim;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Close';

  @override
  Duration get transitionDuration => reduceMotion
      ? Duration.zero
      : kind == _OverlayKind.sheet
      ? tokens.motion.page
      : tokens.motion.short;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    // Its own Material, because a route sits above the page's (fields and
    // ink need one).
    final panel = Material(
      type: MaterialType.transparency,
      child: builder(context),
    );
    return switch (kind) {
      _OverlayKind.sheet => Align(
        alignment: Alignment.bottomCenter,
        child: panel,
      ),
      _OverlayKind.dialog => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: panel,
        ),
      ),
      _OverlayKind.menu => Stack(
        children: [Positioned(top: menuTop, right: 12, child: panel)],
      ),
    };
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final a = CurvedAnimation(parent: animation, curve: tokens.motion.curve);
    return switch (kind) {
      _OverlayKind.sheet => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(a),
        child: child,
      ),
      _OverlayKind.dialog => FadeTransition(
        opacity: a,
        child: AnimatedBuilder(
          animation: a,
          builder: (context, child) => Transform.translate(
            // `translateY(-46%)` to `-50%` of a dialog about 200px tall.
            offset: Offset(0, 8 * (1 - a.value)),
            child: Transform.scale(scale: 0.96 + 0.04 * a.value, child: child),
          ),
          child: child,
        ),
      ),
      _OverlayKind.menu => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.0).animate(a),
          alignment: Alignment.topRight,
          child: child,
        ),
      ),
    };
  }
}

Future<void> _open(
  BuildContext context,
  _OverlayKind kind,
  Widget Function(BuildContext, void Function(VoidCallback?) done) panel, {
  double menuTop = 92,
}) {
  final tokens = OrbitTokens.of(context);
  final navigator = Navigator.of(context);
  // Close first, then run what was chosen a beat later, as the prototype
  // does, so a second overlay opens over the page and not over this one.
  void done(VoidCallback? run) {
    navigator.pop();
    if (run != null) Timer(const Duration(milliseconds: 60), run);
  }

  return navigator.push(
    _OrbitOverlayRoute<void>(
      kind: kind,
      tokens: tokens,
      reduceMotion: !OrbitMotion.allowed(context),
      menuTop: menuTop,
      builder: (context) => panel(context, done),
    ),
  );
}

/// `App.sheet` (`js/app.js`): a bottom sheet of [items] or a [body].
Future<void> showOrbitSheet(
  BuildContext context, {
  String title = '',
  String text = '',
  List<OrbitMenuItem> items = const [],
  Widget? body,
  double? heightFactor,
}) => _open(
  context,
  _OverlayKind.sheet,
  (context, done) => OrbitSheetPanel(
    title: title,
    text: text,
    items: items,
    body: body,
    heightFactor: heightFactor,
    onItem: (it) => done(it.onTap),
  ),
);

/// `App.menu` (`js/app.js`): the menu under the app bar's ⋮, [top] px from
/// the top of the screen and 12px from the right.
Future<void> showOrbitMenu(
  BuildContext context,
  List<OrbitMenuItem> items, {
  double top = 92,
}) => _open(
  context,
  _OverlayKind.menu,
  (context, done) =>
      OrbitMenuPanel(items: items, onItem: (it) => done(it.onTap)),
  menuTop: top,
);

/// `App.dialog` (`js/app.js`).
Future<void> showOrbitDialog(
  BuildContext context, {
  required String title,
  String text = '',
  required List<OrbitDialogAction> actions,
}) => _open(
  context,
  _OverlayKind.dialog,
  (context, done) => OrbitDialogPanel(
    title: title,
    text: text,
    actions: actions,
    onAction: (a) => done(a.onPressed),
  ),
);

/// `Kit.inputDialog` (`js/kit.js`): a dialog with one field, focused, and
/// Cancel and [confirmLabel]; [onConfirm] gets the text.
Future<void> showOrbitInputDialog(
  BuildContext context, {
  required String title,
  required String label,
  String value = '',
  int maxLength = 60,
  String confirmLabel = 'Save',
  ValueChanged<String>? onConfirm,
}) => _open(
  context,
  _OverlayKind.dialog,
  (context, done) => _InputDialog(
    title: title,
    label: label,
    value: value,
    maxLength: maxLength,
    confirmLabel: confirmLabel,
    onConfirm: onConfirm,
    done: done,
  ),
);

/// The input dialog's panel, which owns its text until it is gone (the
/// route still draws it while it closes).
class _InputDialog extends StatefulWidget {
  const _InputDialog({
    required this.title,
    required this.label,
    required this.value,
    required this.maxLength,
    required this.confirmLabel,
    required this.onConfirm,
    required this.done,
  });

  final String title;
  final String label;
  final String value;
  final int maxLength;
  final String confirmLabel;
  final ValueChanged<String>? onConfirm;
  final void Function(VoidCallback?) done;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final _text = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final confirm = widget.onConfirm;
    return OrbitDialogPanel(
      title: widget.title,
      // The field's 14px margin collapses into the 18px over the buttons.
      body: OrbitTextField(
        label: widget.label,
        controller: _text,
        maxLength: widget.maxLength,
        autofocus: true,
        bottom: 0,
      ),
      actions: [
        const OrbitDialogAction('Cancel'),
        OrbitDialogAction(
          widget.confirmLabel,
          kind: OrbitButtonKind.primary,
          onPressed: confirm == null ? null : () => confirm(_text.text),
        ),
      ],
      onAction: (a) => widget.done(a.onPressed),
    );
  }
}

OverlayEntry? _toast;
Timer? _toastTimer;

/// `App.snack` (`js/app.js`): a toast over the bottom of the screen, gone
/// after 2.8s (4s for an [error]), or kept up when [stay] (for a shot of the
/// state). A new toast replaces the one showing.
void showOrbitToast(
  BuildContext context,
  String text, {
  bool error = false,
  String? actionLabel,
  VoidCallback? onAction,
  bool stay = false,
}) {
  _toastTimer?.cancel();
  _toast?.remove();
  final overlay = Overlay.of(context);
  final tokens = OrbitTokens.of(context);
  final motion = OrbitMotion.allowed(context);
  late final OverlayEntry entry;
  void close() {
    if (_toast == entry) {
      entry.remove();
      _toast = null;
    }
  }

  entry = OverlayEntry(
    builder: (context) => Positioned(
      left: 16,
      right: 16,
      bottom: 104,
      child: Material(
        type: MaterialType.transparency,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: motion ? 0 : 1, end: 1),
          duration: motion ? tokens.motion.page : Duration.zero,
          curve: tokens.motion.curve,
          builder: (context, v, child) => Opacity(
            opacity: v,
            child: Transform.translate(
              offset: Offset(0, 16 * (1 - v)),
              child: child,
            ),
          ),
          child: OrbitToast(
            text: text,
            error: error,
            actionLabel: actionLabel,
            onAction: onAction == null
                ? null
                : () {
                    close();
                    onAction();
                  },
          ),
        ),
      ),
    ),
  );
  _toast = entry;
  overlay.insert(entry);
  if (!stay) {
    _toastTimer = Timer(Duration(milliseconds: error ? 4000 : 2800), close);
  }
}
