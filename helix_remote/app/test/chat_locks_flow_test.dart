import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/notifications/alert_count.dart';
import 'package:helix_remote/core/notifications/message_alerts.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/core/security/device_auth.dart';
import 'package:helix_remote/core/security/locked_chats.dart';
import 'package:helix_remote/features/chats/application/chat_actions.dart';
import 'package:helix_remote/features/chats/application/chat_list_provider.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_settings_screen.dart';
import 'package:helix_remote/shared/widgets/locked_chat_gate.dart';
import 'package:helix_remote_db/helix_remote_db.dart' show Setting;
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show IncomingNotice;

import 'support/a3b_fakes.dart' show FakeDeviceAuthenticator;
import 'support/chat_harness.dart';

/// Locked chats: the access, the gate, the actions, the bare notification.
void main() {
  group('the access', () {
    late FakeDeviceAuthenticator auth;
    late ProviderContainer container;
    setUp(() {
      auth = FakeDeviceAuthenticator();
      container = ProviderContainer(
        overrides: [deviceAuthenticatorProvider.overrideWithValue(auth)],
      );
      addTearDown(container.dispose);
    });
    LockedChatAccess access() =>
        container.read(lockedChatAccessProvider.notifier);

    test('is closed until the phone\'s unlock is passed', () async {
      expect(container.read(lockedChatAccessProvider), isFalse);
      auth.passes = false;
      expect(await access().unlock(), isFalse);
      expect(container.read(lockedChatAccessProvider), isFalse);
      auth.passes = true;
      expect(await access().unlock(), isTrue);
      expect(container.read(lockedChatAccessProvider), isTrue);
    });

    test(
      'asks only once while it is open, and again after it is shut',
      () async {
        await access().unlock();
        await access().unlock();
        expect(auth.asked, hasLength(1));
        access().lock();
        await access().unlock();
        expect(auth.asked, hasLength(2));
      },
    );

    test('is taken back when the last screen that held it closes', () async {
      await access().unlock();
      access()
        ..hold()
        ..hold();
      access().release();
      expect(container.read(lockedChatAccessProvider), isTrue);
      access().release();
      expect(container.read(lockedChatAccessProvider), isFalse);
    });

    test('a phone with no screen lock cannot lock a chat', () async {
      auth.available = false;
      expect(await whyNotLock(auth), contains('screen lock'));
      auth.available = true;
      expect(await whyNotLock(auth), isNull);
    });
  });

  group('locking from the Chats tab', () {
    test(
      'moves a chat to Locked, and a phone without a lock refuses',
      () async {
        final gateway = await TestChatGateway.create();
        addTearDown(gateway.close);
        final bob = await gateway.chatWith('bob', name: 'Bob');
        await gateway.chatWith('cara', name: 'Cara');
        final auth = FakeDeviceAuthenticator();
        final container = ProviderContainer(
          overrides: [
            chatGatewayProvider.overrideWith((ref) => gateway),
            peopleRowsProvider.overrideWith(
              (ref) => gateway.engine.people.watchAll(),
            ),
            clockProvider.overrideWithValue(() => testNow),
            deviceAuthenticatorProvider.overrideWithValue(auth),
          ],
        );
        addTearDown(container.dispose);
        container
          ..listen(chatListProvider, (_, _) {})
          ..listen(lockedChatListProvider, (_, _) {});
        Future<void> tick() =>
            Future<void>.delayed(const Duration(milliseconds: 100));
        final actions = container.read(chatActionsProvider);

        auth.available = false;
        expect(
          await actions.setLocked([bob], locked: true),
          contains('screen lock'),
        );
        await tick();
        expect(await container.read(lockedChatListProvider.future), isEmpty);

        auth.available = true;
        expect(await actions.setLocked([bob], locked: true), isNull);
        await tick();
        expect(
          (await container.read(chatListProvider.future)).map((c) => c.id),
          isNot(contains(bob)),
        );
        expect(
          (await container.read(
            lockedChatListProvider.future,
          )).map((c) => c.id),
          [bob],
        );

        // Taking the lock off needs no screen lock, so a phone that lost its
        // lock can still get its chats back.
        auth.available = false;
        expect(await actions.setLocked([bob], locked: false), isNull);
        await tick();
        expect(await container.read(lockedChatListProvider.future), isEmpty);
      },
    );
  });

  group('the gate', () {
    Future<void> open(
      WidgetTester tester,
      TestChatGateway gateway,
      String chat,
      FakeDeviceAuthenticator auth,
    ) async {
      await tester.pumpWidget(
        chatApp(
          gateway,
          LockedChatGate(
            conversationId: chat,
            child: const Text('the chat itself'),
          ),
          overrides: [deviceAuthenticatorProvider.overrideWithValue(auth)],
        ),
      );
      await settle(tester, rounds: 10);
    }

    chatTest('shows an ordinary chat at once', (tester, gateway) async {
      final chat = (await tester.runAsync(
        () => gateway.chatWith('bob', name: 'Bob'),
      ))!;
      final auth = FakeDeviceAuthenticator();
      await open(tester, gateway, chat, auth);
      expect(find.text('the chat itself'), findsOneWidget);
      expect(auth.asked, isEmpty);
    });

    chatTest('covers a locked chat, asks, and opens it when passed', (
      tester,
      gateway,
    ) async {
      final chat = (await tester.runAsync(
        () => gateway.chatWith('bob', name: 'Bob'),
      ))!;
      await tester.runAsync(() => gateway.setLocked(chat, locked: true));
      final auth = FakeDeviceAuthenticator()..passes = false;
      await open(tester, gateway, chat, auth);
      expect(find.text('the chat itself'), findsNothing);
      expect(find.text('This chat is locked'), findsOneWidget);
      expect(auth.asked, hasLength(1), reason: 'it asks without being tapped');

      auth.passes = true;
      await tester.tap(find.text('Unlock'));
      await settle(tester, rounds: 5);
      expect(find.text('the chat itself'), findsOneWidget);
    });

    chatTest('covers it again when the access is taken back', (
      tester,
      gateway,
    ) async {
      final chat = (await tester.runAsync(
        () => gateway.chatWith('bob', name: 'Bob'),
      ))!;
      await tester.runAsync(() => gateway.setLocked(chat, locked: true));
      final auth = FakeDeviceAuthenticator();
      await open(tester, gateway, chat, auth);
      expect(find.text('the chat itself'), findsOneWidget);

      final scope = ProviderScope.containerOf(
        tester.element(find.text('the chat itself')),
      );
      scope.read(lockedChatAccessProvider.notifier).lock();
      await settle(tester, rounds: 5);
      // It asked on the way in, and asks again on the way back.
      expect(auth.asked, hasLength(2));
    });
  });

  group('the notification of a locked chat', () {
    IncomingNotice notice({required bool locked}) => IncomingNotice(
      conversationId: 'direct:alice',
      messageRowid: 1,
      messageId: 'm1',
      sender: 'alice',
      kind: 'text',
      preview: 'the secret plan',
      muted: false,
      sentAt: DateTime.utc(2026, 10, 9),
      locked: locked,
    );

    Future<({String? sender, String? preview, String? label})> shown(
      IncomingNotice latest,
    ) async {
      String? gotSender;
      String? gotPreview;
      String? gotLabel;
      await MessageAlerts.show(
        (Setting<bool> setting) async => true,
        account: 'a',
        count: 1,
        latest: latest,
        senderName: 'Alice',
        accountLabel: 'Work',
        counts: const AlertCountStore(),
        post:
            ({
              required account,
              required count,
              sound = true,
              vibrate = true,
              sender,
              preview,
              accountLabel,
            }) async {
              gotSender = sender;
              gotPreview = preview;
              gotLabel = accountLabel;
            },
      );
      return (sender: gotSender, preview: gotPreview, label: gotLabel);
    }

    test('names no one and shows no text, even with previews on', () async {
      final out = await shown(notice(locked: true));
      expect(out.sender, isNull);
      expect(out.preview, isNull);
      expect(out.label, isNull);
    });

    test('an ordinary chat still follows the previews setting', () async {
      final out = await shown(notice(locked: false));
      expect(out.sender, 'Alice');
      expect(out.preview, 'the secret plan');
    });
  });

  group('a chat\'s settings', () {
    Future<void> openSettings(
      WidgetTester tester,
      TestChatGateway gateway,
      String chat,
      FakeDeviceAuthenticator auth,
    ) async {
      tester.view.physicalSize = const Size(412, 866);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        chatApp(
          gateway,
          ConversationSettingsScreen(conversationId: chat),
          overrides: [deviceAuthenticatorProvider.overrideWithValue(auth)],
        ),
      );
      await settle(tester, rounds: 10);
      await tester.ensureVisible(find.text('Lock chat'));
    }

    chatTest('the switch locks the chat', (tester, gateway) async {
      final chat = (await tester.runAsync(
        () => gateway.chatWith('bob', name: 'Bob'),
      ))!;
      await openSettings(tester, gateway, chat, FakeDeviceAuthenticator());
      await tester.tap(find.text('Lock chat'));
      await settle(tester, rounds: 5);
      final row = (await tester.runAsync(() => gateway.chat(chat)))!;
      expect(row.lockedAt, isNotNull);
    });

    chatTest('a phone without a screen lock says so and locks nothing', (
      tester,
      gateway,
    ) async {
      final chat = (await tester.runAsync(
        () => gateway.chatWith('bob', name: 'Bob'),
      ))!;
      final auth = FakeDeviceAuthenticator()..available = false;
      await openSettings(tester, gateway, chat, auth);
      await tester.tap(find.text('Lock chat'));
      await settle(tester, rounds: 5);
      expect(find.textContaining('Set a screen lock'), findsOneWidget);
      final row = (await tester.runAsync(() => gateway.chat(chat)))!;
      expect(row.lockedAt, isNull);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
