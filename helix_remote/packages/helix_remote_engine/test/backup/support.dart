import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../support/fake_server.dart';
import '../support/peers.dart' show SeededRandom, TestClock, fastConfig;

/// The server's backup module in memory, with its version rule (only a higher
/// version replaces) and size limit.
final class FakeBackupRemote implements BackupRemote {
  HistoryBackup? stored;

  /// The largest history blob accepted (the real limit is 16 MiB).
  int limit = HistoryBackup.maxBytes;
  FullBackup? fullStored;
  int historyPuts = 0;
  int fullPuts = 0;

  /// Makes the next [n] calls of any kind fail like a dropped connection.
  int offline = 0;

  void _check() {
    if (offline > 0) {
      offline--;
      throw const NetworkException();
    }
  }

  @override
  Future<HistoryBackup?> history() async {
    _check();
    return stored;
  }

  @override
  Future<void> putHistory(HistoryBackup backup) async {
    _check();
    historyPuts++;
    if (backup.data.length > limit) {
      throw const ApiException(status: 413, code: ErrorCode.payloadTooLarge);
    }
    final current = stored;
    if (current != null && current.version >= backup.version) {
      throw const ApiException(status: 409, code: ErrorCode.versionConflict);
    }
    stored = backup;
  }

  @override
  Future<void> deleteHistory() async {
    _check();
    stored = null;
  }

  @override
  Future<FullBackup?> full() async {
    _check();
    return fullStored;
  }

  @override
  Future<void> putFull(FullBackup backup) async {
    _check();
    fullPuts++;
    final current = fullStored;
    if (current != null && current.version >= backup.version) {
      throw const ApiException(status: 409, code: ErrorCode.versionConflict);
    }
    // The server refuses forbidden fields at any depth.
    final text = jsonEncode(backup.envelope);
    for (final field in FullBackup.forbiddenFields) {
      if (text.contains('"$field"')) {
        throw const ApiException(status: 400, code: ErrorCode.invalidField);
      }
    }
    // A stored copy is what a later GET returns: through JSON.
    fullStored = FullBackup.fromJson(
      JsonReader.decode(jsonEncode(backup.toJson())),
    );
  }

  @override
  Future<void> deleteFull() async {
    _check();
    fullStored = null;
  }
}

/// The media relay in memory.
final class FakeRelay implements RelayStore {
  final Map<String, Uint8List> objects = {};
  final List<String> deleted = [];
  final Map<String, int> downloads = {};
  int _next = 0;

  /// Uploads after this many fail like a dropped connection (null: never).
  int? failUploadsAfter;
  int _uploads = 0;

  /// Object ids whose next download fails like a dropped connection.
  final Set<String> dropOnce = {};

  /// Applied to the bytes of every download (to tamper in a test).
  Uint8List Function(String id, Uint8List bytes)? tamper;

  @override
  Future<String> upload(
    List<int> ciphertext, {
    CancellationToken? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) throw const RequestCancelledException();
    final limit = failUploadsAfter;
    if (limit != null && ++_uploads > limit) throw const NetworkException();
    final id =
        '00000000-0000-4000-8000-${(_next++).toRadixString(16).padLeft(12, '0')}';
    objects[id] = Uint8List.fromList(ciphertext);
    return id;
  }

  @override
  Future<Uint8List> download(
    String mediaId, {
    CancellationToken? cancel,
  }) async {
    downloads[mediaId] = (downloads[mediaId] ?? 0) + 1;
    if (dropOnce.remove(mediaId)) throw const NetworkException();
    final bytes = objects[mediaId];
    if (bytes == null) {
      throw const ApiException(status: 404, code: ErrorCode.notFound);
    }
    final hook = tamper;
    return hook == null ? bytes : hook(mediaId, Uint8List.fromList(bytes));
  }

  @override
  Future<void> delete(String mediaId) async {
    deleted.add(mediaId);
    objects.remove(mediaId);
  }
}

/// One engine on an in-memory database, against the shared fake server,
/// backup remote and relay.
final class BackupPeer {
  BackupPeer._(this.name, this.db, this.api, this.engine);

  final String name;
  final HelixDb db;
  final HelixApi api;
  final Engine engine;

  String get account => engine.accountId!;
  String get device => engine.deviceId!;
  BackupService get backup => engine.backup;

  Future<void> dispose() async {
    await engine.close();
    await api.close();
    await db.close();
  }
}

/// A fake server plus a fake backup server and relay shared by the peers a
/// test creates.
final class BackupWorld {
  BackupWorld({
    this.pageSize = 400,
    this.frameBytes = 256 * 1024,
    this.segmentBytes = 4 * 1024 * 1024,
    this.maxHistoryBytes = HistoryBackup.maxBytes,
    this.compress = true,
  }) {
    server = FakeServer(clock: clock.call);
  }

  final int pageSize;
  final int frameBytes;
  final int segmentBytes;
  final int maxHistoryBytes;
  final bool compress;

