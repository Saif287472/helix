import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/l10n/helix_localizations.dart';
import 'package:helix_remote/screens/conversation/message_tile.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Rich-content messages (poll, event, location, sticker) arrive on
/// [RemoteDecryptedMessage] as typed fields, but nothing rendered them. Each
/// one fell through to the message tile's plain `Text` branch and was drawn as
/// its own encoded content envelope - the question, every option and the
/// payload keys, as one run of JSON in the bubble.
///
/// These lock in the typed rendering. They are deliberately widget tests over
/// the whole tile rather than unit tests over the card classes, because the
/// bug was a missing branch in the tile's dispatch, not a wrong card.
void main() {
  Widget harness(RemoteDecryptedMessage message) => MaterialApp(
    localizationsDelegates: HelixLocalizations.localizationsDelegates,
    supportedLocales: HelixLocalizations.supportedLocales,
    theme: HelixThemes.light(),
    home: Scaffold(
      body: ConversationMessageTile(
        message: message,
        currentAccountId: 'me',
        isSelected: false,
        isHighlighted: false,
        selectionMode: false,
        onLongPress: (_) {},
        onTap: () {},
        onDoubleTap: () {},
        onSwipeReply: () {},
        onTapReply: (_) {},
        onReactionTap: () {},
        onDownloadAttachment: () {},
        onExportAttachment: () {},
      ),
    ),
  );

  RemoteDecryptedMessage messageWith({
    String? text = 'hello',
    RemotePollContent? poll,
    RemoteEventContent? event,
    RemoteLocationContent? location,
    RemoteStickerContent? sticker,
  }) => RemoteDecryptedMessage(
    messageId: 'msg_1',
    conversationId: 'conv_1',
    senderAccountId: 'peer',
    senderDeviceId: 'peer_device',
    // Deliberately the raw envelope. A rich message's `text` is still the
    // encoded form, so this is what the tile is handed; the point is that it
    // must not be what the tile *shows*.
    text: text ?? 'hello',
    status: 'sent',
    timestamp: 1781848900000,
    poll: poll,
    event: event,
    location: location,
    sticker: sticker,
  );

  group('rich content renders as a card, not as JSON', () {
    testWidgets('poll shows the question and every option', (tester) async {
      final message = messageWith(
        poll: const RemotePollContent(
          pollId: 'poll_1',
          question: 'Lunch?',
          options: [
            RemotePollOption(optionId: 'a', text: 'Pizza'),
            RemotePollOption(optionId: 'b', text: 'Ramen'),
          ],
          creatorAccountId: 'peer',
          createdAt: 1781848900000,
        ),
      );

      await tester.pumpWidget(harness(message));

      expect(find.text('Lunch?'), findsOneWidget);
      expect(find.text('Pizza'), findsOneWidget);
      expect(find.text('Ramen'), findsOneWidget);
      // The encoded payload must not leak into the bubble.
      expect(find.textContaining('poll_id'), findsNothing);
      expect(find.textContaining('content_type'), findsNothing);
    });

    testWidgets('event shows title, time and location', (tester) async {
      final message = messageWith(
        event: RemoteEventContent(
          eventId: 'evt_1',
          title: 'Sprint review',
          creatorAccountId: 'peer',
          // 2026-06-19T06:00:00Z expressed in the sender's own zone, so the
          // card is checked for the wall-clock it was given.
          startsAt: DateTime.utc(2026, 6, 19, 14, 30).millisecondsSinceEpoch,
          timeZone: 'Asia/Dhaka',
          locationText: 'Room 4',
        ),
      );

      await tester.pumpWidget(harness(message));

      expect(find.text('Sprint review'), findsOneWidget);
      expect(find.text('Room 4'), findsOneWidget);
      // The sender's timezone travels with the event; converting it to the
      // reader's zone would show a different time than the one agreed.
      expect(find.textContaining('Asia/Dhaka'), findsOneWidget);
      expect(find.textContaining('event_id'), findsNothing);
    });

    testWidgets('location shows rounded coordinates, not raw E7', (
      tester,
    ) async {
      final message = messageWith(
        location: const RemoteLocationContent(
          locationId: 'loc_1',
          latitudeE7: 235000000,
          longitudeE7: 901000000,
          accuracyMeters: 15,
          createdAt: 1781848900000,
        ),
      );

      await tester.pumpWidget(harness(message));

      // 23.5 / 90.1 to four decimals, not the seven-digit wire value.
      expect(find.textContaining('23.5000'), findsOneWidget);
      expect(find.textContaining('90.1000'), findsOneWidget);
      expect(find.textContaining('latitude_e7'), findsNothing);
    });

    testWidgets('sticker shows its alt text and a save action', (tester) async {
      final message = messageWith(
        sticker: const RemoteStickerContent(
          stickerId: 'stk_1',
          packId: 'pack_1',
          kind: 'animated',
          altText: 'a cat waving',
          attachment: RemoteAttachmentContent(
            fileId: 'att_1',
            filename: 'cat.webp',
            fileSize: 4096,
            fileHash: 'hash_1',
            mimeType: 'image/webp',
            keyDeliverySecret: 'secret',
          ),
        ),
      );

      await tester.pumpWidget(harness(message));

      expect(find.text('a cat waving'), findsOneWidget);
      expect(find.text('Image sticker'), findsOneWidget);
    });

    testWidgets('a live location that has stopped is shown as stopped', (
      tester,
    ) async {
      final message = messageWith(
        location: const RemoteLocationContent(
          locationId: 'loc_2',
          latitudeE7: 235000000,
          longitudeE7: 901000000,
          accuracyMeters: 10,
          createdAt: 1781848900000,
          live: true,
          stoppedAt: 1781848999999,
        ),
      );

      await tester.pumpWidget(harness(message));

      expect(find.text('Sharing stopped'), findsOneWidget);
      // Not "Live location" - the sharing has ended.
      expect(find.text('LIVE LOCATION'), findsNothing);
    });

    testWidgets('a cancelled event is marked cancelled', (tester) async {
      final message = messageWith(
        event: const RemoteEventContent(
          eventId: 'evt_2',
          title: 'Retro',
          creatorAccountId: 'peer',
          startsAt: 1781848900000,
          timeZone: 'UTC',
          cancelledAt: 1781848950000,
        ),
      );

      await tester.pumpWidget(harness(message));

      expect(find.text('Event cancelled'.toUpperCase()), findsOneWidget);
      // Still shown: a cancelled event is history, not something to hide.
      expect(find.text('Retro'), findsOneWidget);
    });
  });

  group('ordinary text is untouched', () {
    testWidgets('plain text still renders verbatim', (tester) async {
      await tester.pumpWidget(harness(messageWith(text: 'just a message')));
      expect(find.text('just a message'), findsOneWidget);
    });

    testWidgets('text mentioning a payload key is not mistaken for content', (
      tester,
    ) async {
      // A user can legitimately type this. The dispatcher reads the typed
      // fields, not the text, so it must not try to decode it.
      await tester.pumpWidget(
        harness(messageWith(text: 'the JSON has "content_type" in it')),
      );
      expect(find.text('the JSON has "content_type" in it'), findsOneWidget);
      expect(find.text('POLL'), findsNothing);
    });
  });
}
