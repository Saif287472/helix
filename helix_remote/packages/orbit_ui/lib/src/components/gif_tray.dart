import 'dart:async';

import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/overlays.dart';
import 'package:orbit_ui/src/components/spinner.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// The GIF tray: the GIFs already on this phone (sent or received), the newest
/// first, three across. Touching one sends it. Nothing here asks a website for
/// anything; with none yet, it says where they come from.
Future<void> showOrbitGifSheet(
  BuildContext context, {
  required FutureOr<List<ChatGifItem>> Function() load,
  required ValueChanged<String> onPick,
}) => showOrbitSheet(
  context,
  title: 'GIFs',
  heightFactor: 0.7,
  body: Builder(
    builder: (sheet) {
      final t = OrbitTokens.of(sheet);
      return FutureBuilder<List<ChatGifItem>>(
        future: Future.sync(load),
        builder: (context, snap) {
          final gifs = snap.data;
          if (snap.hasError) {
            return _note(t, 'GIFs could not be loaded.');
          }
          if (gifs == null) {
            return const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: OrbitSpinner(size: 28)),
            );
          }
          if (gifs.isEmpty) {
            return _note(
              t,
              'No GIFs on this phone yet. GIFs you send or receive in your '
              'chats show up here.',
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              shrinkWrap: true,
              children: [
                for (final gif in gifs)
                  Semantics(
                    button: true,
                    label: 'Send this GIF',
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        Navigator.of(sheet).pop();
                        onPick(gif.id);
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image(
                          image: gif.image,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => ColoredBox(color: t.field),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
    },
  ),
);

Widget _note(OrbitTokens t, String text) => Padding(
  padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
  child: OrbitText(
    text,
    style: t.font.style(size: OrbitType.small, color: t.ink3, height: 1.5),
  ),
);
