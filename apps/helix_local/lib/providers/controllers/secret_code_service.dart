import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:helix_local_protocol/application/contracts/use_cases.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/domain/models.dart';

class SecretCodeService {
  final SecretCodeUseCase useCase;

  const SecretCodeService({required this.useCase});

  Future<void> broadcastSearch(
    String enteredCode,
    RawDatagramSocket socket,
    List<String> broadcastAddresses,
  ) {
    return useCase.broadcastSearch(enteredCode, socket, broadcastAddresses);
  }

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
  ) {
    return useCase.handleChallenge(
      packet,
      storedVerifier,
      replySocket,
      requesterAddr,
      requesterPort,
      sessionId,
      displayName,
      deviceSuffix,
      tcpPort,
    );
  }

  Future<Peer?> waitForResponse(RawDatagramSocket socket, Duration timeout) {
    return useCase.waitForResponse(socket, timeout);
  }

  Future<List<Peer>> waitForResponses(
    RawDatagramSocket socket,
    Duration timeout,
  ) {
    return useCase.waitForResponses(socket, timeout);
  }

  Future<List<Peer>> search(
    String enteredCode, {
    Duration timeout = kCodeSearchTimeout,
    List<String> broadcastAddresses = const ['255.255.255.255'],
  }) {
    return useCase.search(
      enteredCode,
      timeout: timeout,
      broadcastAddresses: broadcastAddresses,
    );
  }
}
