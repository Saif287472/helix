import 'dart:io';

import 'package:flutter/material.dart';
import 'package:orbit_preview/device.dart';
import 'package:orbit_preview/index.dart';
import 'package:orbit_preview/ported.dart';
import 'package:orbit_preview/shoot.dart';
import 'package:orbit_preview/theme_library.dart';
import 'package:orbit_ui/compare.dart' show OrbitDevice;
import 'package:orbit_ui/orbit_ui.dart';

/// The preview app: the Flutter twin of the HTML viewer.
///
/// It runs on fake data and touches nothing in `helix_remote`. Its jobs:
///
/// - **load every theme** from its JSON file, so a theme is proven to be data;
/// - **show them in the gallery**, which is Review 2's first half;
/// - **offer the device frames** the prototype uses - 412x866, 960x720 and
///   1280x800 - so a screenshot is the same size on both sides;
/// - **shoot mode** (`shoot.dart`): photograph ported screens and compare them
///   with the prototype's shots.
///
/// The screen index comes from `index.dart`, generated from the prototype's own
/// `screens.json`: the keys must match exactly, because the compare tool looks
/// the same key up on both sides.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  OrbitFonts.registerPack(orbitPreviewPackFonts);
  final shoot = ShootRequest.parse(args);
  if (shoot != null) {
    // Shoot mode runs unattended, so any failure ends the app with exit code
    // 1 and the reason, rather than leaving a window open on an error.
    try {
      exit(await runShoot(await OrbitThemeLibrary.load(), shoot));
    } on Object catch (e, s) {
      stderr
        ..writeln('shoot failed: $e')
        ..writeln(s);
      exit(1);
    }
  }
  runApp(OrbitPreviewApp(library: await OrbitThemeLibrary.load()));
}

class OrbitPreviewApp extends StatelessWidget {
  const OrbitPreviewApp({super.key, required this.library});

  final OrbitThemeLibrary library;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Orbit preview',
    debugShowCheckedModeBanner: false,
    theme: OrbitTheme.of(library.byId('orbit')),
    home: PreviewShell(library: library),
  );
}

/// The viewer's own frame: a chosen theme on the left, the screen index, and
/// the chosen screen in a device frame.
class PreviewShell extends StatefulWidget {
  const PreviewShell({super.key, required this.library});

  final OrbitThemeLibrary library;

  @override
  State<PreviewShell> createState() => _PreviewShellState();
}

class _PreviewShellState extends State<PreviewShell> {
  String _themeId = 'orbit';
  String _screenKey = 'signin';

