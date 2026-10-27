import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/platform/link_preview_source.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_screen.dart';

import 'support/a3b_fakes.dart' show FakeLocalSettings;
import 'support/chat_harness.dart';

class _FakeSource implements LinkPreviewSource {
  _FakeSource([this.answer]);

  LinkPreviewData? answer;
  Object? failure;
  final List<Uri> asked = [];

  @override
  Future<LinkPreviewData?> fetch(Uri url) async {
    asked.add(url);
    if (failure != null) throw failure!;
    return answer;
  }
}

/// A link in a message gets a card only when the person turned previews on.
void main() {
  Future<void> sendLink(
    WidgetTester tester,
    TestChatGateway gateway, {
    required bool on,
    required _FakeSource source,
    String text = 'read https://example.org/post please',
  }) async {
    final settings = FakeLocalSettings();
    await settings.set(AppSettings.linkPreviews, on);
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    tester.view.physicalSize = const Size(412, 866);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      chatApp(
        gateway,
        ConversationScreen(conversationId: chat),
        settings: settings,
        overrides: [linkPreviewSourceProvider.overrideWithValue(source)],
      ),
    );
    await settle(tester, rounds: 10);
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await settle(tester, rounds: 10);
  }

  chatTest('off: the site is never asked, and the message goes as it is', (
    tester,
    gateway,
  ) async {
    final source = _FakeSource(
      const LinkPreviewData(url: 'x', title: 'Never used'),
    );
    await sendLink(tester, gateway, on: false, source: source);
    expect(source.asked, isEmpty);
    expect(gateway.log.where((l) => l.startsWith('sendText')), hasLength(1));
    expect(gateway.log.where((l) => l.startsWith('linkPreview')), isEmpty);
  });

  chatTest('on: the first link is asked for, and its card goes with the text', (
    tester,
    gateway,
  ) async {
    final source = _FakeSource(
      const LinkPreviewData(
        url: 'ignored',
        title: 'A post',
        description: 'About a thing.',
      ),
    );
    await sendLink(
      tester,
      gateway,
      on: true,
      source: source,
      text: 'read https://example.org/post. and https://other.example/x',
    );
    expect(source.asked.map((u) => u.toString()), ['https://example.org/post']);
    expect(
      gateway.log,
      contains('linkPreview:https://example.org/post:A post'),
      reason: 'the address as written in the message',
    );
  });

  chatTest('on, but no link in the message: nothing is asked', (
    tester,
    gateway,
  ) async {
    final source = _FakeSource();
    await sendLink(tester, gateway, on: true, source: source, text: 'hello');
    expect(source.asked, isEmpty);
    expect(gateway.log, contains(startsWith('sendText')));
  });

  chatTest('a site that gives nothing, or fails, never stops the send', (
    tester,
    gateway,
  ) async {
    final source = _FakeSource()..failure = StateError('boom');
    await sendLink(tester, gateway, on: true, source: source);
    expect(source.asked, hasLength(1));
    expect(gateway.log.where((l) => l.startsWith('sendText')), hasLength(1));
    expect(gateway.log.where((l) => l.startsWith('linkPreview')), isEmpty);
  });
}
