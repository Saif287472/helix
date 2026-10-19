import 'package:flutter/material.dart';

import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';
import 'package:orbit_ui/src/theme/pattern_painter.dart';

/// Windows 840px and wider get panes (`HelixBreakpoints.medium`).
const double orbitWindowBreakpoint = 840;

/// From 1200px the info pane sits beside the chat (`.expanded`).
const double orbitInfoBreakpoint = 1200;

/// The list pane's width (`LIST_W` in `js/app.js`).
const double orbitListWidth = 380;

/// The info pane's width (`.stack.info-open`).
const double orbitInfoWidth = 360;

/// Where a page is drawn on a wide window (`PLACEMENT` in `js/app.js`).
enum OrbitPane { list, detail, info, full }

/// Tells a screen which pane it is in, so the frame's touches apply: no
/// back arrow on the first page on the right (the list is the way back), a
/// close button on the info pane's first page, and a readable width for
/// pages drawn for a phone. A phone has no scope.
class OrbitPaneScope extends InheritedWidget {
  const OrbitPaneScope({
    super.key,
    required this.pane,
    required this.root,
    required super.child,
  });

  final OrbitPane pane;

  /// The first page in its pane.
  final bool root;

  static OrbitPaneScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OrbitPaneScope>();

  @override
  bool updateShouldNotify(OrbitPaneScope old) =>
      old.pane != pane || old.root != root;
}

/// What the right pane says before anything is picked, for each list.
enum OrbitPlaceholderKind {
  chats(
    OrbitIcons.chatsCircle,
    'Pick a chat',
    'Choose a conversation on the left, or start a new one.',
    'Messages are end-to-end encrypted',
  ),
  calls(
    OrbitIcons.phone,
    'Pick a call',
    'Choose a call on the left to see its details, or start a new call.',
    null,
  ),
  you(
    OrbitIcons.userCircleGear,
    'Pick a setting',
    'Choose a topic on the left. Changes save as you go.',
    null,
  );

  const OrbitPlaceholderKind(this.icon, this.title, this.text, this.note);
  final OrbitGlyph icon;
  final String title;
  final String text;
  final String? note;
}

/// `OrbitWindowScaffold` (`css/window.css`): the list pane on the left, the
/// detail pane (or what to pick) beside it, from 1200px the info pane on
/// the right (below that it covers the detail), and a full-window layer on
/// top for calls, the media viewer and the centred sign-in box.
class OrbitWindowScaffold extends StatelessWidget {
  const OrbitWindowScaffold({
    super.key,
    required this.list,
    this.detail,
    this.detailRoot = true,
    this.info,
    this.infoRoot = true,
    this.full,
    this.fullBoxed = false,
    this.placeholder = OrbitPlaceholderKind.chats,
  });

  final Widget list;
  final Widget? detail;
  final bool detailRoot;
  final Widget? info;
  final bool infoRoot;
  final Widget? full;

  /// Sign-in, restore, link this device, reset and lock: a 440px box in the
  /// middle of a tinted page.
  final bool fullBoxed;
  final OrbitPlaceholderKind placeholder;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final beside = info != null && c.maxWidth >= orbitInfoBreakpoint;
        Widget pane(Widget child, OrbitPane p, bool root, double width) =>
            _Pane(
              pane: p,
              root: root,
              width: width,
              height: c.maxHeight,
              child: child,
            );
        final detailWidth =
            c.maxWidth - orbitListWidth - 1 - (beside ? orbitInfoWidth + 1 : 0);
        final right = detail == null
            ? _Placeholder(placeholder)
            : pane(detail!, OrbitPane.detail, detailRoot, detailWidth);
        return ColoredBox(
          color: t.bg,
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: orbitListWidth,
                    child: pane(list, OrbitPane.list, true, orbitListWidth),
                  ),
                  ColoredBox(color: t.line, child: const SizedBox(width: 1)),
                  Expanded(
                    child: info != null && !beside
                        ? pane(info!, OrbitPane.info, infoRoot, detailWidth)
                        : right,
                  ),
                  if (beside) ...[
                    ColoredBox(color: t.line, child: const SizedBox(width: 1)),
                    SizedBox(
                      width: orbitInfoWidth,
                      child: pane(
                        info!,
                        OrbitPane.info,
                        infoRoot,
                        orbitInfoWidth,
                      ),
                    ),
                  ],
                ],
              ),
              if (full != null)
                Positioned.fill(
                  child: fullBoxed
                      ? _Boxed(child: pane(full!, OrbitPane.full, true, 440))
                      : pane(full!, OrbitPane.full, true, c.maxWidth),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A pane: its own size and no status bar, as a screen sees it.
class _Pane extends StatelessWidget {
  const _Pane({
    required this.pane,
    required this.root,
    required this.width,
    required this.height,
    required this.child,
  });

  final OrbitPane pane;
  final bool root;
  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return OrbitPaneScope(
      pane: pane,
      root: root,
      child: MediaQuery(
        data: mq.copyWith(
          size: Size(width, height),
          padding: EdgeInsets.zero,
          viewPadding: EdgeInsets.zero,
        ),
        child: ClipRect(child: child),
      ),
    );
  }
}

