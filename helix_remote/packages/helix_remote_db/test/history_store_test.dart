import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support.dart';

/// `HistoryStore.backupableCount` is the backup's export filter counted in the
/// database: view-once and already-expired messages are never kept, and the
/// caller names the kinds and statuses to leave out as well.
///
/// The review (AUD-10-2) expected an empty list to render `NOT IN ()` and fail
/// as a syntax error. SQLite - unlike the SQL standard and most engines -
/// accepts an empty list there, and `x NOT IN ()` is true, so an empty list
/// already counted correctly. These tests pin that, so a rewrite of the query
/// (or a move to an engine without the extension) cannot break it unseen.
void main() {
  late HelixDb db;
  final now = at(10);

  setUp(() async {
    db = memoryDb();
    addTearDown(db.close);
    final chat = (await directChat(db, 'bob')).id;
    final messages = db.messagesDao;
    await messages.insertMessage(textMessage(chat, 'kept', sentAt: at(1)));
    await messages.insertMessage(
      textMessage(
        chat,
        'other',
        sentAt: at(2),
      ).copyWith(kind: const Value('other')),
    );
    await messages.insertMessage(
      textMessage(
        chat,
        'failed',
        sentAt: at(3),
        outgoing: true,
        status: MessageStatus.failed,
      ),
    );
    await messages.insertMessage(
      textMessage(
        chat,
        'expiring',
        sentAt: at(4),
      ).copyWith(expiresAt: Value(at(60))),
    );
    // Never in a backup, whatever the caller leaves out.
    await messages.insertMessage(
      textMessage(
        chat,
        'view-once',
        sentAt: at(5),
      ).copyWith(viewOnceState: const Value(ViewOnceState.unopened)),
    );
    await messages.insertMessage(
      textMessage(
        chat,
        'expired',
        sentAt: at(6),
      ).copyWith(expiresAt: Value(at(7))),
    );
  });

  Future<int> count({
    List<String> kinds = const [],
    List<MessageStatus> statuses = const [],
  }) => HistoryStore(
    db,
  ).backupableCount(now: now, excludedKinds: kinds, excludedStatuses: statuses);

  test(
    'with nothing to leave out, counts every message a backup keeps',
    () async {
      expect(await HistoryStore(db).messageCount(), 6);
      expect(await count(), 4, reason: 'all but the view-once and the expired');
    },
  );

  test(
    'leaves out the kinds and statuses it is given, either list empty',
    () async {
      expect(await count(kinds: ['other']), 3);
      expect(await count(statuses: [MessageStatus.failed]), 3);
      expect(
        await count(
          kinds: ['other'],
          statuses: [MessageStatus.failed, MessageStatus.pending],
        ),
        2,
      );
    },
  );
}