  final TestClock clock = TestClock();
  late final FakeServer server;
  final FakeBackupRemote remote = FakeBackupRemote();
  final FakeRelay relay = FakeRelay();
  final List<BackupPeer> _all = [];
  int _seed = 0;

  BackupOptions options() => BackupOptions(
    gzip: compress ? gzip : null,
    autoBackup: false,
    autoTransferToNewDevices: false,
    autoAcceptTransfers: false,
    pageSize: pageSize,
    frameBytes: frameBytes,
    segmentBytes: segmentBytes,
    maxHistoryBytes: maxHistoryBytes,
    remote: remote,
    relay: relay,
  );

  Future<BackupPeer> create(String name, {BackupOptions? options}) async {
    final db = HelixDb.inMemory(key: DatabaseKey.generate());
    final api = HelixApi(
      baseUrl: FakeServer.baseUri,
      sessions: DbSessionTokenStore(db),
      httpClient: server.client,
      retry: RetryPolicy.none,
    );
    final engine = Engine(
      api: api,
      db: db,
      clock: clock.call,
      random: SeededRandom('$name${_seed++}'),
      config: fastConfig,
      backupOptions: options ?? this.options(),
    );
    final peer = BackupPeer._(name, db, api, engine);
    _all.add(peer);
    await engine.start(realtime: false, background: false);
    return peer;
  }

  Future<BackupPeer> register(String name, {String? phone}) async {
    final peer = await create(name);
    final challenge = await peer.engine.account.requestPhoneCode(
      phone ?? '+8801700000000',
    );
    final verified = await peer.engine.account.verifyPhone(
      challenge.challengeId,
      '123456',
    );
    await peer.engine.account.register(
      verificationToken: verified.verificationToken,
      phoneNumber: phone,
    );
    expect(peer.engine.status, EngineStatus.running);
    if (phone != null) server.accounts[peer.account]!.phone = phone;
    return peer;
  }

  /// Links a second device of [existing] by QR code.
  Future<BackupPeer> link(BackupPeer existing, String name) async {
    final fresh = await create(name);
    final link = await fresh.engine.account.beginLink();
    final done = link.complete();
    await existing.engine.devices.approveLink(link.code);
    await done;
    expect(fresh.account, existing.account);
    return fresh;
  }

  Future<void> dispose() async {
    for (final peer in _all.reversed) {
      try {
        await peer.dispose();
      } on Object {
        // Closed by the test.
      }
    }
  }
}

// ---------------------------------------------------------------- helpers

int _idCounter = 1;

/// Inserts [count] text messages straight into [peer]'s database, alternating
/// between the peer and [chatPeer] as author, a second apart.
Future<List<MessageRow>> addHistory(
  BackupPeer peer,
  String chatPeer,
  int count, {
  String prefix = 'message',
  DateTime? from,
  MessageStatus incoming = MessageStatus.received,
}) async {
  await peer.db.conversationsDao.ensureDirect(
    chatPeer,
    now: DateTime.utc(2026, 1, 1),
  );
  final start = from ?? DateTime.utc(2026, 3, 1);
  final rows = <MessageRow>[];
  for (var i = 0; i < count; i++) {
    final mine = i.isEven;
    final sentAt = start.add(Duration(seconds: i));
    final id =
        '0192a4f0-0000-7000-8000-${(_idCounter++).toRadixString(16).padLeft(12, '0')}';
    rows.add(
      await peer.db.messagesDao.insertMessage(
        MessagesCompanion.insert(
          messageId: id,
          conversationId: directConversationId(chatPeer),
          sender: mine ? peer.account : chatPeer,
          outgoing: mine,
          sortKey: SortKey.of(sentAt, id),
          sentAt: sentAt,
          receivedAt: sentAt,
          kind: 'text',
          status: mine ? MessageStatus.delivered : incoming,
          body: Value('$prefix $i'),
        ),
      ),
    );
  }
  return rows;
}

/// What two devices must agree on after a restore: every message's identity,
/// text and state, and the chat list's summary columns.
Future<List<String>> historyDigest(BackupPeer peer) async {
  final out = <String>[];
  final chats = await HistoryStore(peer.db).conversations();
  for (final chat in chats) {
    out.add(
      'chat ${chat.id} last=${chat.lastMessageSortKey} '
      'unread=${chat.unreadCount} preview=${chat.lastMessagePreview}',
    );
    final all = await peer.db.messagesDao.pageOlder(chat.id, limit: 100000);
    for (final m in all.messages) {
      final reactions = await peer.db.messagesDao.reactionsFor([m.localRowid]);
      out.add(
        '${m.messageId}|${m.sender}|${m.body}|${m.status.name}|${m.kind}'
        '|${m.deletedAt?.millisecondsSinceEpoch}|${m.editedAt?.millisecondsSinceEpoch}'
        '|${[for (final r in reactions) '${r.reactor}:${r.emoji}']}',
      );
    }
  }
  return out;
}
