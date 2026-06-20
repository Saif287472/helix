// Discovery providers: mDNS/UDP coordinator, nearby peers, favorites, connectivity.
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix/providers/session_provider.dart'
    show productDescriptorProvider;
import 'package:helix/providers/infrastructure_providers.dart';
import 'package:helix/providers/identity_providers.dart'
    show secretCodeUseCaseProvider, knownPeersProvider;
import 'package:helix_local_discovery/helix_discovery.dart';

typedef TrustedPeerPresence = ({KnownPeer peer, Peer? nearbyMatch});

final discoveryCoordinatorProvider = Provider<DiscoveryCoordinator>((ref) {
  final descriptor = ref.watch(productDescriptorProvider);
  final coordinator = DiscoveryCoordinator(
    secretCodeUseCase: ref.watch(secretCodeUseCaseProvider),
    mdns: MdnsDiscovery(
      methodChannelName: '${descriptor.methodChannelNamespace}/mdns',
      eventChannelName: '${descriptor.methodChannelNamespace}/mdns/events',
    ),
  );
  ref.onDispose(() => unawaited(coordinator.dispose()));
  return coordinator;
});

final nearbyPeersProvider = StreamProvider<List<Peer>>((ref) {
  return ref.watch(discoveryCoordinatorProvider).peerListChanges;
});

final trustedPeersWithPresenceProvider = Provider<List<TrustedPeerPresence>>((
  ref,
) {
  final trusted =
      ref.watch(knownPeersProvider).value?.where((p) => p.trusted).toList() ??
      [];
  final nearby = ref.watch(nearbyPeersProvider).value ?? [];
  return trusted.map((p) {
    final match = nearby.cast<Peer?>().firstWhere(
      (n) => n!.deviceSuffix == p.deviceSuffix,
      orElse: () => null,
    );
    return (peer: p, nearbyMatch: match);
  }).toList();
});

final hasConnectivityProvider = StreamProvider<bool>((ref) async* {
  final conn = Connectivity();
  final initial = await conn.checkConnectivity();
  yield initial.any((r) => r != ConnectivityResult.none);
  yield* conn.onConnectivityChanged.map(
    (results) => results.any((r) => r != ConnectivityResult.none),
  );
});

final favoritePeersProvider =
    StateNotifierProvider<FavoritePeersNotifier, Set<String>>((ref) {
      return FavoritePeersNotifier(ref);
    });

class FavoritePeersNotifier extends StateNotifier<Set<String>> {
  FavoritePeersNotifier(this._ref) : super(const {}) {
    _init();
  }

  final Ref _ref;

  Future<void> _init() async {
    final db = await _ref.read(databaseProvider.future);
    if (!mounted) return;
    final ids = db.getFavoritePeers().map((p) => p.sessionId).toSet();
    state = ids;
  }

  Future<void> toggle(Peer peer) async {
    final db = await _ref.read(databaseProvider.future);
    final isFav = state.contains(peer.sessionId);
    db.upsertPeerCache(peer, isFavorite: !isFav);
    state = isFav
        ? (Set<String>.from(state)..remove(peer.sessionId))
        : {...state, peer.sessionId};
  }
}

final favoritePeerListProvider = FutureProvider<List<Peer>>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return db.getFavoritePeers();
});
