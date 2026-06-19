import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:convert/convert.dart' as cvt;
import 'package:crypto/crypto.dart' as pkg_crypto;
import 'package:flutter_test/flutter_test.dart';

import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix/providers/controllers/messaging_service.dart';
import 'package:helix/providers/controllers/request_service.dart';
import 'package:helix_local_storage/infrastructure/storage/in_memory_connection_request_repository.dart';
import 'package:helix/infrastructure/scheduler/timer_disconnect_wipe_scheduler.dart';
import 'package:helix_local_transport/services/transport/secure_channel.dart';

void main() {
  test(
    'accepted request establishes secure channel and delivers chat',
    () async {
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
      final aliceMessaging = MessagingService(
        wipeScheduler: TimerDisconnectWipeScheduler(),
      );
      final bobMessaging = MessagingService(
        wipeScheduler: TimerDisconnectWipeScheduler(),
      );
      ServerSocket? server;
      StreamSubscription<Socket>? serverSub;

      try {
        server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        serverSub = server.listen(bobRequests.handleIncomingTcpConnection);

        final bobIncomingRequest = bobRequests.incomingRequests.first.timeout(
          const Duration(seconds: 10),
        );

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

        expect(aliceResult.request.status, RequestStatus.accepted);
        expect(aliceResult.channel, isNotNull);
        expect(bobChannel, isNotNull);
        expect(
          aliceResult.channel!.threadId,
          bobIdentity.staticPublicKeyFingerprint,
        );
        expect(bobChannel!.threadId, aliceIdentity.staticPublicKeyFingerprint);
        expect(aliceResult.channel!.state, ChannelState.active);
        expect(bobChannel.state, ChannelState.active);

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
          bobChannel.threadId,
          incoming.peerDisplayName,
          incoming.peerDeviceSuffix,
          bobChannel,
          incoming.peerSessionId,
          incoming.peerHost,
          incoming.peerPort,
        );

        final bobReceived = bobMessaging.threadChanges.firstWhere(
          (thread) => thread.messages.any((message) => message.text == 'hello'),
        );

        await aliceMessaging.sendMessage(
          aliceResult.channel!.threadId,
          'hello',
        );
        final bobThread = await bobReceived.timeout(
          const Duration(seconds: 10),
        );

        expect(bobThread.status, ThreadStatus.active);
        expect(bobThread.messages.single.text, 'hello');
        expect(bobThread.messages.single.origin, MessageOrigin.remote);

        final aliceReceived = aliceMessaging.threadChanges.firstWhere(
          (thread) => thread.messages.any((message) => message.text == 'reply'),
        );

        await bobMessaging.sendMessage(bobChannel.threadId, 'reply');
        final aliceThread = await aliceReceived.timeout(
          const Duration(seconds: 10),
        );

        expect(aliceThread.status, ThreadStatus.active);
        expect(
          aliceThread.messages
              .where((message) => message.text == 'reply')
              .single
              .origin,
          MessageOrigin.remote,
        );

        final bobDisconnected = bobMessaging.threadChanges.firstWhere(
          (thread) =>
              thread.threadId == bobChannel.threadId &&
              thread.status == ThreadStatus.disconnected,
        );
        await aliceMessaging.endConnection(aliceResult.channel!.threadId);
        await bobDisconnected.timeout(const Duration(seconds: 10));
      } finally {
        aliceMessaging.dispose();
        bobMessaging.dispose();
        await aliceRequests.close();
        await bobRequests.close();
        await serverSub?.cancel();
        await server?.close();
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test(
    'repeated incoming requests from same peer replace the old pending card',
    () async {
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
      ServerSocket? server;
      StreamSubscription<Socket>? serverSub;

      Future<RequestConnectionResult> ignoreFailure(
        Future<RequestConnectionResult> future,
      ) async {
        try {
          return await future;
        } catch (_) {
          return RequestConnectionResult(request: _dummyRequest());
        }
      }

      try {
        server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        serverSub = server.listen(bobRequests.handleIncomingTcpConnection);

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

        final firstIncoming = bobRequests.incomingRequests.first;
        final firstFuture = ignoreFailure(
          aliceRequests.sendRequest(
            alicePeer,
            RequestSourceMethod.nearby,
            aliceIdentity,
            aliceSessionId,
            'Alice',
          ),
        ).timeout(const Duration(seconds: 3), onTimeout: _dummyResult);
        final first = await firstIncoming.timeout(const Duration(seconds: 10));

        final secondIncoming = bobRequests.incomingRequests.first;
        final secondFuture = ignoreFailure(
          aliceRequests.sendRequest(
            alicePeer,
            RequestSourceMethod.nearby,
            aliceIdentity,
            aliceSessionId,
            'Alice',
          ),
        ).timeout(const Duration(seconds: 3), onTimeout: _dummyResult);
        final second = await secondIncoming.timeout(
          const Duration(seconds: 10),
        );

        expect(first.requestId, isNot(second.requestId));
        expect(bobRequests.pendingRequests.length, 1);
        expect(
          bobRequests.pendingRequests.containsKey(first.requestId),
          isFalse,
        );
        expect(
          bobRequests.pendingRequests.containsKey(second.requestId),
          isTrue,
        );

        await aliceRequests.close();
        await firstFuture;
        await secondFuture;
      } finally {
        await serverSub?.cancel();
        await server?.close();
        await bobRequests.close();
        await aliceRequests.close();
      }
    },
  );

  test(
    'one-way message is received without establishing a channel',
    () async {
      final aliceIdentity = _generateIdentity();
      const aliceSessionId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

      final aliceRequests = RequestService(
        connectionRequestRepository: InMemoryConnectionRequestRepository(),
      )..start();
      final bobRequests = RequestService(
        connectionRequestRepository: InMemoryConnectionRequestRepository(),
      )..start();
      final bobMessaging = MessagingService(
        wipeScheduler: TimerDisconnectWipeScheduler(),
      );
      ServerSocket? server;
      StreamSubscription<Socket>? serverSub;

      try {
        server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        serverSub = server.listen(bobRequests.handleIncomingTcpConnection);

        final incomingMessage = bobRequests.incomingOneWayMessages.first
            .timeout(const Duration(seconds: 10));

        final bobPeer = Peer(
          sessionId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          displayName: 'Bob',
          deviceSuffix: 'bbbb',
          host: InternetAddress.loopbackIPv4.address,
          port: server.port,
          source: PeerSource.udpBroadcast,
          seenAt: DateTime.now(),
          protocolMajor: kProtocolMajor,
          protocolMinor: kProtocolMinor,
        );

        await aliceRequests.sendOneWayMessage(
          bobPeer,
          aliceIdentity,
          aliceSessionId,
          'Alice',
          'bring the backup key',
        );

        final message = await incomingMessage;
        expect(message.peerDisplayName, 'Alice');
        expect(
          message.peerStaticKeyFingerprint,
          aliceIdentity.staticPublicKeyFingerprint,
        );
        expect(message.text, 'bring the backup key');

        bobMessaging.receiveOneWayMessage(message);
        // One-way messages go to the inbox, not a chat thread.
        expect(bobMessaging.oneWayInbox.length, 1);
        expect(bobMessaging.oneWayInbox.first.text, 'bring the backup key');
        expect(
          bobMessaging.oneWayInbox.first.peerStaticKeyFingerprint,
          aliceIdentity.staticPublicKeyFingerprint,
        );
      } finally {
        await bobMessaging.dispose();
        await aliceRequests.close();
        await bobRequests.close();
        await serverSub?.cancel();
        await server?.close();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

ConnectionRequest _dummyRequest() {
  final now = DateTime.now();
  return ConnectionRequest(
    requestId: 'ignored',
    direction: RequestDirection.outgoing,
    peerDisplayName: 'ignored',
    peerDeviceSuffix: '0000',
    peerSessionId: 'ignored',
    peerStaticKeyFingerprint: '',
    peerHost: InternetAddress.loopbackIPv4.address,
    peerPort: 1,
    source: RequestSourceMethod.nearby,
    createdAt: now,
    expiresAt: now,
    status: RequestStatus.rejected,
  );
}

RequestConnectionResult _dummyResult() =>
    RequestConnectionResult(request: _dummyRequest());

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
