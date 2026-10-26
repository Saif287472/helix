import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/overlays.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';
import 'package:orbit_ui/src/theme/pattern_painter.dart';

const _plain = OrbitPattern('none', {});

/// The pattern and the colour a chat is drawn on for [wallpaper] in theme
/// [t]. Every colour is one of the theme's own, so a wallpaper follows the
/// theme and never clashes with its bubbles.
(OrbitPattern, Color) wallpaperLook(OrbitTokens t, HelixWallpaper wallpaper) =>
    switch (wallpaper) {
      HelixWallpaper.theme => (t.chatPattern, t.chatBg),
      HelixWallpaper.plain => (_plain, t.chatBg),
      HelixWallpaper.calm => (_plain, t.accentSoft),
      HelixWallpaper.warm => (_plain, t.warningSoft),
      HelixWallpaper.fresh => (_plain, t.successSoft),
      HelixWallpaper.rose => (_plain, t.dangerSoft),
    };

/// A sheet of wallpapers, each shown as a small chat on it. [current] is the
/// one in use; with [allowDefault], a first tile ("Same as all chats") picks
/// null, which a chat uses to follow the default again.
Future<void> showOrbitWallpaperSheet(
  BuildContext context, {
  required HelixWallpaper? current,
  required ValueChanged<HelixWallpaper?> onPick,
  bool allowDefault = false,
}) => showOrbitSheet(
  context,
  title: 'Wallpaper',
  body: Padding(
    padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
    child: Builder(
      builder: (sheet) {
        void pick(HelixWallpaper? choice) {
          Navigator.of(sheet).pop();
          onPick(choice);
        }

        return GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 10,
          childAspectRatio: 0.78,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            if (allowDefault)
              OrbitWallpaperTile(
                wallpaper: HelixWallpaper.theme,
                label: 'Same as all chats',
                on: current == null,
                onTap: () => pick(null),
              ),
            for (final w in HelixWallpaper.values)
              OrbitWallpaperTile(
                wallpaper: w,
                label: w.label,
                on: current == w,
                onTap: () => pick(w),
              ),
          ],
        );
      },
    ),
  ),
);

/// One wallpaper: a small chat on it, the name under it, and an accent ring
/// when it is the one in use.
class OrbitWallpaperTile extends StatelessWidget {
  const OrbitWallpaperTile({
    super.key,
    required this.wallpaper,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final HelixWallpaper wallpaper;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final (pattern, colour) = wallpaperLook(t, wallpaper);
    Widget bubble({required bool out}) => Align(
      alignment: out ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 38,
        height: 14,
        decoration: BoxDecoration(
          color: out ? t.out : t.inBubble,
          border: Border.all(color: out ? t.outLine : t.inLine),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: on,
      label: '$label wallpaper${on ? ', selected' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: on ? t.accent : t.line,
                    width: on ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: OrbitPatternBackground(
                  pattern: pattern,
                  color: colour,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        bubble(out: false),
                        const SizedBox(height: 6),
                        bubble(out: true),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            OrbitText(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.font.style(
                size: OrbitType.caption,
                weight: on ? 600 : 450,
                color: on ? t.accentInk : t.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