/// `.page.boxed`: the centred box (440px wide, at most 640 tall, 24px
/// corner) on `--bg` with two soft colour washes.
class _Boxed extends StatelessWidget {
  const _Boxed({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: t.bg),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.76, -1),
                  radius: 0.7,
                  colors: [t.accentSoft, t.accentSoft.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.84, 1),
                  radius: 0.6,
                  colors: [t.tint, t.tint.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, c) {
              final v = (c.maxHeight / 2 - 320).clamp(40.0, double.infinity);
              final h = (c.maxWidth / 2 - 220).clamp(24.0, double.infinity);
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: h, vertical: v),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: t.surface,
                    border: Border.all(color: t.line),
                    borderRadius: BorderRadius.circular(t.rXl),
                    boxShadow: t.shadowFloat,
                  ),
                  child: child,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// `.w-empty`: the right pane before anything is picked. A small orbit (a
/// gradient core, a tilted ring and a moon), the title, what to do, and a
/// note.
class _Placeholder extends StatelessWidget {
  const _Placeholder(this.kind);

  final OrbitPlaceholderKind kind;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final note = kind.note;
    return OrbitPatternBackground(
      pattern: t.chatPattern,
      color: t.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 148,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      left: -2,
                      right: -2,
                      top: 22,
                      bottom: 22,
                      child: Transform.rotate(
                        angle: -18 * 3.14159265 / 180,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: t.accentLine, width: 1.5),
                            borderRadius: const BorderRadius.all(
                              Radius.elliptical(76, 52),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        gradient: t.brandGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: t.accent,
                            offset: const Offset(0, 18),
                            blurRadius: 40,
                            spreadRadius: -20,
                          ),
                          ...t.glow,
                        ],
                      ),
                      child: Center(
                        child: OrbitIcon(
                          kind.icon,
                          weight: OrbitIconWeight.fill,
                          size: 38,
                          color: t.onBrand,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 137,
                      top: 46,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: t.accent,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: t.bg, spreadRadius: 4)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              OrbitText(
                kind.title,
                textAlign: TextAlign.center,
                style: t.display(size: 22, height: 1.2),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: OrbitText(
                  kind.text,
                  textAlign: TextAlign.center,
                  style: t.font.style(
                    size: OrbitType.small,
                    color: t.ink3,
                    height: 1.5,
                  ),
                ),
              ),
              if (note != null) ...[
                const SizedBox(height: 22),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OrbitIcon(OrbitIcons.lockSimple, size: 11.5, color: t.ink3),
                    const SizedBox(width: 6),
                    Text(note, style: t.mono.style(size: 11.5, color: t.ink3)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// What is open on the right of a wide window, so the list marks it
/// (`.chat-row.current`, `.stile.current`).
class OrbitCurrentScope extends InheritedWidget {
  const OrbitCurrentScope({super.key, required this.id, required super.child});

  /// A chat id (`direct:nadia`), a call id or a topic.
  final String? id;

  static String? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OrbitCurrentScope>()?.id;

  @override
  bool updateShouldNotify(OrbitCurrentScope old) => old.id != id;
}
