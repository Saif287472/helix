import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import 'support/harness.dart';

/// Goldens for the v2 chat components, in the same setup as
/// `component_gallery_golden_test.dart`: Linux is the reference platform
/// (matching CI), so these skip elsewhere.
///
/// Two further skips keep the suite honest rather than red:
///  * A missing baseline skips instead of failing, so adding a new golden
///    test never breaks a run that cannot generate it. Generate it on Linux
///    (see below) and commit the PNG.
///  * Set `HELIX_GOLDENS_ANY_PLATFORM=1` to run on another OS when you only
///    want to look at the output; never commit baselines made that way.
///
/// Regenerate on Linux, from `helix_remote/packages/helix_remote_ui`:
///   flutter test test/chat_components_golden_test.dart --update-goldens
/// then review every changed PNG before committing.
bool get _canRunGoldens =>
    Platform.isLinux ||
    Platform.environment['HELIX_GOLDENS_ANY_PLATFORM'] == '1';

/// Why [name] cannot run here, or null when it can.
String? _skipReason(String name) {
  if (!_canRunGoldens) return 'goldens are only compared on Linux (CI)';
  final baseline = File('test/goldens/$name.png');
  if (!baseline.existsSync() && !autoUpdateGoldenFiles) {
    return 'baseline test/goldens/$name.png not generated yet; run '
        'flutter test --update-goldens on Linux';
  }
  return null;
}

void main() {
  void golden(String name, Widget child, {double height = 3000}) {
    testWidgets('chat component golden: $name', (tester) async {
      final key = GlobalKey();
      await pumpHelix(
        tester,
        SingleChildScrollView(
          child: Align(
            alignment: Alignment.topCenter,
            child: RepaintBoundary(
              key: key,
              child: Material(
                color: HelixThemes.light().colorScheme.surface,
                child: child,
              ),
            ),
          ),
        ),
        height: height,
      );
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/$name.png'),
      );
    }, skip: _skipReason(name) != null);
  }

  golden('chat_list', const HelixGalleryChatList());
  golden('conversation', const HelixGalleryConversation());
  golden('composer', const HelixGalleryComposer());
  golden('general', const HelixGalleryGeneral());
}
