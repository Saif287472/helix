import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../support/fake_media.dart';
import '../support/fake_server.dart';
import '../support/peers.dart';

/// Short timers; the sweep takes every unreferenced file at once.
const testTransfers = TransferConfig(
  chunkBytes: 4096,
  backoff: Backoff(
    initial: Duration(seconds: 2),
    max: Duration(minutes: 1),
    jitter: 0,
  ),
  sweepGrace: Duration.zero,
  sweepInterval: Duration(hours: 1),
);

/// One engine with a transfer queue: its own database, file store and
/// processor, on the world's fake server and fake media server.
final class MediaPeer {
  MediaPeer._(this.name, this.db, this.api, this.engine, this.blobs);

  final String name;
  final HelixDb db;
  final HelixApi api;
  final Engine engine;
  final MemoryBlobStore blobs;

  String get account => engine.accountId!;

  String chatWith(MediaPeer other) => directConversationId(other.account);

  /// Opens (creates) the direct chat with [other].
  Future<String> openChat(MediaPeer other) async =>
      (await engine.chats.openDirect(other.account)).id;

  Future<List<MessageRow>> messages(MediaPeer other) async =>
      (await db.messagesDao.pageOlder(chatWith(other), limit: 500)).messages;

  Future<List<AttachmentRow>> attachments(MessageRow message) =>
      db.messagesDao.attachmentsFor([message.localRowid]);

  /// Sends what is queued, fetches what is waiting, and runs the queue.
  Future<void> settle() async {
    await engine.drainTransfers();
    await engine.drainOutbox();
    await engine.syncOnce();
    await engine.drainTransfers();
    await engine.drainOutbox();
  }

  Future<void> dispose() async {
    await engine.close();
    await api.close();
    await db.close();
  }
}

/// Engines on one fake server and one fake media server.
final class MediaWorld {
  MediaWorld({FakeMedia? media, TestClock? clock})
    : media = media ?? FakeMedia(),
      clock = clock ?? TestClock() {
    server = FakeServer(clock: this.clock.call);
  }

  final FakeMedia media;
  final TestClock clock;
  late final FakeServer server;
  final List<MediaPeer> _all = [];
  int _seed = 0;

  Future<MediaPeer> register(
    String name, {
    TransferConfig transfers = testTransfers,
    MediaProcessor? processor,
    MemoryBlobStore? blobs,
    bool background = false,
    EngineConfig config = fastConfig,
    bool withBlobs = true,
  }) async {
    final db = HelixDb.inMemory(key: DatabaseKey.generate());
    final api = HelixApi(
      baseUrl: FakeServer.baseUri,
      sessions: DbSessionTokenStore(db),
      httpClient: media.wrap(server.client),
      retry: RetryPolicy.none,
    );
    final store = blobs ?? MemoryBlobStore(clock: clock.call);
    final engine = Engine(
      api: api,
      db: db,
      clock: clock.call,
      random: SeededRandom('$name${_seed++}'),
      config: config,
      blobs: withBlobs ? store : null,
      mediaProcessor: processor,
      transferConfig: transfers,
    );
    final peer = MediaPeer._(name, db, api, engine, store);
    _all.add(peer);
    await engine.start(realtime: false, background: background);
    final challenge = await engine.account.requestPhoneCode('+8801700000000');
    final verified = await engine.account.verifyPhone(
      challenge.challengeId,
      '123456',
    );
    await engine.account.register(
      verificationToken: verified.verificationToken,
    );
    expect(engine.status, EngineStatus.running);
    return peer;
  }

  /// A new engine over the same database, file store and server: the app
  /// was killed and started again. The old engine is stopped without
  /// cleaning anything up.
  Future<MediaPeer> restart(
    MediaPeer old, {
    TransferConfig transfers = testTransfers,
  }) async {
    await old.engine.close();
    final engine = Engine(
      api: old.api,
      db: old.db,
      clock: clock.call,
      random: SeededRandom('${old.name}-restart${_seed++}'),
      config: fastConfig,
      blobs: old.blobs,
      transferConfig: transfers,
    );
    final peer = MediaPeer._(old.name, old.db, old.api, engine, old.blobs);
    _all.add(peer);
    await engine.start(realtime: false, background: false);
    expect(engine.status, EngineStatus.running);
    return peer;
  }

  /// An engine built without a file store.
  Future<MediaPeer> registerWithoutBlobs(String name) =>
      register(name, withBlobs: false);

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

/// A deterministic file of [length] bytes.
Uint8List patterned(int length, {int seed = 1}) => Uint8List.fromList([
  for (var i = 0; i < length; i++) (i * 31 + seed) & 0xFF,
]);

/// A file that starts like a PNG of [width] x [height] (so the basic
/// processor finds the size), padded to [length] bytes.
Uint8List pngLike(int width, int height, {int length = 2000}) {
  final bytes = patterned(length, seed: 7);
  const magic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  bytes.setRange(0, 8, magic);
  final view = ByteData.sublistView(bytes);
  view.setUint32(16, width);
  view.setUint32(20, height);
  return bytes;
}

/// A processor that knows what the test says it knows.
final class FakeProcessor implements MediaProcessor {
  FakeProcessor({
    this.thumbnail,
    this.blurhash,
    this.duration,
    this.fail = false,
  });

  final Uint8List? thumbnail;
  final String? blurhash;
  final int? duration;
  final bool fail;
  final List<String> seen = [];

  @override
  Future<ProcessedMedia> process({
    required String path,
    required MediaItemKind kind,
    required String mime,
  }) async {
    seen.add('${kind.wire}:$mime');
    if (fail) throw StateError('codec exploded');
    return ProcessedMedia(
      width: kind == MediaItemKind.image || kind == MediaItemKind.video
          ? 640
          : null,
      height: kind == MediaItemKind.image || kind == MediaItemKind.video
          ? 480
          : null,
      durationMs: kind == MediaItemKind.video ? duration : null,
      blurhash: kind == MediaItemKind.image ? blurhash : null,
      thumbnail: kind == MediaItemKind.image || kind == MediaItemKind.video
          ? thumbnail
          : null,
    );
  }
}

/// A JPEG-looking thumbnail.
Uint8List thumbnailBytes([int length = 300]) {
  final bytes = patterned(length, seed: 99);
  bytes[0] = 0xFF;
  bytes[1] = 0xD8;
  return bytes;
}

/// The message of [peer] that arrived from [other], newest first.
Future<MessageRow> lastMessage(MediaPeer peer, MediaPeer other) async =>
    (await peer.messages(other)).last;
