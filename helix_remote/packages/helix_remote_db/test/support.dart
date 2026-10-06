import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final t0 = DateTime.utc(2026, 10, 1, 12);

DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

/// A temporary directory removed after the test.
Directory tempDir() {
  final dir = Directory.systemTemp.createTempSync('helix_db_test_');
  addTearDown(() async {
    for (var i = 0; i < 5; i++) {
      try {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        // Windows may hold the file briefly after close.
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });
  return dir;
}

File dbFile(Directory dir) => File(p.join(dir.path, 'helix.db'));

/// An in-memory database closed after the test.
HelixDb memoryDb() {
  final db = HelixDb.inMemory();
  addTearDown(db.close);
  return db;
}

Future<ConversationRow> directChat(HelixDb db, String peer) =>
    db.conversationsDao.ensureDirect(peer, now: t0);

/// A text message from [sender] (incoming unless [outgoing]).
MessagesCompanion textMessage(
  String conversationId,
  String id, {
  required DateTime sentAt,
  String sender = 'bob',
  String? body,
  bool outgoing = false,
  bool mentionsMe = false,
  MessageStatus? status,
  int? expireSeconds,
}) => MessagesCompanion.insert(
  messageId: id,
  conversationId: conversationId,
  sender: sender,
  outgoing: outgoing,
  sortKey: SortKey.of(sentAt, id),
  sentAt: sentAt,
  receivedAt: sentAt,
  kind: 'text',
  body: Value(body ?? 'message $id'),
  mentionsMe: Value(mentionsMe),
  status: status ?? (outgoing ? MessageStatus.pending : MessageStatus.received),
  expireSeconds: Value(expireSeconds),
);

/// True if any of the database's files contain [marker] in plaintext.
bool databaseFilesContain(File file, String marker) {
  final needle = utf8.encode(marker);
  for (final suffix in const ['', '-wal', '-shm', '-journal']) {
    final f = File('${file.path}$suffix');
    if (f.existsSync() && _contains(f.readAsBytesSync(), needle)) return true;
  }
  return false;
}

bool _contains(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// Collects a stream's events until the test ends.
List<T> collect<T>(Stream<T> stream) {
  final events = <T>[];
  final sub = stream.listen(events.add);
  addTearDown(sub.cancel);
  return events;
}

/// Waits until [condition] holds (stream emissions are asynchronous).
Future<void> eventually(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
