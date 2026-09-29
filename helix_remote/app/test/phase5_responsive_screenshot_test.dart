import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Golden baselines are platform-specific rasterisations; see
/// `packages/helix_remote_ui/test/component_gallery_golden_test.dart` for the
/// full reasoning. Linux is the reference platform, matching CI's
/// `verify-linux` job and the pinned Flutter version.
///
/// Regenerate with, on Linux:
///   flutter test test/phase5_responsive_screenshot_test.dart --update-goldens
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> setSurface(WidgetTester tester, Size size) async {
    binding.platformDispatcher.views.first.physicalSize = size;
    binding.platformDispatcher.views.first.devicePixelRatio = 1;
    addTearDown(() {
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const MaterialApp(home: _ConversationSnapshot()));
    await tester.pump();
  }

  testWidgets('P5 visual snapshot - phone conversation list', (tester) async {
    await setSurface(tester, const Size(390, 844));

    await expectLater(
      find.byType(_ConversationSnapshot),
      matchesGoldenFile('goldens/phase5_phone.png'),
    );
  }, skip: !Platform.isLinux);

  testWidgets('P5 visual snapshot - tablet master detail', (tester) async {
    await setSurface(tester, const Size(900, 844));

    await expectLater(
      find.byType(_ConversationSnapshot),
      matchesGoldenFile('goldens/phase5_tablet.png'),
    );
  }, skip: !Platform.isLinux);

  testWidgets('P5 visual snapshot - desktop master detail', (tester) async {
    await setSurface(tester, const Size(1280, 844));

    await expectLater(
      find.byType(_ConversationSnapshot),
      matchesGoldenFile('goldens/phase5_desktop.png'),
    );
  }, skip: !Platform.isLinux);
}

class _ConversationSnapshot extends StatelessWidget {
  const _ConversationSnapshot();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Conversations')),
    body: LayoutBuilder(
      builder: (context, constraints) {
        final showDetail = constraints.maxWidth >= HelixBreakpoints.compact;
        final list = const _ConversationList();
        if (!showDetail) return list;
        return Row(
          children: [
            SizedBox(width: 360, child: list),
            const VerticalDivider(width: 1),
            const Expanded(child: _ConversationDetail()),
          ],
        );
      },
    ),
  );
}

class _ConversationList extends StatelessWidget {
  const _ConversationList();

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: HelixInsets.all(HelixSpace.sm),
    itemCount: 4,
    separatorBuilder: (_, _) => const SizedBox(height: HelixSpace.xs),
    itemBuilder: (context, index) {
      const names = ['Ada Lovelace', 'Design team', 'Grace Hopper', 'Support'];
      return Card(
        child: ListTile(
          leading: Hero(
            tag: 'snapshot-avatar-$index',
            child: CircleAvatar(child: Text(names[index][0])),
          ),
          title: Text(names[index]),
          subtitle: const Text('Latest encrypted message'),
          trailing: const HelixStatusBadge(
            label: 'Secure',
            color: HelixColorTokens.success,
          ),
        ),
      );
    },
  );
}

class _ConversationDetail extends StatelessWidget {
  const _ConversationDetail();

  @override
  Widget build(BuildContext context) => Padding(
    padding: HelixInsets.all(HelixSpace.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ada Lovelace', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: HelixSpace.xs),
        const HelixStatusBadge(
          label: 'End-to-end encrypted',
          color: HelixColorTokens.success,
        ),
        const Spacer(),
        Align(
          alignment: Alignment.centerRight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: HelixRadius.card,
            ),
            child: Padding(
              padding: HelixInsets.all(HelixSpace.sm),
              child: const Text('Hello from the desktop conversation pane.'),
            ),
          ),
        ),
      ],
    ),
  );
}
