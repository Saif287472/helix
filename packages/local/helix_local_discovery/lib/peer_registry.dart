import 'dart:async';

import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/domain/models.dart';

class PeerRegistry {
  final Map<String, Peer> _peers = {};
  final StreamController<List<Peer>> _controller =
      StreamController<List<Peer>>.broadcast();
  Timer? _cleanupTimer;

  // ── Public API ──────────────────────────────────────────────────────────────

  Stream<List<Peer>> get peerListChanges => _controller.stream;

  List<Peer> get peers => List.unmodifiable(_peers.values);

  void start() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _evictStale(),
    );
    _emit();
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _controller.close();
  }

  bool upsert(Peer peer) {
    final existing = _peers[peer.sessionId];

    if (existing != null &&
        existing.host == peer.host &&
        existing.port == peer.port &&
        existing.displayName == peer.displayName) {
      _peers[peer.sessionId] = existing.copyWith(seenAt: peer.seenAt);
      return false;
    }

    _peers[peer.sessionId] = peer;
    _enforceLimit();
    _emit();
    return true;
  }

  bool remove(String sessionId) {
    if (_peers.remove(sessionId) != null) {
      _emit();
      return true;
    }
    return false;
  }

  void clear() {
    if (_peers.isEmpty) return;
    _peers.clear();
    _emit();
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  void _evictStale() {
    final cutoff = DateTime.now().subtract(kPeerStaleDuration);
    final stale = _peers.entries
        .where((e) => e.value.seenAt.isBefore(cutoff))
        .toList();
    if (stale.isEmpty) return;
    for (final e in stale) {
      _peers.remove(e.key);
    }
    _emit();
  }

  void _enforceLimit() {
    if (_peers.length <= kMaxNearbyPeers) return;
    final oldest = _peers.values.reduce(
      (a, b) => a.seenAt.isBefore(b.seenAt) ? a : b,
    );
    _peers.remove(oldest.sessionId);
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(List.unmodifiable(_peers.values));
    }
  }
}
