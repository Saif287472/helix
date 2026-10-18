import 'package:flutter/material.dart';
import 'package:orbit_ui/compare.dart' show OrbitDevice;
import 'package:orbit_ui/orbit_ui.dart';

/// One screen on one device, exactly as the prototype's bare mode draws it.
///
/// The prototype's `.phone-screen` (`css/shell.css`, `css/components.css`):
/// the theme's `--bg` behind everything, a 40px status bar laid over the top
/// and a gesture bar over the bottom. A screen reads the status bar as its top
/// inset, the way it will read the real one on a phone, so nothing in
/// `orbit_ui` knows it is in a preview.
///
/// The windows have no device chrome of their own yet; the title bar arrives
/// with the window layouts in Phase 4.
///
/// Everything the platform would otherwise decide is pinned here, because a
/// screenshot must not depend on the machine it was taken on: one logical pixel
/// per pixel, no text scaling, and reduce motion only when asked for.
class OrbitDeviceSurface extends StatelessWidget {
  const OrbitDeviceSurface({
    super.key,
    required this.device,
    required this.tokens,
    required this.child,
    this.reduceMotion = false,
  });

  final OrbitDevice device;
  final OrbitTokens tokens;
  final Widget child;
  final bool reduceMotion;

  /// `.statusbar { height: 40px }`, which `.page` pads its content below.
  static const statusBarHeight = 40.0;

  bool get _phone => device == OrbitDevice.phone;

  @override
  Widget build(BuildContext context) {
    final size = Size(device.width.toDouble(), device.height.toDouble());
    final theme = OrbitTheme.of(tokens).copyWith(
      platform: _phone ? TargetPlatform.android : TargetPlatform.windows,
    );
    return SizedBox.fromSize(
      size: size,
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          devicePixelRatio: 1,
          textScaler: TextScaler.noScaling,
          platformBrightness: tokens.meta.dark
              ? Brightness.dark
              : Brightness.light,
          padding: EdgeInsets.only(top: _phone ? statusBarHeight : 0),
          viewPadding: EdgeInsets.only(top: _phone ? statusBarHeight : 0),
          disableAnimations: reduceMotion,
        ),
        child: Theme(
          data: theme,
          child: Material(
            color: tokens.bg,
            child: Stack(
              children: [
                // The screen's own navigator, so a sheet, dialog or toast
                // opens inside the phone, under its status bar, as the
                // prototype's overlay layer does.
                Positioned.fill(
                  child: Navigator(
                    pages: [MaterialPage<void>(child: child)],
                    onDidRemovePage: (_) {},
                  ),
                ),
                if (_phone) ...[
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: statusBarHeight,
                    child: _StatusBar(),
                  ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 7,
                    child: Center(child: _GestureBar()),
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

/// `.statusbar`: 9:41 and three filled icons, mono 13px at 500, in `--ink`.
class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    Widget icon(OrbitGlyph glyph) =>
        OrbitIcon(glyph, weight: OrbitIconWeight.fill, size: 15, color: t.ink);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 6, 28, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '9:41',
              style: t.mono.style(size: 13, weight: 500, color: t.ink),
            ),
            Row(
              children: [
                icon(OrbitIcons.cellSignalFull),
                const SizedBox(width: 5),
                icon(OrbitIcons.wifiHigh),
                const SizedBox(width: 5),
                icon(OrbitIcons.batteryHigh),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// `.gesture-bar`: 120×4, corner 4, `--gesture`, 7px off the bottom.
class _GestureBar extends StatelessWidget {
  const _GestureBar();

  @override
  Widget build(BuildContext context) => Container(
    width: 120,
    height: 4,
    decoration: BoxDecoration(
      color: OrbitTokens.of(context).gesture,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}
