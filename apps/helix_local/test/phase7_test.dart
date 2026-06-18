import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:helix/application/diagnostics/diagnostics_use_case_impl.dart';
import 'package:helix/application/trust/trust_use_case_impl.dart';
import 'package:helix/providers/controllers/group_service.dart';
import 'package:helix_local_calls/services/call_service.dart';
import 'package:helix_local_crypto/crypto/session_key_derivation.dart';
import 'package:helix_local_domain/application/contracts/repositories.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/domain/call/call_state.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix_local_protocol/application/contracts/gateways.dart';
import 'package:helix_local_protocol/protocol/protocol_messages.dart';
import 'package:helix_local_storage/infrastructure/storage/in_memory_group_repository.dart';
import 'package:helix_local_storage/infrastructure/storage/in_memory_transfer_repository.dart';
import 'package:helix_local_transfer/application/receive_file_coordinator_impl.dart';
import 'package:helix_local_transport/services/transport/frame_io.dart';

void main() {
  group('P7-001/P7-002: security claim and key-agreement review', () {
    test('forward secrecy is reserved but not advertised', () {
      expect(kCapForwardSecrecy, isNot(0));
      expect(
        kCapAll & kCapForwardSecrecy,
        equals(0),
        reason: 'Do not advertise forward secrecy until external review.',
      );
    });

    test(
      'chain keys are bound to both peer public keys and session IDs',
      () async {
        final baseline = await deriveDirectionalChainKeys(
          localSessionId: 'alice-session',
          peerSessionId: 'bob-session',
          localPublicKeyDer: Uint8List.fromList([1, 2, 3, 4]),
          peerPublicKeyDer: Uint8List.fromList([5, 6, 7, 8]),
        );
        final changedPeerKey = await deriveDirectionalChainKeys(
          localSessionId: 'alice-session',
          peerSessionId: 'bob-session',
          localPublicKeyDer: Uint8List.fromList([1, 2, 3, 4]),
          peerPublicKeyDer: Uint8List.fromList([5, 6, 7, 9]),
        );
        final changedSession = await deriveDirectionalChainKeys(
          localSessionId: 'alice-session-2',
          peerSessionId: 'bob-session',
          localPublicKeyDer: Uint8List.fromList([1, 2, 3, 4]),
          peerPublicKeyDer: Uint8List.fromList([5, 6, 7, 8]),
        );

        expect(
          await baseline.sendChainKey.extractBytes(),
          isNot(await changedPeerKey.sendChainKey.extractBytes()),
        );
        expect(
          await baseline.sendChainKey.extractBytes(),
          isNot(await changedSession.sendChainKey.extractBytes()),
        );
      },
    );
  });

  group('P7-003/P7-004: protocol decoder hardening', () {
    test('all current frame classes round-trip through public decoder', () {
      for (final frame in _allFrames()) {
        final encoded = frame.encode();
        expect(encoded.length, lessThanOrEqualTo(kMaxFrameBytes));
        expect(ProtocolFrame.decode(encoded).type, frame.type);
      }
    });

    test('malformed CBOR and bad field types are rejected', () {
      final malformedPayloads = <Uint8List>[
        Uint8List(0),
        Uint8List.fromList([0xff]),
        _cborMap({1: 'missing-type'}),
        _cborMap({0: 0x7fffffff}),
        _cborMap({0: kTypeChatMessage, 1: 'm1', 2: 42, 3: 1}),
        _cborMap({0: kTypeFileTransfer, 1: '../escape'}),
        _cborMap({0: kTypeReadReceipt, 1: 'not-a-list'}),
      ];

      for (final payload in malformedPayloads) {
        expect(() => ProtocolFrame.decode(payload), throwsA(anything));
      }
    });

    test('raw oversized protocol payload is rejected before CBOR parse', () {
      expect(
        () => ProtocolFrame.decode(Uint8List(kMaxFrameBytes + 1)),
        throwsA(isA<FrameTooLargeException>()),
      );
    });

    test(
      'length-prefixed reader rejects zero, oversized, and truncated frames',
      () async {
        await expectLater(
          readFrame(Stream.value(Uint8List(kFrameLengthPrefixBytes))),
          throwsA(isA<ProtocolException>()),
        );

        final oversizedPrefix = ByteData(kFrameLengthPrefixBytes)
          ..setUint32(0, kMaxFrameBytes + 1, Endian.big);
        await expectLater(
          readFrame(Stream.value(oversizedPrefix.buffer.asUint8List())),
          throwsA(isA<FrameTooLargeException>()),
        );

        final truncated = BytesBuilder()
          ..add(
            (ByteData(
              kFrameLengthPrefixBytes,
            )..setUint32(0, 8, Endian.big)).buffer.asUint8List(),
          )
          ..add(Uint8List.fromList([1, 2, 3]));
        await expectLater(
          readFrame(Stream.value(truncated.toBytes())),
          throwsA(isA<ProtocolException>()),
        );
      },
    );
  });

  group('P7-005: LAN impersonation and fingerprint changes', () {
    test(
      'trusted nickname with changed fingerprint is flagged; untrusted is not',
      () async {
        final repo = _MemoryTrustRepository();
        final trust = TrustUseCaseImpl(repository: repo);
        await trust.init();

        await trust.markKnown('fp-old', 'Alice', 'a1', '10.0.0.2', 9000);
        await trust.trustPeer('fp-old', 'Alice');
        await trust.markKnown('fp-new', 'Alice', 'a2', '10.0.0.3', 9001);

        expect(
          trust.detectImpersonation('fp-new', 'Alice')?.fingerprint,
          'fp-old',
        );
        expect(trust.detectImpersonation('fp-new', 'Mallory'), isNull);

        await trust.untrustPeer('fp-old');
        expect(trust.detectImpersonation('fp-new', 'Alice'), isNull);
        trust.dispose();
      },
    );
  });

  group('P7-006: file resume/hash/cancel races', () {
    test(
      'hash mismatch removes unsafe partial output and transfer state',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'helix_p7_transfer_',
        );
        addTearDown(() async {
          if (await temp.exists()) await temp.delete(recursive: true);
        });

        final repo = InMemoryTransferRepository();
        final coordinator = ReceiveFileCoordinatorImpl(
          repository: repo,
          onProgressUpdate: (_, _, _, {localFilePath}) {},
          getCacheDirectory: () async => temp,
        );
        final gateway = _RecordingTransferGateway();
        const fileId = 'race-file';
        final bytes = Uint8List.fromList(List<int>.generate(128, (i) => i));

        await coordinator.receiveProbe(
          threadId: 't',
          messageId: 'm',
          frame: FileProbeFrame(
            fileId: fileId,
            fileName: 'race.bin',
            mimeType: 'application/octet-stream',
            totalSize: bytes.length,
            sha256: '',
          ),
          gateway: gateway,
        );
        expect(gateway.resumes.single.resumeOffset, 0);

        await coordinator.receiveChunk(
          threadId: 't',
          messageId: 'm',
          frame: FileTransferFrame(
            fileId: fileId,
            fileName: 'race.bin',
            mimeType: 'application/octet-stream',
            totalSize: bytes.length,
            chunkIndex: 0,
            chunkCount: 1,
            chunkData: bytes,
          ),
        );

        await Future.wait([
          coordinator.receiveComplete(
            threadId: 't',
            messageId: 'm',
            fileId: fileId,
            expectedSha256: '00' * 32,
          ),
          coordinator.cancelTransfer(fileId),
        ]);

        expect(repo.loadTransfer(fileId), isNull);
        expect(
          File(
            '${temp.path}${Platform.pathSeparator}transfers'
            '${Platform.pathSeparator}$fileId.part',
          ).existsSync(),
          isFalse,
        );
        await coordinator.dispose();
      },
    );

    test('resume offset only advances to full verified chunks', () async {
      final temp = await Directory.systemTemp.createTemp('helix_p7_resume_');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });

      final partialDir = Directory(
        '${temp.path}${Platform.pathSeparator}transfers',
      );
      await partialDir.create(recursive: true);
      final partial = File(
        '${partialDir.path}${Platform.pathSeparator}resume-id.part',
      );
      await partial.writeAsBytes(Uint8List(kFileChunkSize + 17));

      final gateway = _RecordingTransferGateway();
      final coordinator = ReceiveFileCoordinatorImpl(
        repository: InMemoryTransferRepository(),
        onProgressUpdate: (_, _, _, {localFilePath}) {},
        getCacheDirectory: () async => temp,
      );

      await coordinator.receiveProbe(
        threadId: 't',
        messageId: 'm',
        frame: FileProbeFrame(
          fileId: 'resume-id',
          fileName: 'resume.bin',
          mimeType: 'application/octet-stream',
          totalSize: kFileChunkSize * 2,
          sha256: '',
        ),
        gateway: gateway,
      );

      expect(gateway.resumes.single.resumeOffset, kFileChunkSize);
      await coordinator.dispose();
    });
  });

  group('P7-007: three-device group election', () {
    test(
      'three public lobby hosts converge on lexicographically lowest fingerprint',
      () async {
        final repoA = InMemoryGroupRepository();
        final repoB = InMemoryGroupRepository();
        final repoC = InMemoryGroupRepository();
        final serviceA = _groupService(repoA, 'alice');
        final serviceB = _groupService(repoB, 'bob');
        final serviceC = _groupService(repoC, 'charlie');

        await serviceA.createPublicLobby();
        await serviceB.createPublicLobby();
        await serviceC.createPublicLobby();

        final aliceAnnouncement = serviceA.buildHostAnnouncement(
          GroupService.publicLobbyId,
        );
        expect(serviceB.applyControlFrame(aliceAnnouncement), isTrue);
        expect(serviceC.applyControlFrame(aliceAnnouncement), isTrue);

        expect(
          repoA.loadGroup(GroupService.publicLobbyId)!.hostFingerprint,
          'alice',
        );
        expect(
          repoB.loadGroup(GroupService.publicLobbyId)!.hostFingerprint,
          'alice',
        );
        expect(
          repoC.loadGroup(GroupService.publicLobbyId)!.hostFingerprint,
          'alice',
        );
      },
    );
  });

  group('P7-008/P7-009: call state regressions', () {
    test(
      'camera switch is delegated without mutating active call state',
      () async {
        final engine = _MockCallEngine();
        final gateway = _MockCallGateway();
        final calls = CallService(engine: engine, signalingGateway: gateway);
        addTearDown(calls.dispose);

        await calls.initiateVideoCall('peer-1', 'Alice');
        final callId = calls.currentCall!.callId;
        engine.emitConnected(callId);
        await Future<void>.delayed(Duration.zero);

        await calls.switchCamera();

        expect(engine.log, contains('switchCamera:$callId'));
        expect(calls.currentCall?.status, CallStatus.active);
        expect(calls.currentCall?.isVideoEnabled, isTrue);
      },
    );
  });

  group('P7-010/P7-011: offline and diagnostics behavior', () {
    test(
      'diagnostics remain usable without internet-facing network data',
      () async {
        final diagnostics = DiagnosticsUseCaseImpl(
          gateway: _FakeDiagnosticsGateway(
            interfaceType: 'none',
            localIp: null,
            networkName: null,
          ),
        );

        diagnostics.recordBindError('udp bind failed');
        final result = await diagnostics.getDiagnostics(
          tcpPort: 42424,
          tcpActive: false,
          mdnsActive: false,
          udpActive: false,
        );

        expect(result.interfaceType, 'none');
        expect(result.protocolVersion, '$kProtocolMajor.$kProtocolMinor');
        expect(result.mdnsAvailable, isFalse);
        expect(result.udpBroadcastAvailable, isFalse);
        if (Platform.isWindows) {
          expect(result.firewallNote, contains('Windows Firewall'));
        }
      },
    );
  });

  group('P7-012 through P7-020: release gates', () {
    test('release hardening artifacts exist and claims are documented', () {
      final root = _findRepoRoot();
      for (final path in const [
        'docs/security/AUTHENTICATED_KEY_AGREEMENT_REVIEW.md',
        'docs/security/EXTERNAL_SECURITY_REVIEW_GATE.md',
        'docs/release/LOCAL_RELEASE_CHECKLIST.md',
        'docs/release/LOCAL_PRIVACY_VERIFICATION_CHECKLIST.md',
        'docs/release/LOCAL_RELEASE_ROLLBACK_PLAN.md',
        'docs/release/LOCAL_SBOM_DEPENDENCY_AUDIT.md',
        'scripts/local_release_gate.ps1',
        'tool/check_release_hardening.dart',
        'tool/generate_local_sbom.dart',
      ]) {
        expect(
          File('${root.path}${Platform.pathSeparator}$path').existsSync(),
          isTrue,
        );
      }
    });

    test('Android release signing is fail-closed and product scoped', () {
      final root = _findRepoRoot();
      final gradle = File(
        '${root.path}${Platform.pathSeparator}apps'
        '${Platform.pathSeparator}helix_local'
        '${Platform.pathSeparator}android'
        '${Platform.pathSeparator}app'
        '${Platform.pathSeparator}build.gradle.kts',
      ).readAsStringSync();

      expect(gradle, contains('HELIX_LOCAL_STORE_PASSWORD'));
      expect(gradle, contains('HELIX_LOCAL_KEY_ALIAS'));
      expect(gradle, contains('HELIX_LOCAL_KEY_PASSWORD'));
      expect(gradle, contains('Debug signing is forbidden'));
      expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    });
  });
}