  @override
  Widget build(BuildContext context) {
    final tokens = widget.library.byId(_themeId);
    return OrbitThemeScope(
      tokens: tokens,
      child: Theme(
        data: OrbitTheme.of(tokens),
        child: Scaffold(
          body: Row(
            children: [
              _sidebar(context, tokens),
              const VerticalDivider(width: 1),
              Expanded(
                child: DeviceFrame(
                  tokens: tokens,
                  screenKey: _screenKey,
                  onScreen: _screenKey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sidebar(BuildContext context, OrbitTokens tokens) {
    return SizedBox(
      width: 300,
      child: ColoredBox(
        color: tokens.bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, tokens),
            const Divider(height: 1),
            _themePicker(context, tokens),
            const Divider(height: 1),
            Expanded(child: _screenList(context, tokens)),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, OrbitTokens tokens) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Orbit preview',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: tokens.ink,
                fontFamily: tokens.fontDisplay.family,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).push(OrbitThemeGallery.route(widget.library.themes)),
            icon: const Icon(Icons.palette_outlined, size: 18),
            label: const Text('Themes'),
          ),
        ],
      ),
    );
  }

  Widget _themePicker(BuildContext context, OrbitTokens tokens) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in widget.library.themes) _themeChip(context, t, tokens),
        ],
      ),
    );
  }

  Widget _themeChip(BuildContext context, OrbitTokens t, OrbitTokens tokens) {
    final chosen = t.meta.id == _themeId;
    return Semantics(
      button: true,
      selected: chosen,
      label: 'Theme ${t.meta.name}',
      child: InkWell(
        onTap: () => setState(() => _themeId = t.meta.id),
        borderRadius: BorderRadius.circular(tokens.rSm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: chosen ? tokens.accentSoft : tokens.surface,
            borderRadius: BorderRadius.circular(tokens.rSm),
            border: Border.all(color: chosen ? tokens.accent : tokens.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in t.palette) ...[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                ),
                const SizedBox(width: 3),
              ],
              const SizedBox(width: 5),
              Text(
                t.meta.name,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: chosen ? tokens.accentInk : tokens.ink2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _screenList(BuildContext context, OrbitTokens tokens) {
    return ListView(
      children: [
        for (final group in orbitGroups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              group,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: tokens.ink3,
                fontFamily: tokens.mono.family,
              ),
            ),
          ),
          for (final s in orbitScreensInGroup(group))
            _screenRow(context, s, tokens),
        ],
      ],
    );
  }

  Widget _screenRow(BuildContext context, ScreenState s, OrbitTokens tokens) {
    final chosen = s.key == _screenKey;
    return InkWell(
      onTap: () => setState(() => _screenKey = s.key),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        color: chosen ? tokens.accentSoft : null,
        child: Text(
          s.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: chosen ? tokens.accentInk : tokens.ink2,
          ),
        ),
      ),
    );
  }
}

/// The device the prototype draws in, at its own size.
///
/// 412x866 is the phone; the two windows are the prototype's `window-m` and
/// `window-l`. The frame is drawn at true size so a screenshot of it is the
/// same pixel count as the prototype's shot of the same screen - which is the
/// only way the compare tool's score means anything.
class DeviceFrame extends StatelessWidget {
  const DeviceFrame({
    super.key,
    required this.tokens,
    required this.screenKey,
    required this.onScreen,
  });

  final OrbitTokens tokens;
  final String screenKey;

  /// The key currently on the device, drawn as a caption so a shot says which
  /// screen it is without anyone having to remember.
  final String onScreen;

  @override
  Widget build(BuildContext context) {
    final screen = orbitScreen(onScreen);
    final device = switch (screen?.placement) {
      'window-m' => OrbitDevice.windowM,
      'window-l' => OrbitDevice.windowL,
      _ => OrbitDevice.phone,
    };
    final build = orbitPorted[onScreen];
    return ColoredBox(
      color: tokens.bg,
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                onScreen,
                style: tokens.mono.style(size: 11, color: tokens.ink3),
              ),
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: tokens.line),
                ),
                child: build == null
                    // Not ported yet: the frame says so rather than showing a
                    // stand-in that could be mistaken for the screen.
                    ? SizedBox(
                        width: device.width.toDouble(),
                        height: device.height.toDouble(),
                        child: Center(
                          child: Text(
                            'Not ported yet',
                            style: tokens.font.style(
                              size: 13,
                              color: tokens.ink3,
                            ),
                          ),
                        ),
                      )
                    : OrbitDeviceSurface(
                        device: device,
                        tokens: tokens,
                        child: Builder(builder: build),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Makes the chosen theme's tokens reachable without a [Theme] above every
/// widget that only needs to read a value.
///
/// [OrbitTokens.of] is the way a screen reads its tokens; this is for the
/// viewer chrome, which draws the chrome of one theme around another theme's
/// screens.
class OrbitThemeScope extends InheritedWidget {
  const OrbitThemeScope({
    super.key,
    required this.tokens,
    required super.child,
  });

  final OrbitTokens tokens;

  static OrbitTokens of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OrbitThemeScope>()!.tokens;

  @override
  bool updateShouldNotify(OrbitThemeScope oldWidget) =>
      oldWidget.tokens != tokens;
}
