import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/avatar.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// The night colours (`css/tokens.css`, "Night: camera and media viewer
/// only"). They sit in `:root`, outside every theme, so they are the same in
/// all of them; the media viewer's own `#000` and greys are from
/// `css/pages.css` and `js/screens/chat_pages.js`.
abstract final class OrbitNight {
  static const night = Color(0xFF090C15);
  static const night2 = Color(0xFF111626);
  static const night3 = Color(0xFF1B2236);
  static const line = Color(0xFF263049);
  static const text = Color(0xFFEAEEF8);
  static const muted = Color(0xFF9099B2);

  /// `--call-accept` and `--call-end`: Answer and End on a call.
  static const callAccept = Color(0xFF18A867);
  static const callEnd = Color(0xFFE5484D);

  /// The viewer's sentences ("This file is not on your device yet.").
  static const viewerText = Color(0xFFC9D0DF);

  /// `.viewer-page .ab-sub`.
  static const viewerSub = Color(0xFFAEB6C8);

  /// `.mv-cap`.
  static const caption = Color(0xFFE8ECF6);

  /// The "Open video" button on a video that cannot play.
  static const buttonBg = Color(0xFF1B2236);
  static const buttonLine = Color(0xFF2B3550);
}

/// `.hero` (`css/pages.css`): a 72px picture, the name in the display face
/// at 24px with the seal, and the mono sub line, centred, 18px 24px 4px in.
class OrbitProfileHero extends StatelessWidget {
  const OrbitProfileHero({
    super.key,
    required this.avatar,
    required this.name,
    this.sub = '',
    this.verified = false,
    this.about = '',
    this.size = 72,
    this.extra = const [],
  });

  final HelixAvatarModel avatar;
  final String name;
  final String sub;
  final bool verified;
  final String about;

  /// The picture's size (112 on Contact info).
  final double size;

  /// Lines under the sub line, 8px apart ("Blocked").
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 4),
      child: Column(
        children: [
          OrbitAvatar(avatar: avatar, size: size),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: OrbitText(
                  name,
                  textAlign: TextAlign.center,
                  style: t.display(size: 24),
                ),
              ),
              if (verified) ...[
                const SizedBox(width: 6),
                OrbitIcon(
                  OrbitIcons.sealCheck,
                  weight: OrbitIconWeight.fill,
                  size: 20,
                  color: t.accent,
                ),
              ],
            ],
          ),
          // The prototype always draws `.h-sub`, so even an empty one keeps
          // its 4px gap.
          const SizedBox(height: 4),
          if (sub.isNotEmpty) ...[
            OrbitText(
              sub,
              textAlign: TextAlign.center,
              style: t.mono.style(size: 12.5, color: t.ink3),
            ),
          ],
          for (final e in extra) ...[const SizedBox(height: 8), e],
          if (about.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: OrbitText(
                about,
                textAlign: TextAlign.center,
                style: t.font.style(
                  size: OrbitType.small,
                  color: t.ink2,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `.tabs`: equal 48px tabs on `--surface` over a `--line-2` rule; the on tab
/// is `--ink` with a 3px `--accent` bar across its middle half.
class OrbitTabs extends StatelessWidget {
  const OrbitTabs({
    super.key,
    required this.labels,
    required this.index,
    this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(bottom: BorderSide(color: t.line2)),
      ),
      child: Row(
        children: [
          for (final (i, l) in labels.indexed)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == index,
                child: InkWell(
                  onTap: () => onChanged?.call(i),
                  hoverColor: t.hover,
                  splashFactory: NoSplash.splashFactory,
                  child: SizedBox(
                    height: 48,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Center(
                          child: Text(
                            l,
                            style: t.font.style(
                              size: 14,
                              weight: 580,
                              color: i == index ? t.ink : t.ink3,
                            ),
                          ),
                        ),
                        if (i == index)
                          Positioned.fill(
                            bottom: -1,
                            top: null,
                            child: FractionallySizedBox(
                              widthFactor: 0.52,
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  color: t.accent,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// `.pick`: the 24px tick a picker row ends with: a 1.5px `--control-line`
/// ring, or `--accent` with a bold check when picked. [corner] is 12 for
/// the circle; the forward list draws it with 7.
class OrbitPick extends StatelessWidget {
  const OrbitPick({super.key, required this.on, this.corner = 12});

  final bool on;
  final double corner;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: on ? t.accent : null,
        border: Border.all(color: on ? t.accent : t.controlLine, width: 1.5),
        borderRadius: BorderRadius.circular(corner),
      ),
      child: on
          ? Center(
              child: OrbitIcon(
                OrbitIcons.check,
                weight: OrbitIconWeight.bold,
                size: 14,
                color: t.onAccent,
              ),
            )
          : null,
    );
  }
}

/// `.bottom-bar`: the action strip under a page, on `--surface` over a
/// `--line-2` rule, 10px 16px 30px in, its parts 10px apart.
class OrbitBottomBar extends StatelessWidget {
  const OrbitBottomBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        OrbitSpace.gutter,
        10,
        OrbitSpace.gutter,
        30,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.line2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            c,
          ],
        ],
      ),
    );
  }
}
