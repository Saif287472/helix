import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:helix_protocol/application/contracts/use_cases.dart';
import 'package:helix/application/secret_code/secret_code_use_case_impl.dart';
import 'package:helix_domain/core/constants.dart';
import 'package:helix_domain/domain/models.dart';

class SecretCodeService {
  static SecretCodeUseCase? globalUseCase;

  static final _defaultUseCase = SecretCodeUseCaseImpl();

  final SecretCodeUseCase? _useCase;

  const SecretCodeService({this._useCase});

  SecretCodeUseCase get _effectiveUseCase =>
      _useCase ?? globalUseCase ?? _defaultUseCase;

  static bool isChallengePacket(Uint8List packet) =>
      (globalUseCase ?? _defaultUseCase).isChallengePacket(packet);

  static Future<String> deriveVerifier(String code) =>
      (globalUseCase ?? _defaultUseCase).deriveVerifier(code);

  Future<void> broadcastSearch(
    String enteredCode,
    RawDatagramSocket socket,
    List<String> broadcastAddresses,
  ) {
    return _effectiveUseCase.broadcastSearch(
      enteredCode,
      socket,
      broadcastAddresses,
    );
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
    return _effectiveUseCase.handleChallenge(
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
    return _effectiveUseCase.waitForResponse(socket, timeout);
  }

  Future<List<Peer>> waitForResponses(
    RawDatagramSocket socket,
    Duration timeout,
  ) {
    return _effectiveUseCase.waitForResponses(socket, timeout);
  }

  Future<List<Peer>> search(
    String enteredCode, {
    Duration timeout = kCodeSearchTimeout,
    List<String> broadcastAddresses = const ['255.255.255.255'],
  }) {
    return _effectiveUseCase.search(
      enteredCode,
      timeout: timeout,
      broadcastAddresses: broadcastAddresses,
    );
  }
}
