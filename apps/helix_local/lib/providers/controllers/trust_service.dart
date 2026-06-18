import 'dart:async';

import 'package:helix_local_domain/domain/models.dart';
import 'package:helix_local_protocol/application/contracts/use_cases.dart';
import 'package:helix/application/trust/trust_use_case_impl.dart';
import 'package:helix_local_storage/infrastructure/storage/secure_trust_repository.dart';

class TrustService {
  final TrustUseCase _trustUseCase;

  TrustService({TrustUseCase? trustUseCase})
    : _trustUseCase =
          trustUseCase ??
          TrustUseCaseImpl(repository: const SecureTrustRepository());

  Stream<List<KnownPeer>> get changes => _trustUseCase.changes;

  List<KnownPeer> get allPeers => _trustUseCase.allPeers;
  List<KnownPeer> get trustedPeers => _trustUseCase.trustedPeers;

  Future<void> init() async {
    await _trustUseCase.init();
  }

  KnownPeer? getPeer(String fingerprint) {
    return _trustUseCase.getPeer(fingerprint);
  }

  bool isKnown(String fingerprint) => _trustUseCase.isKnown(fingerprint);

  bool isTrusted(String fingerprint) => _trustUseCase.isTrusted(fingerprint);

  String displayNameFor(String fingerprint, String fallback) {
    return _trustUseCase.displayNameFor(fingerprint, fallback);
  }

  KnownPeer? detectImpersonation(String incomingFp, String incomingName) {
    return _trustUseCase.detectImpersonation(incomingFp, incomingName);
  }

  Future<void> markKnown(
    String fingerprint,
    String publicName,
    String deviceSuffix,
    String host,
    int port,
  ) async {
    await _trustUseCase.markKnown(
      fingerprint,
      publicName,
      deviceSuffix,
      host,
      port,
    );
  }

  Future<void> trustPeer(String fingerprint, String nickname) async {
    await _trustUseCase.trustPeer(fingerprint, nickname);
  }

  Future<void> untrustPeer(String fingerprint) async {
    await _trustUseCase.untrustPeer(fingerprint);
  }

  Future<void> forgetPeer(String fingerprint) async {
    await _trustUseCase.forgetPeer(fingerprint);
  }

  Future<void> renamePeer(String fingerprint, String nickname) async {
    await _trustUseCase.renamePeer(fingerprint, nickname);
  }

  Future<void> clearAllPeers() async {
    await _trustUseCase.clearAllPeers();
  }

  void dispose() {
    _trustUseCase.dispose();
  }
}
