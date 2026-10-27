import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/platform/location_source.dart';
import 'package:helix_remote/features/conversation/application/message_mapper.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_screen.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:orbit_ui/orbit_ui.dart';

import 'support/chat_harness.dart';
import 'support/location_fakes.dart';

MessageRow _row(
  String kind,
  Map<String, Object?> payload, {
  bool outgoing = false,
}) {
  final at = DateTime.utc(2026, 10, 3, 9);
  return MessageRow(
    localRowid: 1,
    messageId: 'm1',
    conversationId: 'direct:bob',
    sender: outgoing ? 'me' : 'bob',
    outgoing: outgoing,
    sortKey: SortKey.of(at, 'm1'),
    sentAt: at,
    receivedAt: at,
    kind: kind,
    payload: jsonEncode(payload),
    forwarded: false,
    mentionsMe: false,
    status: MessageStatus.received,
  );
}

void main() {
  final now = DateTime(2026, 10, 3, 14, 30);
  int ms(DateTime t) => t.toUtc().millisecondsSinceEpoch;

  group('what a location row draws', () {
    test('a place shows its coordinates and can be opened', () {
      final c =
          contentOf(
                _row('location', {
                  'lat_e7': 236810000,
                  'lng_e7': 903560000,
                  'accuracy_m': 5,
                }),
                now: now,
              )
              as HelixLocationContent;
      expect(c.address, '23.6810, 90.3560');
      expect(c.openable, isTrue);
      expect(c.live, isNull);
    });

    test('a running share says until when, and is yours to stop', () {
      final c =
          contentOf(
                _row('live_location', {
                  'state': 'update',
                  'lat_e7': 236810000,
                  'lng_e7': 903560000,
                  'expires_at': ms(now.add(const Duration(minutes: 15))),
                }, outgoing: true),
                now: now,
              )
              as HelixLocationContent;
      expect(c.live!.active, isTrue);
      expect(c.live!.statusLabel, 'Live until 14:45');
      expect(c.live!.mine, isTrue);
      expect(c.openable, isTrue);
    });

    test('a share past its time, or stopped, shows no place', () {
      for (final payload in [
        {
          'state': 'update',
          'lat_e7': 236810000,
          'lng_e7': 903560000,
          'expires_at': ms(now.subtract(const Duration(minutes: 1))),
        },
        {
          'state': 'stop',
          'ended': true,
          'lat_e7': 0,
          'lng_e7': 0,
          'expires_at': ms(now.add(const Duration(hours: 1))),
        },
      ]) {
        final c =
            contentOf(_row('live_location', payload), now: now)
                as HelixLocationContent;
        expect(c.live!.active, isFalse);
        expect(c.live!.statusLabel, 'Live location ended');
        expect(c.openable, isFalse);
      }
    });
  });

  group('sharing from the attach sheet', () {
    chatTest('a live share starts, shows, and stops from its bubble', (
      tester,
      gateway,
    ) async {
      final phone = FakeLocationSource();
      final chat = (await tester.runAsync(
        () => gateway.chatWith('bob', name: 'Bob'),
      ))!;
      await tester.pumpWidget(
        chatApp(
          gateway,
          ConversationScreen(conversationId: chat),
          overrides: [locationSourceProvider.overrideWithValue(phone)],
        ),
      );
      await settle(tester, rounds: 10);

      await tester.tap(find.byTooltip('Attach'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Location'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share live for 15 minutes'));
      await settle(tester, rounds: 10);

      expect(gateway.log, contains('startLive:$chat:15m'));
      expect(find.text('Live until 14:45'), findsOneWidget);

      await tester.tap(find.text('Stop sharing'));
      await settle(tester, rounds: 10);
      expect(gateway.log.where((l) => l.startsWith('stopLive')), hasLength(1));
      expect(find.text('Live location ended'), findsOneWidget);
      expect(find.text('Stop sharing'), findsNothing);
    });

    chatTest('with location refused, the sheet says why and sends nothing', (
      tester,
      gateway,
    ) async {
      final phone = FakeLocationSource()..granted = LocationAccess.denied;
      final chat = (await tester.runAsync(
        () => gateway.chatWith('bob', name: 'Bob'),
      ))!;
      await tester.pumpWidget(
        chatApp(
          gateway,
          ConversationScreen(conversationId: chat),
          overrides: [locationSourceProvider.overrideWithValue(phone)],
        ),
      );
      await settle(tester, rounds: 10);

      await tester.tap(find.byTooltip('Attach'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Location'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send current location'));
      await settle(tester, rounds: 10);

      expect(find.textContaining('Allow location access'), findsOneWidget);
      expect(gateway.log.where((l) => l.startsWith('send')), isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
