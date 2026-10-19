import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
class OrbitDeviceSurface extends StatefulWidget {
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

  /// The screen under the status bar is a night page.
  static final _night = ValueNotifier(false);

  @override
  State<OrbitDeviceSurface> createState() => _OrbitDeviceSurfaceState();
}

class _OrbitDeviceSurfaceState extends State<OrbitDeviceSurface> {
  // One per surface: a shared key would carry a screen's state into the
  // next shot.
  final _screen = GlobalKey(debugLabel: 'screen');

  bool get _phone => widget.device == OrbitDevice.phone;

  static const statusBarHeight = OrbitDeviceSurface.statusBarHeight;

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final tokens = widget.tokens;
    final reduceMotion = widget.reduceMotion;
    final child = widget.child;
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
                  child: RepaintBoundary(
                    key: _screen,
                    child: Navigator(
                      pages: [MaterialPage<void>(child: child)],
                      onDidRemovePage: (_) {},
                    ),
                  ),
                ),
                if (_phone) ...[
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: statusBarHeight,
                    child: _StatusBar(screen: _screen),
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

/// `.statusbar`: 9:41 and three filled icons, mono 13px at 500, in `--ink`;
/// in `--night-text` over a night page (`.phone-screen.on-night`). A screen
/// says it is a night page the way it tells a phone, with an
/// `AnnotatedRegion<SystemUiOverlayStyle>` whose icons are light; the bar
/// reads the region under it after every frame.
class _StatusBar extends StatefulWidget {
  const _StatusBar({required this.screen});

  final GlobalKey screen;

  @override
  State<_StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<_StatusBar> {
  var _night = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPersistentFrameCallback(_check);
  }

  void _check(Duration _) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = widget.screen.currentContext?.findRenderObject();
      // ignore: invalid_use_of_protected_member
      final layer = box is RenderRepaintBoundary ? box.layer : null;
      final style = layer?.find<SystemUiOverlayStyle>(const Offset(200, 20));
      final night = style?.statusBarIconBrightness == Brightness.light;
      if (night != _night) setState(() => _night = night);
      OrbitDeviceSurface._night.value = night;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final ink = _night ? OrbitNight.text : t.ink;
    Widget icon(OrbitGlyph glyph) =>
        OrbitIcon(glyph, weight: OrbitIconWeight.fill, size: 15, color: ink);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 6, 28, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '9:41',
              style: t.mono.style(size: 13, weight: 500, color: ink),
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

/// `.gesture-bar`: 120×4, corner 4, `--gesture`, 7px off the bottom;
/// `rgba(234, 238, 248, 0.45)` over a night page.
class _GestureBar extends StatelessWidget {
  const _GestureBar();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: OrbitDeviceSurface._night,
    builder: (context, night, _) => Container(
      width: 120,
      height: 4,
      decoration: BoxDecoration(
        color: night
            ? OrbitNight.text.withValues(alpha: 0.45)
            : OrbitTokens.of(context).gesture,
        borderRadius: BorderRadius.circular(4),
      ),
    ),
  );
}
