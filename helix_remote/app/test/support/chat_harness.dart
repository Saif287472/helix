import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart' show SecureCryptoRandom;
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show Mention, MessageRef, PresenceResponse;
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// "Now" in every chat test: 3 October 2026, 14:30 local.
final DateTime testNow = DateTime(2026, 10, 3, 14, 30);

/// A gateway over a real, unsigned engine on an in-memory encrypted database.
///
/// Reads are the engine's own watch queries, so the screens run against the
/// real SQL (paging, FTS, summaries). Writes need an account and a server, so
/// they are simulated here: each one records a line in [log] and changes the
/// database the way the engine would, which is what the screens then show.
class TestChatGateway extends ChatGateway {
  TestChatGateway._(this.db, this.engine) : super(engine);

  static Future<TestChatGateway> create() async {
    final db = HelixDb.inMemory(key: DatabaseKey.generate());
    final api = HelixApi(
      baseUrl: Uri.parse('http://127.0.0.1:9'),
      sessions: DbSessionTokenStore(db),
      clientName: 'test',
    );
    final engine = Engine(
      api: api,
      db: db,
      clock: () => testNow,
      random: SecureCryptoRandom(),
    );
    return TestChatGateway._(db, engine);
  }

  final HelixDb db;
  final Engine engine;
  final List<String> log = [];
  int _n = 0;

  Future<void> close() async {
    await engine.close();
    await db.close();
  }

  @override
  String? get selfAccountId => 'me';

  @override
  bool get canSendMedia => true;

  // ---- fixtures

  Future<String> chatWith(String peer, {String? name}) async {
    final chat = await db.conversationsDao.ensureDirect(peer, now: testNow);
    await db.peopleDao.upsertPerson(
      PeopleCompanion.insert(
        accountId: peer,
        phonebookName: Value(name),
        updatedAt: testNow,
      ),
    );
    return chat.id;
  }

  Future<MessageRow> incoming(
    String chat,
    String text, {
    DateTime? at,
    String sender = 'bob',
    String? id,
  }) {
    final when = at ?? testNow.subtract(Duration(minutes: 600 - _n));
    final messageId = id ?? 'in${_n++}';
    return db.messagesDao.insertMessage(
      MessagesCompanion.insert(
        messageId: messageId,
        conversationId: chat,
        sender: sender,
        outgoing: false,
        sortKey: SortKey.of(when.toUtc(), messageId),
        sentAt: when.toUtc(),
        receivedAt: when.toUtc(),
        kind: 'text',
        body: Value(text),
        status: MessageStatus.received,
      ),
    );
  }

  Future<MessageRow> outgoing(
    String chat,
    String text, {
    DateTime? at,
    MessageStatus status = MessageStatus.sent,
    String? id,
  }) {
    final when = at ?? testNow.subtract(Duration(minutes: 600 - _n));
    final messageId = id ?? 'out${_n++}';
    return db.messagesDao.insertMessage(
      MessagesCompanion.insert(
        messageId: messageId,
        conversationId: chat,
        sender: 'me',
        outgoing: true,
        sortKey: SortKey.of(when.toUtc(), messageId),
        sentAt: when.toUtc(),
        receivedAt: when.toUtc(),
        kind: 'text',
        body: Value(text),
        status: status,
      ),
    );
  }

  // ---- simulated writes

  @override
  Future<void> sendText(
    String conversationId,
    String text, {
    MessageRef? replyTo,
    List<Mention> mentions = const [],
  }) async {
    log.add('sendText:$conversationId:$text');
    await outgoing(
      conversationId,
      text,
      at: testNow,
      status: MessageStatus.pending,
    );
  }

  @override
  Future<void> sendMedia(
    String conversationId,
    List<MediaInput> items, {
    String? caption,
    MessageRef? replyTo,
    bool viewOnce = false,
  }) async => log.add('sendMedia:$conversationId:${items.length}');

  @override
  Future<void> react(int rowid, String? emoji) async {
    log.add('react:$rowid:$emoji');
    if (emoji == null) {
      await db.messagesDao.removeReaction(rowid, reactor: 'me');
    } else {
      await db.messagesDao.setReaction(
        rowid,
        reactor: 'me',
        emoji: emoji,
        at: testNow,
      );
    }
  }

  @override
  Future<void> edit(int rowid, String text) async {
    log.add('edit:$rowid:$text');
    await db.messagesDao.editMessage(rowid, body: text, editedAt: testNow);
  }

  @override
  Future<void> deleteForEveryone(int rowid) async {
    log.add('deleteForEveryone:$rowid');
    await db.messagesDao.deleteForEveryone(rowid, deletedAt: testNow);
  }

  @override
  Future<void> deleteForMe(Iterable<int> rowids) async {
    log.add('deleteForMe:${rowids.join(',')}');
    await db.messagesDao.removeMessages(rowids);
  }

  @override
  Future<void> markRead(String id) async {
    log.add('markRead:$id');
    final chat = await db.conversationsDao.byId(id);
    final newest = chat?.lastMessageSortKey;
    if (newest != null) await db.messagesDao.markReadUpTo(id, newest);
  }

  @override
  Future<void> clearChat(String id) async {
    log.add('clearChat:$id');
    await db.messagesDao.clearConversation(id);
  }

  @override
  Future<void> setDisappearing(String id, int? seconds) async {
    log.add('setDisappearing:$id:$seconds');
    await db.conversationsDao.setDisappearingSeconds(id, seconds);
  }

  @override
  Future<void> sendTyping(
    String conversationId, {
    required bool typing,
  }) async => log.add('typing:$typing');

  @override
  Future<void> retrySend(int rowid) async => log.add('retry:$rowid');

  @override
  Future<void> forward(int rowid, String toConversationId) async =>
      log.add('forward:$rowid:$toConversationId');

  @override
  Future<void> block(String account) async {
    log.add('block:$account');
    await db.peopleDao.setBlocked(account, true, now: testNow);
  }

  @override
  Future<void> unblock(String account) async {
    log.add('unblock:$account');
    await db.peopleDao.setBlocked(account, false, now: testNow);
  }

  @override
  Future<PresenceResponse?> presence(String account) async =>
      PresenceResponse(account: account, online: true);

  @override
  Future<void> downloadNow(int attachmentId) async =>
      log.add('download:$attachmentId');
}

/// A scope with the test gateway and a fixed clock, around [home] in the real
/// light theme.
Widget chatApp(
  TestChatGateway gateway,
  Widget home, {
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [
    chatGatewayProvider.overrideWith((ref) => gateway),
    clockProvider.overrideWithValue(() => testNow),
    ...overrides,
  ],
  child: MaterialApp(theme: HelixThemes.light(), home: home),
);

/// Takes the app out of the tree and lets drift's stream clean-up timers run,
/// so a test does not end with a timer pending.
Future<void> disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

/// Lets real asynchronous work (the database, streams) finish, then draws.
Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// A widget test with its own gateway; the app is taken down at the end.
void chatTest(
  String name,
  Future<void> Function(WidgetTester tester, TestChatGateway gateway) body,
) => testWidgets(name, (tester) async {
  final gateway = (await tester.runAsync(TestChatGateway.create))!;
  await body(tester, gateway);
  await disposeApp(tester);
});
