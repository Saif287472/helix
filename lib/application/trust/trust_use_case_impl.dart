import 'dart:async';

import 'package:helix_domain/domain/models.dart';
import 'package:helix_domain/application/contracts/repositories.dart';
import 'package:helix_protocol/application/contracts/use_cases.dart';

class TrustUseCaseImpl implements TrustUseCase {
  final TrustRepository _repository;

  final List<KnownPeer> _peers = [];
  final StreamController<List<KnownPeer>> _ctrl =
      StreamController<List<KnownPeer>>.broadcast();

  TrustUseCaseImpl({required this._repository});

  @override
  List<KnownPeer> get allPeers => List.unmodifiable(_peers);

  @override
  List<KnownPeer> get trustedPeers => _peers.where((p) => p.trusted).toList();

  @override
  Stream<List<KnownPeer>> get changes => _ctrl.stream;

  @override
  Future<void> init() async {
    final loaded = await _repository.loadKnownPeers();
    _peers.clear();
    _peers.addAll(loaded);
    _ctrl.add(List.unmodifiable(_peers));
  }

  Future<void> _save() async {
    await _repository.saveKnownPeers(_peers);
    _ctrl.add(List.unmodifiable(_peers));
  }

  @override
  KnownPeer? getPeer(String fingerprint) {
    for (final p in _peers) {
      if (p.fingerprint == fingerprint) return p;
    }
    return null;
  }

  @override
  bool isKnown(String fingerprint) => getPeer(fingerprint) != null;

  @override
  bool isTrusted(String fingerprint) => getPeer(fingerprint)?.trusted == true;

  @override
  String displayNameFor(String fingerprint, String fallback) {
    final p = getPeer(fingerprint);
    if (p != null && p.trusted && p.nickname != null) return p.nickname!;
    return fallback;
  }

  @override
  KnownPeer? detectImpersonation(String incomingFp, String incomingName) {
    final lower = incomingName.toLowerCase();
    for (final p in _peers) {
      if (!p.trusted) continue;
      if (p.fingerprint == incomingFp) continue;
      final nick = p.nickname?.toLowerCase();
      if (nick == lower) return p;
    }
    return null;
  }

  @override
  Future<void> markKnown(
    String fingerprint,
    String publicName,
    String deviceSuffix,
    String host,
    int port,
  ) async {
    final now = DateTime.now();
    final idx = _peers.indexWhere((p) => p.fingerprint == fingerprint);
    if (idx >= 0) {
      _peers[idx] = _peers[idx].copyWith(
        lastPublicName: publicName,
        lastHost: host,
        lastPort: port,
        lastSeenAt: now,
      );
    } else {
      _peers.add(
        KnownPeer(
          fingerprint: fingerprint,
          lastPublicName: publicName,
          deviceSuffix: deviceSuffix,
          lastHost: host,
          lastPort: port,
          firstSeenAt: now,
          lastSeenAt: now,
        ),
      );
    }
    await _save();
  }

  @override
  Future<void> trustPeer(String fingerprint, String nickname) async {
    final idx = _peers.indexWhere((p) => p.fingerprint == fingerprint);
    if (idx >= 0) {
      _peers[idx] = _peers[idx].copyWith(trusted: true, nickname: nickname);
    }
    await _save();
  }

  @override
  Future<void> untrustPeer(String fingerprint) async {
    final idx = _peers.indexWhere((p) => p.fingerprint == fingerprint);
    if (idx >= 0) {
      _peers[idx] = _peers[idx].copyWith(trusted: false, nickname: null);
      await _save();
    }
  }

  @override
  Future<void> forgetPeer(String fingerprint) async {
    _peers.removeWhere((p) => p.fingerprint == fingerprint);
    await _save();
  }

  @override
  Future<void> renamePeer(String fingerprint, String nickname) async {
    final idx = _peers.indexWhere((p) => p.fingerprint == fingerprint);
    if (idx >= 0 && _peers[idx].trusted) {
      _peers[idx] = _peers[idx].copyWith(nickname: nickname);
      await _save();
    }
  }

  @override
  Future<void> clearAllPeers() async {
    _peers.clear();
    await _save();
  }

  @override
  void dispose() {
    _ctrl.close();
  }
}
