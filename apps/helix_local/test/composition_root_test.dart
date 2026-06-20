// Phase 5 + Phase 7 composition tests.
// P5-007: LocalCompositionRoot smoke test.
// P5-008: Deterministic disposal.
// P5-019: Two roots share no mutable state.
// P7-01: Static-fallback isolation — services use injected use cases only.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:helix_local_domain/core/product_descriptor.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix_local_protocol/application/contracts/use_cases.dart';
import 'package:helix/app/composition_root.dart';
import 'package:helix/providers/controllers/qr_code_service.dart';
import 'package:helix/providers/controllers/secret_code_service.dart';

void main() {
  group('LocalCompositionRoot', () {
    test(
      'P5-007: production() instantiates all required dependencies',
      () async {
        const descriptor = LocalProductDescriptor();
        final root = LocalCompositionRoot.production(descriptor);

        expect(root.conversationRepository, isNotNull);
        expect(root.connectionRequestRepository, isNotNull);
        expect(root.groupRepository, isNotNull);
        expect(root.transferRepository, isNotNull);
        expect(root.ephemeralMediaCache, isNotNull);
        expect(root.trustRepository, isNotNull);
        expect(root.sessionRepository, isNotNull);
        expect(root.foregroundServiceGateway, isNotNull);
        expect(root.notificationGateway, isNotNull);
        expect(root.diagnosticsGateway, isNotNull);
        expect(root.callEngine, isNotNull);
        expect(root.wipeScheduler, isNotNull);

        await root.dispose();
      },
    );

    test('P5-008: dispose() completes without error', () async {
      const descriptor = LocalProductDescriptor();
      final root = LocalCompositionRoot.production(descriptor);
      await expectLater(root.dispose(), completes);
    });

    test(
      'P5-019: two roots produce independent repository instances',
      () async {
        const descriptor = LocalProductDescriptor();
        final root1 = LocalCompositionRoot.production(descriptor);
        final root2 = LocalCompositionRoot.production(descriptor);

        expect(
          root1.conversationRepository,
          isNot(same(root2.conversationRepository)),
          reason: 'Each root must own independent in-memory storage',
        );
        expect(root1.groupRepository, isNot(same(root2.groupRepository)));
        expect(root1.wipeScheduler, isNot(same(root2.wipeScheduler)));

        await root1.dispose();
        await root2.dispose();
      },
    );
  });

  // P7-01: Static-fallback isolation.
  // Two service instances backed by independent use cases must not share any
  // mutable state — removing global/static fields ensures full isolation.
  group('P7-01: static-fallback isolation', () {
    test('QrCodeService instances are fully isolated by injected use case', () {
      final recordA = <String>[];
      final recordB = <String>[];

      final svcA = QrCodeService(useCase: _RecordingQrUseCase(recordA));
      final svcB = QrCodeService(useCase: _RecordingQrUseCase(recordB));

      svcA.decode('qr-a');
      svcB.decode('qr-b');
      svcA.decode('qr-a2');

      expect(recordA, ['qr-a', 'qr-a2']);
      expect(recordB, ['qr-b']);
    });

    test(
      'SecretCodeService.search dispatches to the injected use case',
      () async {
        final queriesA = <String>[];
        final queriesB = <String>[];

        final svcA = SecretCodeService(
          useCase: _StubSecretCodeUseCase(queriesA),
        );
        final svcB = SecretCodeService(
          useCase: _StubSecretCodeUseCase(queriesB),
        );

        await svcA.search('code-alpha');
        await svcB.search('code-beta');
        await svcA.search('code-alpha-2');

        expect(queriesA, ['code-alpha', 'code-alpha-2']);
        expect(queriesB, ['code-beta']);
      },
    );
  });
}

// ── Test doubles ─────────────────────────────────────────────────────────────

class _RecordingQrUseCase implements QrCodeUseCase {
  _RecordingQrUseCase(this._log);
  final List<String> _log;

  @override
  String encode(QrPayload payload) => '';

  @override
  QrPayload? decode(String raw) {
    _log.add(raw);
    return null;
  }

  @override
  Peer payloadToPeer(QrPayload payload) => throw UnimplementedError();

  @override
  List<Peer> payloadToPeers(QrPayload payload) => [];
}

class _StubSecretCodeUseCase implements SecretCodeUseCase {
  _StubSecretCodeUseCase(this._queries);
  final List<String> _queries;

  @override
  bool isChallengePacket(Uint8List packet) => false;

  @override
  Future<String> deriveVerifier(String code) async => '';

  @override
  Future<void> broadcastSearch(
    String enteredCode,
    RawDatagramSocket socket,
    List<String> broadcastAddresses,
  ) async {}

  @override
  Future<bool> handleChallenge(
    Uint8List packet,
    String storedVerifier,
    RawDatagramSocket replySocket,
    InternetAddress requesterAddr,
    int requesterPort,
    String sessionId,
    String displayName,
    String deviceSuffix,
    int tcpPort,
  ) async => false;

  @override
  Future<Peer?> waitForResponse(
    RawDatagramSocket socket,
    Duration timeout,
  ) async => null;

  @override
  Future<List<Peer>> waitForResponses(
    RawDatagramSocket socket,
    Duration timeout,
  ) async => [];

  @override
  Future<List<Peer>> search(
    String enteredCode, {
    Duration timeout = const Duration(seconds: 3),
    List<String> broadcastAddresses = const ['255.255.255.255'],
  }) async {
    _queries.add(enteredCode);
    return [];
  }
}