List<ProtocolFrame> _allFrames() => [
  RequestFrame(
    requestId: 'req-1',
    displayName: 'Alice',
    deviceSuffix: 'a1',
    sessionId: 's' * 32,
    staticKeyFingerprint: 'a' * 32,
    protocolMajor: kProtocolMajor,
    protocolMinor: kProtocolMinor,
    port: 42424,
    expiresAt: 1,
  ),
  AcceptFrame(requestId: 'req-1', connectPort: 42425),
  RejectFrame(requestId: 'req-1', reason: 'denied'),
  CancelFrame(requestId: 'req-1'),
  IdentityFrame(
    staticPublicKeyDer: Uint8List.fromList([1, 2, 3]),
    signature: Uint8List.fromList([4, 5, 6]),
    sessionId: 's' * 32,
  ),
  IdentityAckFrame(ok: true, sessionId: 's' * 32),
  CapabilityFrame(
    major: kProtocolMajor,
    minor: kProtocolMinor,
    features: const ['baseline'],
    capabilities: kCapAll,
  ),
  ChatMessageFrame(messageId: 'm1', text: 'hello', timestamp: 1),
  ChatAckFrame(messageId: 'm1', ok: true),
  KeepaliveFrame(counter: 1),
  CloseFrame(reason: 'normal'),
  ProfileUpdateFrame(newDisplayName: 'Alice 2'),
  BusyFrame(),
  VersionMismatchFrame(ourMajor: kProtocolMajor, ourMinor: kProtocolMinor),
  TypingIndicatorFrame(isTyping: true),
  ReadReceiptFrame(messageIds: const ['m1']),
  ReactionFrame(messageId: 'm1', emoji: '+1', remove: false),
  FileTransferFrame(
    fileId: 'file-1',
    fileName: 'file.bin',
    mimeType: 'application/octet-stream',
    totalSize: 3,
    chunkIndex: 0,
    chunkCount: 1,
    chunkData: Uint8List.fromList([1, 2, 3]),
  ),
  EditMessageFrame(messageId: 'm1', newText: 'updated', editedAt: 2),
  DeleteMessageFrame(messageId: 'm1'),
  WipeFrame(),
  FileProbeFrame(
    fileId: 'file-2',
    fileName: 'file.bin',
    mimeType: 'application/octet-stream',
    totalSize: 3,
    sha256: crypto.sha256.convert([1, 2, 3]).toString(),
  ),
  FileResumeFrame(fileId: 'file-2', resumeOffset: 0),
  FileCompleteFrame(
    fileId: 'file-2',
    sha256: crypto.sha256.convert([1, 2, 3]).toString(),
  ),
  FileCancelFrame(fileId: 'file-2', reason: 'user-cancel'),
  EphemeralMediaFrame(
    mediaId: 'media-1',
    mimeType: 'image/jpeg',
    totalSize: 3,
    chunkIndex: 0,
    chunkCount: 1,
    chunkData: Uint8List.fromList([1, 2, 3]),
  ),
  GroupControlFrame(
    groupId: 'g1',
    eventId: 'e1',
    command: GroupCommands.hostAnnounce,
    senderFingerprint: 'alice',
    hostFingerprint: 'alice',
    hostEndpoint: '127.0.0.1:4001',
    epoch: 1,
    membershipVersion: 1,
  ),
  GroupMessageFrame(
    groupId: 'g1',
    messageId: 'gm1',
    senderFingerprint: 'alice',
    epoch: 1,
    membershipVersion: 1,
    sentAt: 1,
    encryptedPayload: Uint8List.fromList([1, 2, 3]),
  ),
  CallSignalFrame(
    callId: 'call-1',
    signalType: 'ice',
    candidate: 'candidate:1 1 udp 2122260223 192.168.1.2 5000 typ host',
    mlineIndex: 0,
    sdpMid: '0',
  ),
];

