import 'dart:async';
import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../../support/flows.dart';
import '../../support/harness.dart';
import '../../support/test_database.dart';
import 'support.dart';

/// Attachments end to end: two engines with a transfer queue on the real
/// in-process server (media module over local storage), the real REST client
/// and live sockets. Interruptions are injected between the client and the
/// server, so the engines meet them as a phone going through a tunnel would.
void main() {
  // Server start-up, registrations and megabytes through the real server are
  // slower than the default 30 s on a busy machine.
  group(
    'engine media',
    skip: databaseTestSkipReason,
    timeout: const Timeout(Duration(minutes: 2)),
    () {
      late Harness h;
      late _World world;

      Future<void> start({Map<String, String> extra = const {}}) async {
        h = await Harness.start(extra: extra);
        world = _World(h);
      }

      tearDown(() async {
        await world.dispose();
        await h.stop();
      });

      test(
        'an image, a document and a voice note reach the other side',
        () async {
          await start();
          final alice = await world.register(
            'alice',
            aliceNumber,
            processor: _Thumbnailer(),
          );
          final bob = await world.register('bob', bobNumber);
          final chat = (await alice.engine.chats.openDirect(bob.account)).id;
          await bob.engine.settings.set(
            MediaSettings.autoDownloadDocuments,
            MediaSettings.unlimited,
          );

          final photo = _png(1024, 768, 90 * 1024);
          final pdf = _bytes(150 * 1024, seed: 5);
          final voice = _bytes(21 * 1024, seed: 8);
          final waveform = Uint8List.fromList(List.generate(64, (i) => i * 4));
          final image = await alice.engine.media.sendMedia(chat, [
            MediaInput.bytes(
              bytes: photo,
              kind: MediaItemKind.image,
              mime: 'image/png',
            ),
          ], caption: 'the beach');
          await alice.engine.media.sendMedia(chat, [
            MediaInput.bytes(
              bytes: pdf,
              kind: MediaItemKind.document,
              mime: 'application/pdf',
              name: 'tickets.pdf',
            ),
          ]);
          await alice.engine.media.sendMedia(chat, [
            MediaInput.bytes(
              bytes: voice,
              kind: MediaItemKind.voiceNote,
              mime: 'audio/ogg',
              durationMs: 7300,
              waveform: waveform,
            ),
          ]);

          // Everything is delivered and fetched without anyone asking.
          await settle(() async {
            final received = await _mediaMessages(bob, alice);
            expect(received, hasLength(3));
            for (final message in received) {
              final views = await bob.engine.media.viewsOf(message.localRowid);
              expect(views.single.phase, TransferPhase.ready);
            }
          });
          final received = await _mediaMessages(bob, alice);
          expect(received.first.body, 'the beach');
          final photoRow = (await _attachmentsOf(bob, received[0])).single;
          expect(
            bob.blobs.bytesOf(
              (await bob.engine.media.openLocalPath(photoRow.id))!,
            ),
            photo,
          );
          expect((photoRow.width, photoRow.height), (1024, 768));
          expect(
            bob.blobs.bytesOf(
              (await bob.engine.media.thumbnailPath(photoRow.id))!,
            ),
            _Thumbnailer.thumbnail,
          );
          final docRow = (await _attachmentsOf(bob, received[1])).single;
          expect(docRow.name, 'tickets.pdf');
          expect(
            bob.blobs.bytesOf(
              (await bob.engine.media.openLocalPath(docRow.id))!,
            ),
            pdf,
          );
          final noteRow = (await _attachmentsOf(bob, received[2])).single;
          expect(noteRow.durationMs, 7300);
          expect(noteRow.waveform, orderedEquals(waveform));
          expect(
            bob.blobs.bytesOf(
              (await bob.engine.media.openLocalPath(noteRow.id))!,
            ),
            voice,
          );

          // Alice's message went from pending to delivered, and kept its file.
          await settle(() async {
            final row = await alice.db.messagesDao.byRowid(image.localRowid);
            expect(row!.status, MessageStatus.delivered);
          });
          final sentRow = (await _attachmentsOf(alice, image)).single;
          expect(sentRow.transfer, AttachmentTransfer.ready);
          expect(
            alice.blobs.bytesOf(sentRow.localPath!),
            photo,
            reason: 'the sender keeps her copy',
          );
          // The server holds ciphertext only: nothing of the file in its objects.
          expect(alice.blobs.pathsIn(BlobArea.staging), isEmpty);
          expect(bob.blobs.pathsIn(BlobArea.staging), isEmpty);

          // The other way round, with a caption and a reply.
          final reply = await bob.engine.media.sendMedia(
            directConversationId(alice.account),
            [
              MediaInput.bytes(
                bytes: voice,
                kind: MediaItemKind.voiceNote,
                mime: 'audio/ogg',
                durationMs: 1000,
              ),
            ],
            replyTo: MessageRef(id: image.messageId, author: alice.account),
          );
          await settle(() async {
            final incoming = (await _mediaMessages(
              alice,
              bob,
            )).where((m) => !m.outgoing);
            expect(incoming, hasLength(1));
            final back = incoming.single;
            expect(back.replyToId, image.messageId);
            final views = await alice.engine.media.viewsOf(back.localRowid);
            expect(views.single.phase, TransferPhase.ready);
          });
          expect(reply.status, MessageStatus.pending);
        },
      );

      test(
        'an upload cut off in the middle resumes where the server stopped',
        () async {
          await start();
          final flaky = _Flaky();
          final alice = await world.register(
            'alice',
            aliceNumber,
            flaky: flaky,
          );
          final bob = await world.register('bob', bobNumber);
          final chat = (await alice.engine.chats.openDirect(bob.account)).id;
          await bob.engine.settings.set(
            MediaSettings.autoDownloadDocuments,
            MediaSettings.unlimited,
          );

          // 1 MiB in 64 KiB requests; the connection dies on the 5th and 9th.
          flaky.dropPuts({5, 9});
          final data = _bytes(1024 * 1024, seed: 11);
          final sent = await alice.engine.media.sendMedia(chat, [
            MediaInput.bytes(
              bytes: data,
              kind: MediaItemKind.document,
              mime: 'application/zip',
              name: 'archive.zip',
            ),
          ]);

          await settle(() async {
            final row = await alice.db.messagesDao.byRowid(sent.localRowid);
            expect(
              row!.status.index,
              greaterThanOrEqualTo(MessageStatus.sent.index),
            );
          });
          await settle(() async {
            final received = await _mediaMessages(bob, alice);
            expect(received, hasLength(1));
            final view = (await bob.engine.media.viewsOf(
              received.single.localRowid,
            )).single;
            expect(view.phase, TransferPhase.ready);
          });
          final att = (await _attachmentsOf(
            bob,
            (await _mediaMessages(bob, alice)).single,
          )).single;
          expect(
            bob.blobs.bytesOf((await bob.engine.media.openLocalPath(att.id))!),
            data,
          );

          // The dropped requests were followed by ones at the same offset, never
          // by a restart from zero.
          final puts = flaky.putOffsets;
          expect(puts.where((o) => o == 0), hasLength(1), reason: 'one start');
          expect(
            puts.toSet().length,
            lessThan(puts.length),
            reason: 'repeated',
          );
          final distinct = puts.toSet().toList()..sort();
          expect(distinct, [
            for (var i = 0; i < distinct.length; i++) i * 64 * 1024,
          ], reason: 'no gaps: every chunk was sent');
          expect(flaky.statusRequests, greaterThan(0), reason: 'asked HEAD');
        },
      );

      test(
        'a large file goes up and down in chunks',
        () async {
          await start();
          final flaky = _Flaky();
          final alice = await world.register(
            'alice',
            aliceNumber,
            flaky: flaky,
          );
          final bob = await world.register('bob', bobNumber, flaky: flaky);
          final chat = (await alice.engine.chats.openDirect(bob.account)).id;
          await bob.engine.settings.set(
            MediaSettings.autoDownloadVideo,
            MediaSettings.unlimited,
          );
          final data = _bytes(5 * 1024 * 1024 + 123, seed: 3);
          await alice.engine.media.sendMedia(chat, [
            MediaInput.bytes(
              bytes: data,
              kind: MediaItemKind.video,
              mime: 'video/mp4',
              name: 'clip.mp4',
            ),
          ]);
          await settle(() async {
            final received = await _mediaMessages(bob, alice);
            expect(received, hasLength(1));
            final view = (await bob.engine.media.viewsOf(
              received.single.localRowid,
            )).single;
            expect(view.phase, TransferPhase.ready);
            expect(view.fraction, 1);
          }, timeout: const Duration(seconds: 60));
          final att = (await _attachmentsOf(
            bob,
            (await _mediaMessages(bob, alice)).single,
          )).single;
          final path = (await bob.engine.media.openLocalPath(att.id))!;
          expect(bob.blobs.bytesOf(path), data);
          // 5 MiB over 64 KiB requests, both ways.
          expect(flaky.putOffsets.length, greaterThanOrEqualTo(80));
          expect(flaky.getRanges.length, greaterThanOrEqualTo(80));
          expect(flaky.getRanges.first, 0);
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'a download cut off in the middle resumes from the staged bytes',
        () async {
          await start();
          final flaky = _Flaky();
          final alice = await world.register('alice', aliceNumber);
          final bob = await world.register('bob', bobNumber, flaky: flaky);
          final chat = (await alice.engine.chats.openDirect(bob.account)).id;
          await bob.engine.settings.set(
            MediaSettings.autoDownloadImages,
            MediaSettings.unlimited,
          );
          flaky.dropGets({4});
          final data = _bytes(512 * 1024, seed: 21);
          await alice.engine.media.sendMedia(chat, [
            MediaInput.bytes(
              bytes: data,
              kind: MediaItemKind.image,
              mime: 'image/jpeg',
            ),
          ]);
          await settle(() async {
            final received = await _mediaMessages(bob, alice);
            expect(received, hasLength(1));
            final view = (await bob.engine.media.viewsOf(
              received.single.localRowid,
            )).single;
            expect(view.phase, TransferPhase.ready);
          });
          final ranges = flaky.getRanges;
          // 0, 64K, 128K, 192K (dropped), 192K again, ...
          expect(ranges.take(5), [0, 65536, 131072, 196608, 196608]);
          final att = (await _attachmentsOf(
            bob,
            (await _mediaMessages(bob, alice)).single,
          )).single;
          expect(
            bob.blobs.bytesOf((await bob.engine.media.openLocalPath(att.id))!),
            data,
          );
        },
      );

      test('a file over the server limit fails with a typed error', () async {
        await start(extra: {'HELIX_MAX_ATTACHMENT_BYTES': '2048'});
        final alice = await world.register('alice', aliceNumber);
        final bob = await world.register('bob', bobNumber);
        final chat = (await alice.engine.chats.openDirect(bob.account)).id;
        final failures = <SendFailedEvent>[];
        final sub = alice.engine.events.listen((e) {
          if (e is SendFailedEvent) failures.add(e);
        });
        addTearDown(sub.cancel);

        final sent = await alice.engine.media.sendMedia(chat, [
          MediaInput.bytes(
            bytes: _bytes(10 * 1024),
            kind: MediaItemKind.document,
            mime: 'application/zip',
          ),
        ]);
        await settle(() async {
          final view = (await alice.engine.media.viewsOf(
            sent.localRowid,
          )).single;
          expect(view.phase, TransferPhase.failed);
          expect(view.failure, TransferFailure.tooLarge);
        });
        expect(
          (await alice.db.messagesDao.byRowid(sent.localRowid))!.status,
          MessageStatus.failed,
        );
        expect(failures.single.errorCode, 'too_large');
        // Nothing half-made reached Bob.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(await _mediaMessages(bob, alice), isEmpty);

        // A small one goes through.
        await alice.engine.media.sendMedia(chat, [
          MediaInput.bytes(
            bytes: _bytes(500),
            kind: MediaItemKind.document,
            mime: 'text/plain',
          ),
        ]);
        await settle(() async {
          expect(await _mediaMessages(bob, alice), hasLength(1));
        });
      });

      test('a text sent behind a media message arrives after it', () async {
        await start();
        final flaky = _Flaky();
        final alice = await world.register('alice', aliceNumber, flaky: flaky);
        final bob = await world.register('bob', bobNumber);
        final chat = (await alice.engine.chats.openDirect(bob.account)).id;
        flaky.dropPuts({2});
        await alice.engine.media.sendMedia(chat, [
          MediaInput.bytes(
            bytes: _bytes(200 * 1024),
            kind: MediaItemKind.document,
            mime: 'application/zip',
          ),
        ]);
        await alice.engine.chats.sendText(chat, 'the file is above');
        await _waitForText(bob, alice, 'the file is above');
        final order = [
          for (final m in await _messages(bob, alice))
            if (m.kind == 'media' || m.kind == 'text') m.kind,
        ];
        expect(order, ['media', 'text']);
        // And they were delivered in that order too: the text waited.
        expect(
          flaky.firstPutAt.isBefore(
            (await _messages(bob, alice)).last.receivedAt,
          ),
          isTrue,
        );
      });

      test(
        'a receiver that was offline fetches the file when it syncs',
        () async {
          await start();
          final alice = await world.register('alice', aliceNumber);
          final bob = await world.register(
            'bob',
            bobNumber,
            realtime: false,
            background: false,
          );
          final chat = (await alice.engine.chats.openDirect(bob.account)).id;
          final data = _bytes(100 * 1024, seed: 2);
          await alice.engine.media.sendMedia(chat, [
            MediaInput.bytes(
              bytes: data,
              kind: MediaItemKind.image,
              mime: 'image/jpeg',
            ),
          ]);
          await settle(() async {
            final row = (await _messages(alice, bob)).single;
            expect(row.status, MessageStatus.sent);
          });

          // The headless path (FCM isolate): read the mailbox, then the queue.
          final summary = await bob.engine.syncOnce();
          expect(summary.notices.single.kind, 'media');
          await bob.engine.drainTransfers();
          final att = (await _attachmentsOf(
            bob,
            (await _mediaMessages(bob, alice)).single,
          )).single;
          expect(
            bob.blobs.bytesOf((await bob.engine.media.openLocalPath(att.id))!),
            data,
          );
        },
      );

      test('view-once media is gone after viewing, on both sides', () async {
        await start();
        final alice = await world.register('alice', aliceNumber);
        final bob = await world.register('bob', bobNumber);
        final chat = (await alice.engine.chats.openDirect(bob.account)).id;
        final sent = await alice.engine.media.sendMedia(chat, [
          MediaInput.bytes(
            bytes: _png(40, 40, 3000),
            kind: MediaItemKind.image,
            mime: 'image/png',
          ),
        ], viewOnce: true);
        late MessageRow received;
        await settle(() async {
          final all = await _mediaMessages(bob, alice);
          expect(all, hasLength(1));
          received = all.single;
          expect(
            (await bob.engine.media.viewsOf(received.localRowid)).single.phase,
            TransferPhase.ready,
          );
        });
        await bob.engine.chats.openViewOnce(received.localRowid);
        await bob.engine.media.consumeViewOnce(received.localRowid);
        expect(await _attachmentsOf(bob, received), isEmpty);
        expect(bob.blobs.pathsIn(BlobArea.media), isEmpty);

        // Alice hears "viewed" and drops her copy at the next housekeeping.
        await settle(() async {
          final row = await alice.db.messagesDao.byRowid(sent.localRowid);
          expect(row!.status, MessageStatus.viewed);
        });
        await alice.engine.runMaintenance();
        expect(await _attachmentsOf(alice, sent), isEmpty);
        expect(alice.blobs.pathsIn(BlobArea.media), isEmpty);
      });
    },
  );
}

// ---------------------------------------------------------------- helpers

Future<List<MessageRow>> _messages(_User user, _User peer) async =>
    (await user.db.messagesDao.pageOlder(
      directConversationId(peer.account),
      limit: 200,
    )).messages;

Future<List<MessageRow>> _mediaMessages(_User user, _User peer) async => [
  for (final m in await _messages(user, peer))
    if (m.kind == 'media') m,
];

Future<MessageRow> _waitForText(_User user, _User peer, String text) async {
  late MessageRow found;
  await settle(() async {
    final match = (await _messages(
      user,
      peer,
    )).where((m) => m.body == text && m.deletedAt == null);
    expect(match, isNotEmpty);
    found = match.first;
  });
  return found;
}

Future<List<AttachmentRow>> _attachmentsOf(_User user, MessageRow message) =>
    user.db.messagesDao.attachmentsFor([message.localRowid]);

Uint8List _bytes(int length, {int seed = 1}) => Uint8List.fromList([
  for (var i = 0; i < length; i++) (i * 131 + (i >> 8) * 17 + seed) & 0xFF,
]);

/// Bytes that start like a PNG of the given size.
Uint8List _png(int width, int height, int length) {
  final bytes = _bytes(length, seed: 7);
  bytes.setRange(0, 8, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final view = ByteData.sublistView(bytes);
  view.setUint32(16, width);
  view.setUint32(20, height);
  return bytes;
}

/// A processor that supplies a thumbnail and the blurhash.
final class _Thumbnailer implements MediaProcessor {
  static final thumbnail = Uint8List.fromList([
    0xFF,
    0xD8,
    for (var i = 0; i < 400; i++) (i * 7) & 0xFF,
  ]);

  @override
  Future<ProcessedMedia> process({
    required String path,
    required MediaItemKind kind,
    required String mime,
  }) async => kind == MediaItemKind.image
      ? ProcessedMedia(
          width: 1024,
          height: 768,
          thumbnail: thumbnail,
          blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
        )
      : ProcessedMedia.none;
}

/// Sits between an engine and the server, sees every media request and can
/// kill chosen ones (the connection dies before the server hears of them).
final class _Flaky {
  final List<int> putOffsets = [];
  final List<int> getRanges = [];
  int statusRequests = 0;
  int _puts = 0;
  int _gets = 0;
  Set<int> _dropPuts = {};
  Set<int> _dropGets = {};
  DateTime firstPutAt = DateTime.utc(9999);

  void dropPuts(Set<int> numbers) => _dropPuts = numbers;

  void dropGets(Set<int> numbers) => _dropGets = numbers;

  http.Client wrap(http.Client inner) => _Client(this, inner);
}

final class _Client extends http.BaseClient {
  _Client(this._flaky, this._inner);

  final _Flaky _flaky;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final path = request.url.path;
    if (path.startsWith('/v1/media/') && path.endsWith('/content')) {
      switch (request.method) {
        case 'PUT':
          final number = ++_flaky._puts;
          final offset = int.parse(request.headers['upload-offset'] ?? '0');
          _flaky.putOffsets.add(offset);
          if (_flaky.firstPutAt.year == 9999) {
            _flaky.firstPutAt = DateTime.now().toUtc();
          }
          if (_flaky._dropPuts.remove(number)) {
            throw http.ClientException('connection lost');
          }
        case 'HEAD':
          _flaky.statusRequests++;
        case 'GET':
          final number = ++_flaky._gets;
          final range = RegExp(
            r'bytes=(\d+)-',
          ).firstMatch(request.headers['range'] ?? '');
          _flaky.getRanges.add(range == null ? 0 : int.parse(range.group(1)!));
          if (_flaky._dropGets.remove(number)) {
            throw http.ClientException('connection lost');
          }
      }
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// An engine with a transfer queue, a file store in memory and (optionally)
/// a flaky connection to the server.
final class _User {
  _User(this.name, this.db, this.api, this.engine, this.blobs);

  final String name;
  final HelixDb db;
  final HelixApi api;
  final Engine engine;
  final MemoryBlobStore blobs;

  String get account => engine.accountId!;

  Future<void> dispose() async {
    await engine.close();
    await api.close();
    await db.close();
  }
}

final class _World {
  _World(this.h);

  final Harness h;
  final List<_User> _users = [];

  Future<_User> register(
    String name,
    String number, {
    MediaProcessor? processor,
    _Flaky? flaky,
    bool realtime = true,
    bool background = true,
  }) async {
    final db = HelixDb.inMemory(key: DatabaseKey.generate());
    final inner = http.Client();
    final api = HelixApi(
      baseUrl: h.server.baseUri,
      sessions: DbSessionTokenStore(db),
      clientName: 'engine-media-test/$name',
      httpClient: flaky == null ? inner : flaky.wrap(inner),
      retry: RetryPolicy.none,
    );
    final blobs = MemoryBlobStore();
    final engine = Engine(
      api: api,
      db: db,
      clock: DateTime.now,
      random: SecureCryptoRandom(),
      config: testEngineConfig,
      blobs: blobs,
      mediaProcessor: processor,
      transferConfig: const TransferConfig(
        chunkBytes: 64 * 1024,
        backoff: Backoff(
          initial: Duration(milliseconds: 60),
          max: Duration(milliseconds: 400),
          jitter: 0,
        ),
        sweepGrace: Duration.zero,
        sweepInterval: Duration(minutes: 30),
      ),
    );
    final user = _User(name, db, api, engine, blobs);
    _users.add(user);
    await engine.start(realtime: realtime, background: background);
    final challenge = await engine.account.requestPhoneCode(number);
    final verified = await engine.account.verifyPhone(
      challenge.challengeId,
      h.sms.lastCodeFor(number),
    );
    await engine.account.register(
      verificationToken: verified.verificationToken,
      phoneNumber: number,
    );
    expect(engine.status, EngineStatus.running);
    return user;
  }

  Future<void> dispose() async {
    for (final user in _users.reversed) {
      try {
        await user.dispose();
      } on Object {
        // Already closed.
      }
    }
    _users.clear();
  }
}
