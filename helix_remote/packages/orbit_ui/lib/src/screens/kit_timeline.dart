import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/composer.dart';
import 'package:orbit_ui/src/components/timeline.dart';
import 'package:orbit_ui/src/fakes/orbit_fakes.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/screens/kit_sheet.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';
import 'package:orbit_ui/src/theme/pattern_painter.dart';

/// `kit-timeline` (`prototype/js/screens/states.js`): the prototype's four
/// sample conversations, the start of an empty chat, and the composer in
/// each of its states.
class KitTimelineScreen extends StatelessWidget {
  const KitTimelineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final c = OrbitFakes.conversations;
    Widget timeline(List<HelixTimelineItem> items, {bool group = false}) =>
        OrbitKitFrame(
          padding: EdgeInsets.zero,
          background: t.bg,
          child: OrbitPatternBackground(
            pattern: t.chatPattern,
            color: t.chatBg,
            child: OrbitTimeline(items: items, group: group, onRetry: (_) {}),
          ),
        );
    Widget composer(OrbitComposer child, {double top = 0}) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: OrbitKitFrame(
        padding: EdgeInsets.only(top: top),
        background: t.bg,
        child: child,
      ),
    );
    const nadia = 'Nadia Rahman';
    return OrbitKitPage(
      title: 'Timeline',
      intro:
          'Messages of every kind, the separators and notices between them, '
          'and the composer in each of its states.',
      children: [
        const OrbitKitLabel('A direct chat'),
        timeline([...c['direct:nadia']!, const HelixTypingItem()]),
        const OrbitKitLabel('A group'),
        timeline(c['group:family']!, group: true),
        const OrbitKitLabel('Every kind of message'),
        timeline(c['direct:arif']!),
        const OrbitKitLabel('Not sent and not downloaded'),
        timeline(c['direct:rafiq']!),
        const OrbitKitLabel('A new chat'),
        timeline(const [HelixEncryptionNoticeItem()]),
        const OrbitKitLabel('Composer'),
        composer(const OrbitComposer()),
        composer(const OrbitComposer(initialText: 'See you there')),
        composer(
          const OrbitComposer(
            banner: HelixComposerBannerModel(
              kind: HelixComposerBannerKind.reply,
              title: 'Replying to $nadia',
              text: 'Good morning ☀️ We got back last night',
            ),
          ),
        ),
        composer(
          const OrbitComposer(
            initialText: 'Here it is. The colour pages are 14 to 22',
            banner: HelixComposerBannerModel(
              kind: HelixComposerBannerKind.edit,
              title: 'Edit message',
              text: 'Here it is. The colour pages are 14 to 22',
            ),
          ),
        ),
        composer(
          OrbitComposer(
            recording: OrbitRecording.locked,
            recordingWave: OrbitFakes.wave.take(24).toList().reversed.toList(),
          ),
        ),
        composer(const OrbitComposer(recording: OrbitRecording.hold), top: 84),
        composer(
          const OrbitComposer(
            disabled:
                'You blocked this contact. Open chat settings to unblock.',
            disabledIcon: true,
          ),
        ),
        composer(
          const OrbitComposer(
            disabled: 'You can no longer send messages to this group.',
          ),
        ),
      ],
    );
  }
}