Uint8List _cborMap(Map<int, Object?> fields) {
  return Uint8List.fromList(cbor.encode(CborValue(fields)));
}

GroupService _groupService(InMemoryGroupRepository repo, String fingerprint) {
  final service = GroupService(repository: repo);
  service.configureLocalIdentity(
    fingerprint: fingerprint,
    displayName: fingerprint,
    deviceSuffix: fingerprint.substring(0, 1),
    endpoint: '127.0.0.1:4000',
  );
  return service;
}

Directory _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File(
      '${dir.path}${Platform.pathSeparator}HELIX_ENTERPRISE_TWO_APP_MASTER_PLAN.md',
    ).existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'Could not find repo root from ${Directory.current.path}',
      );
    }
    dir = parent;
  }
}

class _MemoryTrustRepository implements TrustRepository {
  List<KnownPeer> peers = [];

  @override
  Future<List<KnownPeer>> loadKnownPeers() async => peers;

  @override
  Future<void> saveKnownPeers(List<KnownPeer> peers) async {
    this.peers = List<KnownPeer>.from(peers);
  }
}

class _RecordingTransferGateway implements TransferGateway {
  final resumes = <FileResumeFrame>[];
  final _resumeController = StreamController<FileResumeFrame>.broadcast();

  @override
  bool get supportsFileResume => true;

