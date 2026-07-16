import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:helix_local_domain/domain/models.dart';
import 'package:helix/providers/app_providers.dart';
import 'package:helix/providers/controllers/messaging_service.dart';
import 'package:helix/infrastructure/scheduler/timer_disconnect_wipe_scheduler.dart';

void main() {
  test('thread provider updates when messaging service mutates', () async {
    final messaging = MessagingService(
      wipeScheduler: TimerDisconnectWipeScheduler(),
    );
    final container = ProviderContainer(
      overrides: [messagingServiceProvider.overrideWithValue(messaging)],
    );
    addTearDown(() async {
      container.dispose();
      await messaging.dispose();
    });

    const threadId = 'abcd1234abcd1234abcd1234abcd1234';
    expect(container.read(threadByIdProvider(threadId)), isNull);

    // Create a thread directly so the provider can observe it.
    messaging.createThread(
      threadId,
      'Alice',
      'abcd',
      'session-a',
      '127.0.0.1',
      42424,
    );
    await Future<void>.delayed(Duration.zero);

    final afterCreate = container.read(threadByIdProvider(threadId));
    expect(afterCreate, isNotNull);
    expect(afterCreate!.messages, isEmpty);

    await messaging.clearThread(threadId);
    await Future<void>.delayed(Duration.zero);

    // Thread is removed by closeThread; clearThread just empties messages.
    final afterClear = container.read(threadByIdProvider(threadId));
    expect(afterClear, isNotNull);
    expect(afterClear!.messages, isEmpty);
  });

  test('one-way inbox updates when a one-way message is received', () async {
    final messaging = MessagingService(
      wipeScheduler: TimerDisconnectWipeScheduler(),
    );
    final container = ProviderContainer(
      overrides: [messagingServiceProvider.overrideWithValue(messaging)],
    );
    addTearDown(() async {
      container.dispose();
      await messaging.dispose();
    });

    const threadId = 'abcd1234abcd1234abcd1234abcd1234';

    messaging.receiveOneWayMessage(
      OneWayMessage(
        messageId: 'm1',
        peerDisplayName: 'Alice',
        peerDeviceSuffix: 'abcd',
        peerSessionId: 'session-a',
        peerStaticKeyFingerprint: threadId,
        peerHost: '127.0.0.1',
        peerPort: 42424,
        text: 'urgent note',
        timestamp: DateTime(2026, 1, 1, 12),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // One-way messages are inbox-only — they do not create chat threads.
    expect(container.read(threadByIdProvider(threadId)), isNull);
    expect(messaging.oneWayInbox.length, 1);
    expect(messaging.oneWayInbox.first.text, 'urgent note');
  });
}
