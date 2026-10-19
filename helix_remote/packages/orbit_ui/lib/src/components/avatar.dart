import 'package:flutter/material.dart';

import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// `.av` (`css/components.css`; `UI.avatar` in `js/ui.js`): a rounded square
/// whose corner is `--avatar-r` of its size, filled from the 8-colour palette
/// (`--av-N-bg`, `--av-N-ink`).
///
/// It shows the photo, or a group's filled users-three icon at 46% of the
/// size, or the initials at 36% and weight 620.
/// - [check]: `.av-check`, the selected state, the accent with a bold tick.
/// - [online]: `.av-online`, a 13px `--success` dot with a 2.5px `--surface`
///   ring at the bottom right. The prototype draws it only when the call asks
///   for it *and* the person is online, so pass the person's state.
class OrbitAvatar extends StatelessWidget {
  const OrbitAvatar({
    super.key,
    required this.avatar,
    this.size = 48,
    this.check = false,
    this.online = false,
    this.round = false,
    this.cornerPct,
  });

  final HelixAvatarModel avatar;
  final double size;
  final bool check;
  final bool online;

  /// A circle instead of the theme's corner (`.me-ring .av`).
  final bool round;

  /// The corner as a share of the size, in place of the theme's
  /// `--avatar-r` (the call screen's 34%).
  final double? cornerPct;

  static (Color, Color) palette(OrbitTokens t, int index) =>
      switch (index % HelixAvatarModel.paletteSize) {
        0 => (t.av0Bg, t.av0Ink),
        1 => (t.av1Bg, t.av1Ink),
        2 => (t.av2Bg, t.av2Ink),
        3 => (t.av3Bg, t.av3Ink),
        4 => (t.av4Bg, t.av4Ink),
        5 => (t.av5Bg, t.av5Ink),
        6 => (t.av6Bg, t.av6Ink),
        _ => (t.av7Bg, t.av7Ink),
      };

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final (bg, ink) = palette(t, avatar.colorIndex);
    final radius = BorderRadius.circular(
      round ? size / 2 : size * (cornerPct ?? t.avatarR) / 100,
    );
    final image = avatar.image;
    final Widget face = image != null
        ? const SizedBox.shrink()
        : avatar.isGroup
        ? OrbitIcon(
            OrbitIcons.usersThree,
            weight: OrbitIconWeight.fill,
            size: size * 0.46,
            color: ink,
          )
        : Text(
            avatar.initials,
            maxLines: 1,
            softWrap: false,
            style: t.font.style(
              size: size * 0.36,
              weight: 620,
              color: ink,
              letterSpacingEm: -0.01,
            ),
          );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: radius,
                  image: image == null
                      ? null
                      : DecorationImage(image: image, fit: BoxFit.cover),
                ),
                child: Center(child: face),
              ),
            ),
            if (check)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.accent,
                    borderRadius: radius,
                  ),
                  child: Center(
                    child: OrbitIcon(
                      OrbitIcons.check,
                      weight: OrbitIconWeight.bold,
                      size: size * 0.46,
                      color: t.onAccent,
                    ),
                  ),
                ),
              ),
            if (online)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: t.success,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: t.surface, spreadRadius: 2.5)],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