  @override
  Stream<FileResumeFrame> get resumeEvents => _resumeController.stream;

  @override
  Future<void> sendCancel(FileCancelFrame frame) async {}

  @override
  Future<void> sendChunk(FileTransferFrame frame) async {}

  @override
  Future<void> sendComplete(FileCompleteFrame frame) async {}

  @override
  Future<void> sendFileResume(FileResumeFrame frame) async {
    resumes.add(frame);
    _resumeController.add(frame);
  }

  @override
  Future<void> sendProbe(FileProbeFrame frame) async {}
}

class _FakeDiagnosticsGateway implements DiagnosticsGateway {
  const _FakeDiagnosticsGateway({
    required this.interfaceType,
    required this.localIp,
    required this.networkName,
  });

  final String interfaceType;
  final String? localIp;
  final String? networkName;

  @override
  Future<String> getConnectivityType() async => interfaceType;

  @override
  Future<String?> getWifiIP() async => localIp;

  @override
  Future<String?> getWifiName() async => networkName;
}

class _MockCallEngine implements CallEngine {
  final log = <String>[];
  final _events = StreamController<CallEngineEvent>.broadcast();

  @override
  Stream<CallEngineEvent> get events => _events.stream;

  @override
  Future<void> addIceCandidate(
    String callId,
    String candidate,
    int mlineIndex,
    String sdpMid,
  ) async {
    log.add('addIceCandidate:$callId');
  }

  @override
  Future<String> createAnswer(
    String callId,
    String offerSdp, {
    bool video = false,
  }) async {
    log.add('createAnswer:$callId:video=$video');
    return 'answer';
  }

  @override
  Future<String> createOffer(String callId, {bool video = false}) async {
    log.add('createOffer:$callId:video=$video');
    return 'offer';
  }

  @override
  Future<void> dispose() async {
    await _events.close();
  }

  @override
  Future<void> endCall(String callId) async {
    log.add('endCall:$callId');
  }

  @override
  Future<void> setMuted(String callId, {required bool muted}) async {}

  @override
  Future<void> setRemoteAnswer(String callId, String answerSdp) async {}

  @override
  Future<void> setSpeakerOn(String callId, {required bool enabled}) async {}

  @override
  Future<void> setVideoEnabled(String callId, {required bool enabled}) async {}

  @override
  Future<void> switchCamera(String callId) async {
    log.add('switchCamera:$callId');
  }

  void emitConnected(String callId) {
    _events.add(CallConnectionStateEvent(callId: callId, connected: true));
  }
}

class _MockCallGateway implements CallSignalingGateway {
  @override
  Future<void> sendCallSignal(String peerId, CallSignalFrame frame) async {}
}
