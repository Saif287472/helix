// test/phase0_test.dart
//
// Phase 0 tests: file-transfer receive path, file-ID consistency, and
// capability negotiation.
// Phase 1 tests: identity verification phrase.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:convert/convert.dart' as cvt;
import 'package:crypto/crypto.dart' as pkg_crypto;
import 'package:flutter_test/flutter_test.dart';

import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/core/identity_phrase.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix/providers/controllers/ephemeral_media_service.dart';
import 'package:helix/providers/controllers/file_transfer_service.dart';
import 'package:helix/providers/controllers/messaging_service.dart';
import 'package:helix/providers/controllers/request_service.dart';
import 'package:helix_local_storage/infrastructure/storage/in_memory_connection_request_repository.dart';
import 'package:helix_local_storage/infrastructure/storage/in_memory_ephemeral_media_cache.dart';
import 'package:helix/infrastructure/scheduler/timer_disconnect_wipe_scheduler.dart';
import 'package:helix_local_protocol/protocol/protocol_messages.dart';
import 'package:helix_local_transport/services/transport/secure_channel.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Helpers shared across tests
  // ---------------------------------------------------------------------------

  Future<
    ({
      SecureChannel aliceChannel,
      SecureChannel bobChannel,
      MessagingService aliceMessaging,
      MessagingService bobMessaging,
      ServerSocket server,
    })
  >
  establishChannels([
    MessagingService? aliceMessagingOverride,
    MessagingService? bobMessagingOverride,
  ]) async {
    final aliceIdentity = _generateIdentity();
    final bobIdentity = _generateIdentity();
    const aliceSessionId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const bobSessionId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

    final aliceRequests = RequestService(
      connectionRequestRepository: InMemoryConnectionRequestRepository(),
    )..start();
    final bobRequests = RequestService(
      connectionRequestRepository: InMemoryConnectionRequestRepository(),
    )..start();

    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(bobRequests.handleIncomingTcpConnection);

    final alicePeer = Peer(
      sessionId: bobSessionId,
      displayName: 'Bob',
      deviceSuffix: bobIdentity.deviceSuffix,
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      source: PeerSource.udpBroadcast,
      seenAt: DateTime.now(),
      protocolMajor: kProtocolMajor,
      protocolMinor: kProtocolMinor,
    );

    final bobIncomingRequest = bobRequests.incomingRequests.first.timeout(
      const Duration(seconds: 10),
    );

    final aliceResultFuture = aliceRequests.sendRequest(
      alicePeer,
      RequestSourceMethod.nearby,
      aliceIdentity,
      aliceSessionId,
      'Alice',
    );

    final incoming = await bobIncomingRequest;
    final bobChannelFuture = bobRequests.acceptRequest(
      incoming.requestId,
      bobIdentity,
      bobSessionId,
    );

    final aliceResult = await aliceResultFuture.timeout(
      const Duration(seconds: 15),
    );
    final bobChannel = await bobChannelFuture.timeout(
      const Duration(seconds: 15),
    );

    final aliceMessaging =
        aliceMessagingOverride ??
        MessagingService(wipeScheduler: TimerDisconnectWipeScheduler());
    final bobMessaging =
        bobMessagingOverride ??
        MessagingService(wipeScheduler: TimerDisconnectWipeScheduler());

    aliceMessaging.attachChannel(
      aliceResult.channel!.threadId,
      aliceResult.request.peerDisplayName,
      aliceResult.request.peerDeviceSuffix,
      aliceResult.channel!,
      aliceResult.request.peerSessionId,
      aliceResult.request.peerHost,
      aliceResult.request.peerPort,
    );
    bobMessaging.attachChannel(
      bobChannel!.threadId,
      incoming.peerDisplayName,
      incoming.peerDeviceSuffix,
      bobChannel,
      incoming.peerSessionId,
      incoming.peerHost,
      incoming.peerPort,
    );

    await aliceRequests.close();
    await bobRequests.close();

    return (
      aliceChannel: aliceResult.channel!,
      bobChannel: bobChannel,
      aliceMessaging: aliceMessaging,
      bobMessaging: bobMessaging,
      server: server,
    );
  }

  // ---------------------------------------------------------------------------
  // Task 0.1 — receive-side file transfer
  // ---------------------------------------------------------------------------

  test('Task 0.1: incoming file chunk creates a remote placeholder message on '
      'the receiver and progress is reported', () async {
    final ctx = await establishChannels();

    const fileId = 'test-file-id-001';
    final fileData = Uint8List.fromList(
      List<int>.generate(1024, (i) => i & 0xFF),
    );

    // Wire a handler that just updates progress — avoids path_provider in tests.
    ctx.bobMessaging.setFileChunkHandler((threadId, messageId, frame) async {
      // Simulate partial progress (chunk 0 of 2).
      ctx.bobMessaging.updateTransferProgress(threadId, messageId, 0.5);
    });

    // Watch for Bob's thread to show the placeholder message at 50% progress.
    final bobGotPlaceholder = ctx.bobMessaging.threadChanges
        .where((t) {
          return t.messages.any(
            (m) => m.fileId == fileId && m.transferProgress == 0.5,
          );
        })
        .first
        .timeout(const Duration(seconds: 10));

    // Alice sends a single file chunk directly over the channel.
    await ctx.aliceChannel.sendFileChunk(
      FileTransferFrame(
        fileId: fileId,
        fileName: 'test.bin',
        mimeType: 'application/octet-stream',
        totalSize: fileData.length,
        chunkIndex: 0,
        chunkCount: 2, // pretend there's a second chunk so progress < 1.0
        chunkData: fileData,
      ),
    );

    final thread = await bobGotPlaceholder;
    final msg = thread.messages.firstWhere((m) => m.fileId == fileId);

    expect(
      msg.origin,
      MessageOrigin.remote,
      reason: 'Incoming file message must be remote origin',
    );
    expect(msg.fileName, 'test.bin');
    expect(msg.mimeType, 'application/octet-stream');
    expect(msg.transferProgress, 0.5);

    await ctx.aliceMessaging.dispose();
    await ctx.bobMessaging.dispose();
    await ctx.server.close();
  }, timeout: const Timeout(Duration(seconds: 30)));

  // ---------------------------------------------------------------------------
  // Task 0.2 — file ID consistency
  // ---------------------------------------------------------------------------

  test('Task 0.2: FileTransferService.sendFile uses the caller-supplied fileId '
      'in every outbound frame', () async {
    final ctx = await establishChannels();

    const expectedFileId = 'caller-supplied-file-id';

    // Capture the frames Bob receives.
    final receivedFrames = <FileTransferFrame>[];
    final frameSub = ctx.bobChannel.fileChunkEvents.listen(receivedFrames.add);

    // Bob must respond to the FileProbeFrame with a FileResumeFrame so
    // Alice's sendFile (which now uses kCapFileResume) can proceed.
    final probeSub = ctx.bobChannel.fileProbeEvents.listen((probe) {
      ctx.bobChannel.sendFileResume(
        FileResumeFrame(fileId: probe.fileId, resumeOffset: 0),
      );
    });

    final aliceMessaging = ctx.aliceMessaging;
    final aliceFileTransfer = FileTransferService();

    // Create a tiny temp file to send.
    final tmp = await File(
      '${Directory.systemTemp.path}/ft_test_${DateTime.now().millisecondsSinceEpoch}.bin',
    ).create();
    await tmp.writeAsBytes(List<int>.generate(256, (i) => i & 0xFF));

    final messageId = aliceMessaging.addFileMessage(
      threadId: ctx.aliceChannel.threadId,
      origin: MessageOrigin.local,
      fileId: expectedFileId,
      fileName: 'ft_test.bin',
      mimeType: 'application/octet-stream',
      fileSize: 256,
      localFilePath: tmp.path,
    );
    expect(messageId, isNotEmpty);

    await aliceFileTransfer.sendFile(
      threadId: ctx.aliceChannel.threadId,
      messageId: messageId,
      fileId: expectedFileId,
      file: tmp,
      mimeType: 'application/octet-stream',
      channel: ctx.aliceChannel,
    );

    // Give frames a moment to arrive.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await frameSub.cancel();
    await probeSub.cancel();

    expect(receivedFrames, isNotEmpty);
    for (final frame in receivedFrames) {
      expect(
        frame.fileId,
        expectedFileId,
        reason: 'Every wire frame must carry the caller-supplied fileId',
      );
    }

    await tmp.delete();
    await ctx.aliceMessaging.dispose();
    await ctx.bobMessaging.dispose();
    await ctx.server.close();
  }, timeout: const Timeout(Duration(seconds: 30)));

  // ---------------------------------------------------------------------------
  // Task 0.3 — capability negotiation
  // ---------------------------------------------------------------------------

  test('Task 0.3: negotiatedCapabilities is the intersection of both peers\' '
      'capability bitmasks after handshake', () async {
    final ctx = await establishChannels();

    // Both peers advertise kCapAll. The intersection is also kCapAll.
    expect(
      ctx.aliceChannel.negotiatedCapabilities,
      kCapAll,
      reason: 'Alice negotiated full capability set',
    );
    expect(
      ctx.bobChannel.negotiatedCapabilities,
      kCapAll,
      reason: 'Bob negotiated full capability set',
    );

    // Spot-check individual flags.
    expect(ctx.aliceChannel.supportsCapability(kCapFileTransfer), isTrue);
    expect(ctx.aliceChannel.supportsCapability(kCapReactions), isTrue);
    expect(
      ctx.aliceChannel.supportsCapability(kCapForwardSecrecy),
      isFalse,
      reason:
          'Forward secrecy must not be advertised until independently verified',
    );

    // Phase 3.3 flag is now in kCapAll.
    expect(ctx.aliceChannel.supportsCapability(kCapFileResume), isTrue);

    // Phase 3.4 flag is now in kCapAll.
    expect(ctx.aliceChannel.supportsCapability(kCapEphemeralMedia), isTrue);

    // Phase 4 group support is now advertised.
    expect(ctx.aliceChannel.supportsCapability(kCapGroups), isTrue);

    // Stage 6: kCapWebRTC is now in kCapAll and is negotiated.
    expect(ctx.aliceChannel.supportsCapability(kCapWebRTC), isTrue);

    await ctx.aliceMessaging.dispose();
    await ctx.bobMessaging.dispose();
    await ctx.server.close();
  }, timeout: const Timeout(Duration(seconds: 30)));

  // ---------------------------------------------------------------------------
  // Task 1.2 — identity verification phrase
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Task 2.2 — per-thread auto-wipe after unexpected disconnect
  // ---------------------------------------------------------------------------

  group('Task 2.2: per-thread auto-wipe', () {
    test('wipeThread removes thread and notifies listeners', () async {
      final messaging = MessagingService(
        autoWipeDelay: const Duration(milliseconds: 50),
        wipeScheduler: TimerDisconnectWipeScheduler(),
      );

      // Seed a thread directly via createThread.
      messaging.createThread('fp1234', 'Alice', 'fp12', '', '10.0.0.1', 9000);
      expect(messaging.threads.containsKey('fp1234'), isTrue);

      messaging.wipeThread('fp1234');
      expect(messaging.threads.containsKey('fp1234'), isFalse);

      await messaging.dispose();
    });

    test(
      'auto-wipe timer fires after unexpected disconnect and removes thread',
      () async {
        final ctx = await establishChannels(
          MessagingService(
            autoWipeDelay: const Duration(milliseconds: 100),
            wipeScheduler: TimerDisconnectWipeScheduler(),
          ),
          MessagingService(
            autoWipeDelay: const Duration(milliseconds: 100),
            wipeScheduler: TimerDisconnectWipeScheduler(),
          ),
        );

        final threadId = ctx.aliceChannel.threadId;
        expect(ctx.aliceMessaging.threads.containsKey(threadId), isTrue);

        // Force an unexpected disconnect (close the channel directly, not via endConnection).
        await ctx.aliceChannel.close();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Thread still present immediately after disconnect.
        expect(ctx.aliceMessaging.threads.containsKey(threadId), isTrue);

        // After wipe delay the thread is gone.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(ctx.aliceMessaging.threads.containsKey(threadId), isFalse);

        await ctx.bobMessaging.dispose();
        await ctx.server.close();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'reconnect cancels the auto-wipe timer',
      () async {
        final ctx = await establishChannels(
          MessagingService(
            autoWipeDelay: const Duration(milliseconds: 100),
            wipeScheduler: TimerDisconnectWipeScheduler(),
          ),
          MessagingService(
            autoWipeDelay: const Duration(milliseconds: 100),
            wipeScheduler: TimerDisconnectWipeScheduler(),
          ),
        );

        final threadId = ctx.aliceChannel.threadId;

        // Detach manually (simulates unexpected disconnect) by calling detachChannel directly.
        ctx.aliceMessaging.detachChannel(threadId);
        expect(ctx.aliceMessaging.threads.containsKey(threadId), isTrue);

        // Re-attach before the timer fires — cancels the wipe timer.
        ctx.aliceMessaging.attachChannel(
          threadId,
          'bob',
          threadId.substring(0, 4),
          FakeSecureChannel(threadId),
          'sess1',
          '127.0.0.1',
          9001,
        );

        // Wait past the wipe delay — thread should still be there because timer was cancelled.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(
          ctx.aliceMessaging.threads.containsKey(threadId),
          isTrue,
          reason: 'Reconnect must cancel the auto-wipe timer',
        );

        await ctx.aliceMessaging.dispose();
        await ctx.bobMessaging.dispose();
        await ctx.server.close();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });

  // ---------------------------------------------------------------------------
  // Task 3.3 — probe/resume/complete/cancel protocol frames
  // ---------------------------------------------------------------------------

  group('Task 3.3: file transfer probe/resume/complete/cancel', () {
    test(
      'FileProbeFrame round-trips through protocol_messages encode/decode',
      () {
        final frame = FileProbeFrame(
          fileId: 'id-001',
          fileName: 'hello.txt',
          mimeType: 'text/plain',
          totalSize: 1234,
          sha256: 'abcdef' * 10 + 'abcd',
        );
        final encoded = frame.encode();
        final decoded = ProtocolFrame.decode(encoded) as FileProbeFrame;
        expect(decoded.fileId, frame.fileId);
        expect(decoded.fileName, frame.fileName);
        expect(decoded.mimeType, frame.mimeType);
        expect(decoded.totalSize, frame.totalSize);
        expect(decoded.sha256, frame.sha256);
      },
    );

    test(
      'FileResumeFrame round-trips through protocol_messages encode/decode',
      () {
        final frame = FileResumeFrame(fileId: 'id-002', resumeOffset: 65536);
        final decoded = ProtocolFrame.decode(frame.encode()) as FileResumeFrame;
        expect(decoded.fileId, frame.fileId);
        expect(decoded.resumeOffset, frame.resumeOffset);
      },
    );

    test(
      'FileCompleteFrame round-trips through protocol_messages encode/decode',
      () {
        final frame = FileCompleteFrame(fileId: 'id-003', sha256: 'ff' * 32);
        final decoded =
            ProtocolFrame.decode(frame.encode()) as FileCompleteFrame;
        expect(decoded.fileId, frame.fileId);
        expect(decoded.sha256, frame.sha256);
      },
    );

    test(
      'FileCancelFrame round-trips through protocol_messages encode/decode',
      () {
        final frame = FileCancelFrame(fileId: 'id-004', reason: 'user-cancel');
        final decoded = ProtocolFrame.decode(frame.encode()) as FileCancelFrame;
        expect(decoded.fileId, frame.fileId);
        expect(decoded.reason, frame.reason);
      },
    );

    test(
      'FileProbeFrame sent by Alice arrives on Bob\'s fileProbeEvents stream',
      () async {
        final ctx = await establishChannels();

        final probeCompleter = Completer<FileProbeFrame>();
        final sub = ctx.bobChannel.fileProbeEvents.listen(
          probeCompleter.complete,
        );

        await ctx.aliceChannel.sendFileProbe(
          FileProbeFrame(
            fileId: 'probe-test-id',
            fileName: 'test.dat',
            mimeType: 'application/octet-stream',
            totalSize: 512,
            sha256: 'aa' * 32,
          ),
        );

        final received = await probeCompleter.future.timeout(
          const Duration(seconds: 10),
        );
        expect(received.fileId, 'probe-test-id');
        expect(received.totalSize, 512);

        await sub.cancel();
        await ctx.aliceMessaging.dispose();
        await ctx.bobMessaging.dispose();
        await ctx.server.close();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'probe/resume handshake: Alice probes, Bob replies, Alice receives resume offset',
      () async {
        final ctx = await establishChannels();

        // Bob echoes a FileResumeFrame when he receives the probe.
        final bobProbeSub = ctx.bobChannel.fileProbeEvents.listen((probe) {
          ctx.bobChannel.sendFileResume(
            FileResumeFrame(fileId: probe.fileId, resumeOffset: 0),
          );
        });

        final resumeCompleter = Completer<FileResumeFrame>();
        final aliceResumeSub = ctx.aliceChannel.fileResumeEvents.listen(
          resumeCompleter.complete,
        );

        await ctx.aliceChannel.sendFileProbe(
          FileProbeFrame(
            fileId: 'handshake-id',
            fileName: 'big.bin',
            mimeType: 'application/octet-stream',
            totalSize: 128 * 1024,
            sha256: 'bb' * 32,
          ),
        );

        final resume = await resumeCompleter.future.timeout(
          const Duration(seconds: 10),
        );
        expect(resume.fileId, 'handshake-id');
        expect(resume.resumeOffset, 0);

        await bobProbeSub.cancel();
        await aliceResumeSub.cancel();
        await ctx.aliceMessaging.dispose();
        await ctx.bobMessaging.dispose();
        await ctx.server.close();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'sendFile resumes from the receiver-provided chunk offset',
      () async {
        final ctx = await establishChannels();

        const fileId = 'resume-offset-id';
        final receivedFrames = <FileTransferFrame>[];
        final frameSub = ctx.bobChannel.fileChunkEvents.listen(
          receivedFrames.add,
        );
        final probeSub = ctx.bobChannel.fileProbeEvents.listen((probe) {
          ctx.bobChannel.sendFileResume(
            FileResumeFrame(fileId: probe.fileId, resumeOffset: kFileChunkSize),
          );
        });

        final tmp = await File(
          '${Directory.systemTemp.path}/ft_resume_${DateTime.now().millisecondsSinceEpoch}.bin',
        ).create();
        await tmp.writeAsBytes(
          List<int>.generate(kFileChunkSize * 2 + 128, (i) => i & 0xFF),
        );

        final messageId = ctx.aliceMessaging.addFileMessage(
          threadId: ctx.aliceChannel.threadId,
          origin: MessageOrigin.local,
          fileId: fileId,
          fileName: 'resume.bin',
          mimeType: 'application/octet-stream',
          fileSize: await tmp.length(),
          localFilePath: tmp.path,
        );
        expect(messageId, isNotEmpty);

        await FileTransferService().sendFile(
          threadId: ctx.aliceChannel.threadId,
          messageId: messageId,
          fileId: fileId,
          file: tmp,
          mimeType: 'application/octet-stream',
          channel: ctx.aliceChannel,
        );

        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(receivedFrames, isNotEmpty);
        expect(
          receivedFrames.first.chunkIndex,
          1,
          reason: 'Sender must skip chunks already reported by receiver',
        );
        expect(receivedFrames.every((frame) => frame.fileId == fileId), isTrue);

        await frameSub.cancel();
        await probeSub.cancel();
        await tmp.delete();
        await ctx.aliceMessaging.dispose();
        await ctx.bobMessaging.dispose();
        await ctx.server.close();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'FileCompleteFrame and FileCancelFrame are routed to their streams',
      () async {
        final ctx = await establishChannels();

        final completeFuture = ctx.bobChannel.fileCompleteEvents.first.timeout(
          const Duration(seconds: 10),
        );
        final cancelFuture = ctx.aliceChannel.fileCancelEvents.first.timeout(
          const Duration(seconds: 10),
        );

        await ctx.aliceChannel.sendFileComplete(
          FileCompleteFrame(fileId: 'done-id', sha256: 'cc' * 32),
        );
        await ctx.bobChannel.sendFileCancel(
          FileCancelFrame(fileId: 'abort-id', reason: 'test'),
        );

        final complete = await completeFuture;
        expect(complete.fileId, 'done-id');

        final cancel = await cancelFuture;
        expect(cancel.fileId, 'abort-id');
        expect(cancel.reason, 'test');

        await ctx.aliceMessaging.dispose();
        await ctx.bobMessaging.dispose();
        await ctx.server.close();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'FileCancelFrame invokes the cancel handler even without a prior file mapping',
      () async {
        final ctx = await establishChannels();
        final cancelCompleter = Completer<String>();

        ctx.aliceMessaging.setFileCancelHandler((threadId, fileId) async {
          cancelCompleter.complete(fileId);
        });

        await ctx.bobChannel.sendFileCancel(
          FileCancelFrame(fileId: 'unknown-cancel-id', reason: 'test'),
        );

        await expectLater(
          cancelCompleter.future.timeout(const Duration(seconds: 10)),
          completion('unknown-cancel-id'),
        );

        await ctx.aliceMessaging.dispose();
        await ctx.bobMessaging.dispose();
        await ctx.server.close();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });

  group('Task 3.4: ephemeral media assembly', () {
    test('reassembles valid chunks and keeps bytes in RAM', () {
      final service = EphemeralMediaService(
        cache: InMemoryEphemeralMediaCache(),
      );
      final first = Uint8List.fromList([1, 2, 3]);
      final second = Uint8List.fromList([4, 5]);

      final partial = service.receiveChunk(
        EphemeralMediaFrame(
          mediaId: 'media-001',
          mimeType: 'image/jpeg',
          totalSize: 5,
          chunkIndex: 0,
          chunkCount: 2,
          chunkData: first,
        ),
      );
      expect(partial, isNull);

      final complete = service.receiveChunk(
        EphemeralMediaFrame(
          mediaId: 'media-001',
          mimeType: 'image/jpeg',
          totalSize: 5,
          chunkIndex: 1,
          chunkCount: 2,
          chunkData: second,
        ),
      );

      expect(complete, [1, 2, 3, 4, 5]);
      expect(service.getMedia('media-001'), [1, 2, 3, 4, 5]);
    });

    test('rejects malformed chunk metadata without caching bytes', () {
      final service = EphemeralMediaService(
        cache: InMemoryEphemeralMediaCache(),
      );

      final complete = service.receiveChunk(
        EphemeralMediaFrame(
          mediaId: 'media-bad',
          mimeType: 'image/jpeg',
          totalSize: 5,
          chunkIndex: 0,
          chunkCount: 0,
          chunkData: Uint8List.fromList([1, 2, 3]),
        ),
      );

      expect(complete, isNull);
      expect(service.hasMedia('media-bad'), isFalse);
    });
  });

  group('Task 1.2: buildVerificationPhrase', () {
    const fp1 = 'aabbccdd11223344aabbccdd11223344';
    const fp2 = '5566778899aabbcc5566778899aabbcc';

    test('produces a non-empty 6-word phrase', () {
      final phrase = buildVerificationPhrase(fp1, fp2);
      final words = phrase.split(' ');
      expect(words.length, 6, reason: 'phrase must be exactly 6 words');
      for (final w in words) {
        expect(w, isNotEmpty);
      }
    });

    test('is symmetric — order of fp1/fp2 does not matter', () {
      expect(
        buildVerificationPhrase(fp1, fp2),
        equals(buildVerificationPhrase(fp2, fp1)),
        reason:
            'both peers must derive the same phrase regardless of argument order',
      );
    });

    test('changes completely when one fingerprint changes', () {
      const fp1b = 'aabbccdd11223344aabbccdd11223345'; // last nibble differs
      expect(
        buildVerificationPhrase(fp1, fp2),
        isNot(equals(buildVerificationPhrase(fp1b, fp2))),
        reason:
            'a single-nibble fingerprint change must produce a different phrase',
      );
    });

    test('same inputs always produce same phrase (deterministic)', () {
      expect(
        buildVerificationPhrase(fp1, fp2),
        equals(buildVerificationPhrase(fp1, fp2)),
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Identity generation helper (same as integration test)
// ---------------------------------------------------------------------------

DeviceIdentity _generateIdentity() {
  final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final privateKey = keyPair.privateKey as RSAPrivateKey;
  final publicKey = keyPair.publicKey as RSAPublicKey;
  final csrPem = X509Utils.generateRsaCsrPem(
    {'CN': 'Helix Test Device'},
    privateKey,
    publicKey,
  );
  final certPem = X509Utils.generateSelfSignedCertificate(
    privateKey,
    csrPem,
    365,
  );
  final privateKeyPem = CryptoUtils.encodeRSAPrivateKeyToPem(privateKey);
  final digest = pkg_crypto.sha256.convert(_modulusBytes(publicKey));
  final fingerprintHex = cvt.hex.encode(digest.bytes);

  return DeviceIdentity(
    certPem: certPem,
    privateKeyPem: privateKeyPem,
    staticPublicKeyFingerprint: fingerprintHex.substring(0, 32),
    deviceSuffix: fingerprintHex.substring(0, 4),
  );
}

Uint8List _modulusBytes(RSAPublicKey key) {
  final hex = key.modulus!.toRadixString(16);
  final padded = hex.length.isOdd ? '0$hex' : hex;
  return Uint8List.fromList(
    List.generate(
      padded.length ~/ 2,
      (i) => int.parse(padded.substring(i * 2, i * 2 + 2), radix: 16),
    ),
  );
}

class FakeSecureChannel extends Fake implements SecureChannel {
  FakeSecureChannel(this.threadId);

  @override
  final String threadId;

  @override
  Stream<ChatMessageFrame> get messages =>
      StreamController<ChatMessageFrame>().stream;

  @override
  Stream<ChannelState> get stateChanges =>
      StreamController<ChannelState>().stream;

  @override
  Stream<bool> get typingEvents => StreamController<bool>().stream;

  @override
  Stream<List<String>> get receiptEvents =>
      StreamController<List<String>>().stream;

  @override
  Stream<ReactionFrame> get reactionEvents =>
      StreamController<ReactionFrame>().stream;

  @override
  Stream<EditMessageFrame> get editEvents =>
      StreamController<EditMessageFrame>().stream;

  @override
  Stream<DeleteMessageFrame> get deleteEvents =>
      StreamController<DeleteMessageFrame>().stream;

  @override
  Stream<WipeFrame> get wipeEvents => StreamController<WipeFrame>().stream;

  @override
  Stream<FileTransferFrame> get fileChunkEvents =>
      StreamController<FileTransferFrame>().stream;

  @override
  Stream<FileProbeFrame> get fileProbeEvents =>
      StreamController<FileProbeFrame>().stream;

  @override
  Stream<FileCompleteFrame> get fileCompleteEvents =>
      StreamController<FileCompleteFrame>().stream;

  @override
  Stream<FileCancelFrame> get fileCancelEvents =>
      StreamController<FileCancelFrame>().stream;

  @override
  Stream<EphemeralMediaFrame> get ephemeralMediaEvents =>
      StreamController<EphemeralMediaFrame>().stream;

  @override
  Stream<GroupControlFrame> get groupControlEvents =>
      StreamController<GroupControlFrame>().stream;

  @override
  Stream<GroupMessageFrame> get groupMessageEvents =>
      StreamController<GroupMessageFrame>().stream;

  @override
  Stream<CallSignalFrame> get callSignalEvents =>
      StreamController<CallSignalFrame>().stream;

  @override
  Future<void> close() async {}
}
