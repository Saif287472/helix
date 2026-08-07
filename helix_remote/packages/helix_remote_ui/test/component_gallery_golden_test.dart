import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Golden files record how a specific renderer rasterised a specific font.
/// Text anti-aliasing differs between platforms, so a baseline approved on one
/// fails on another with a sub-2% diff that reads as a real regression and is
/// not one — which is exactly what happened here: the committed baselines were
/// approved off-Linux and failed every Linux run, including CI's own
/// `verify-linux` job.
///
/// The reference platform is Linux, matching the `ubuntu-latest` runner and
/// the pinned Flutter version in `.github/workflows/ci.yml`. Elsewhere these
/// skip: a golden that cannot be trusted off its reference platform must not
/// be allowed to fail there either, or the suite trains people to ignore it.
///
/// Regenerate with, on Linux:
///   flutter test --update-goldens
const goldensReferencePlatform = 'linux';

void main() {
  testWidgets(
    'P8 component gallery matches its approved light-theme baseline',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: HelixThemes.light(),
          home: Scaffold(
            body: ListView(
              padding: HelixInsets.all(HelixSpace.md),
              children: const [
                HelixStatusBadge(label: 'End-to-end encrypted'),
                SizedBox(height: HelixSpace.md),
                HelixSkeleton(height: 24),
                SizedBox(height: HelixSpace.md),
                HelixErrorState(message: 'The server is unavailable.'),
                SizedBox(height: HelixSpace.md),
                HelixEmptyState(
                  icon: Icons.forum_outlined,
                  title: 'No conversations yet',
                  message: 'Start a secure conversation with a contact.',
                ),
              ],
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/component_gallery_light.png'),
      );
    },
    skip: !Platform.isLinux,
  );
}
