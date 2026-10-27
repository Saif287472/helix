import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/engine/local_settings.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart' show SecureCryptoRandom;
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show LinkPreview, Mention, MessageRef, PresenceResponse, RsvpState;
import 'a3b_fakes.dart' show FakeLocalSettings;
import 'orbit_theme.dart';

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

  /// Where attachments "are on the device" (attachment id to path), for the
  /// audio and video tests.
  final Map<int, String> localPaths = {};

  @override
  Future<String?> localPathOf(int attachmentId) async =>
      localPaths[attachmentId];

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
    int? expireSeconds,
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
        // A received message arrives with no `expires_at`: the timer counts
        // from first display on this device, which the timeline reports.
        expireSeconds: expireSeconds == null
            ? const Value.absent()
            : Value(expireSeconds),
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
    LinkPreview? linkPreview,
  }) async {
    log.add('sendText:$conversationId:$text');
    if (linkPreview != null) {
      log.add('linkPreview:${linkPreview.url}:${linkPreview.title}');
    }
    await outgoing(
      conversationId,
      text,
      at: testNow,
      status: MessageStatus.pending,
    );
  }

  /// Groups the test lets only admins send to (the engine reads this from the
  /// group's encrypted state, which these tests do not build).
  final Set<String> adminsOnlyGroups = {};

  @override
  Stream<bool> watchCanSendToGroup(String groupId) =>
      Stream.value(!adminsOnlyGroups.contains(groupId));

  /// Pins are simulated like the other sends: the row changes the way the
  /// engine would change it, and a fourth is refused as the engine refuses it.
  @override
  Future<void> pinMessage(int rowid, {required bool pinned}) async {
    log.add('pin:$rowid:$pinned');
    final row = (await db.messagesDao.byRowid(rowid))!;
    if (pinned &&
        (await db.messagesDao.pinnedIn(row.conversationId)).length >= 3) {
      throw StateError('a chat keeps at most 3 pinned messages');
    }
    await db.messagesDao.setPinned(rowid, pinned ? testNow : null);
  }

  /// Your own vote or RSVP goes into the message's payload, as the engine
  /// does, which is what the bubble then draws.
  Future<void> _answer(int rowid, String key, Object? answer) async {
    final row = (await db.messagesDao.byRowid(rowid))!;
    final payload = row.payload == null
        ? <String, Object?>{}
        : (jsonDecode(row.payload!) as Map).cast<String, Object?>();
    final answers = {...(payload[key] as Map? ?? const {})};
    answer == null ? answers.remove('me') : answers['me'] = answer;
    await db.messagesDao.updatePayload(
      rowid,
      jsonEncode({...payload, key: answers}),
    );
  }

  @override
  Future<void> vote(int rowid, List<String> optionIds) async {
    log.add('vote:$rowid:${optionIds.join(',')}');
    await _answer(rowid, 'votes', optionIds.isEmpty ? null : optionIds);
  }

  @override
  Future<void> rsvp(int rowid, RsvpState state) async {
    log.add('rsvp:$rowid:${state.wire}');
    await _answer(rowid, 'rsvps', {'state': state.wire, 'plus_one': false});
  }

  Future<void> _sendCard(
    String conversationId,
    String kind,
    Map<String, Object?> payload,
  ) => db.messagesDao.insertMessage(
    MessagesCompanion.insert(
      messageId: 'card${_n++}',
      conversationId: conversationId,
      sender: 'me',
      outgoing: true,
      sortKey: SortKey.of(testNow.toUtc(), 'card$_n'),
      sentAt: testNow.toUtc(),
      receivedAt: testNow.toUtc(),
      kind: kind,
      payload: Value(jsonEncode(payload)),
      status: MessageStatus.pending,
    ),
  );

  @override
  Future<void> sendPoll(
    String conversationId, {
    required String question,
    required List<String> options,
    bool multiple = false,
  }) async {
    log.add(
      'sendPoll:$conversationId:$question:${options.join('|')}:$multiple',
    );
    await _sendCard(conversationId, 'poll', {
      'question': question,
      'options': [
        for (final (i, t) in options.indexed) {'id': 'o${i + 1}', 'text': t},
      ],
      'multiple': multiple,
    });
  }

  @override
  Future<void> sendEvent(
    String conversationId, {
    required String title,
    required DateTime startsAt,
    String place = '',
  }) async {
    log.add('sendEvent:$conversationId:$title:${startsAt.toIso8601String()}');
    await _sendCard(conversationId, 'event', {
      'title': title,
      'starts_at': startsAt.toUtc().millisecondsSinceEpoch,
      'time_zone': 'UTC+00:00',
      'location_text': ?(place.isEmpty ? null : place),
    });
  }

  /// Makes every media send fail (the engine refused or the disk is full).
  bool failMedia = false;

  /// The paths of the items of every media send, in order.
  final List<String?> sentPaths = [];

  @override
  Future<void> sendMedia(
    String conversationId,
    List<MediaInput> items, {
    String? caption,
    MessageRef? replyTo,
    bool viewOnce = false,
  }) async {
    if (failMedia) throw StateError('refused');
    sentPaths.addAll([for (final i in items) i.path]);
    log.add('sendMedia:$conversationId:${items.length}');
  }

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

  /// What the timeline should show as failed actions (the real ones live in
  /// the outbox, which a test builds only when it needs to).
  final List<FailedAction> actionFailures = [];

  @override
  Stream<List<FailedAction>> watchFailedActions(String conversationId) =>
      Stream.value(actionFailures);

  @override
  Future<List<FailedAction>> failedActions(String conversationId) async =>
      actionFailures;

  @override
  Future<void> retryAction(int opId) async => log.add('retryAction:$opId');

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

/// A scope with the test gateway, a fixed clock and in-memory settings
/// ([settings], e.g. "Enter key sends"), around [home] in the Orbit theme.
/// With [routes], [home] is `/` of a router that has them too.
Widget chatApp(
  TestChatGateway gateway,
  Widget home, {
  List<Override> overrides = const [],
  FakeLocalSettings? settings,
  List<RouteBase> routes = const [],
}) => ProviderScope(
  overrides: [
    chatGatewayProvider.overrideWith((ref) => gateway),
    localSettingsProvider.overrideWithValue(settings ?? FakeLocalSettings()),
    // Names are the app's one source; here its rows are the test database's.
    peopleRowsProvider.overrideWith((ref) => gateway.engine.people.watchAll()),
    clockProvider.overrideWithValue(() => testNow),
    ...overrides,
  ],
  child: routes.isEmpty
      ? MaterialApp(
          theme: orbitTestTheme(),
          builder: orbitTestBuilder,
          home: home,
        )
      : MaterialApp.router(
          theme: orbitTestTheme(),
          builder: orbitTestBuilder,
          routerConfig: GoRouter(
            routes: [
              GoRoute(path: '/', builder: (_, _) => home),
              ...routes,
            ],
          ),
        ),
);

/// Takes the app out of the tree and lets drift's stream clean-up timers
/// and the last Orbit toast's (4s at most) run, so a test does not end with
/// a timer pending.
Future<void> disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
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
