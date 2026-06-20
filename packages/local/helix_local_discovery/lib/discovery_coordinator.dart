import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix_local_protocol/application/contracts/use_cases.dart';

import 'package:helix_local_discovery/lan_candidate.dart';
import 'package:helix_local_discovery/mdns_discovery.dart';
import 'package:helix_local_discovery/peer_registry.dart';
import 'package:helix_local_discovery/udp_discovery.dart';

class DiscoveryCoordinator {
  DiscoveryCoordinator({
    MdnsDiscovery? mdns,
    UdpDiscovery? udp,
    PeerRegistry? registry,
    SecretCodeUseCase? secretCodeUseCase,
  }) : _mdns = mdns ?? MdnsDiscovery(),
       _udp = udp ?? UdpDiscovery(secretCodeUseCase: secretCodeUseCase),
       _registry = registry ?? PeerRegistry(),
       _secretCodeUseCase = secretCodeUseCase;

  final MdnsDiscovery _mdns;
  final UdpDiscovery _udp;
  final PeerRegistry _registry;
  final SecretCodeUseCase? _secretCodeUseCase;

  StreamSubscription<Peer>? _mdnsSub;
  StreamSubscription<Peer>? _udpSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _restartDebounce;

  bool _running = false;
  bool _restarting = false;
  String? _lastConnectivitySignature;
  _DiscoveryStartConfig? _lastConfig;

  // ── Public API ──────────────────────────────────────────────────────────────

  List<Peer> get peers => _registry.peers;

  Stream<List<Peer>> get peerListChanges => _registry.peerListChanges;

  Future<void> start({
    required String sessionId,
    required String displayName,
    required String deviceSuffix,
    required int tcpPort,
    required bool discoverable,
    String? secretCodeVerifier,
  }) async {
    if (_running) return;
    _running = true;

    _lastConfig = _DiscoveryStartConfig(
      sessionId: sessionId,
      displayName: displayName,
      deviceSuffix: deviceSuffix,
      tcpPort: tcpPort,
      discoverable: discoverable,
      secretCodeVerifier: secretCodeVerifier,
    );

    _startRegistrySubscriptions();
    _startConnectivityWatcher();
    try {
      await _startDiscoverySources(_lastConfig!);
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  Future<List<Peer>> searchBySecretCode(String enteredCode) async {
    final broadcasts = await _computeBroadcastAddresses();
    if (_secretCodeUseCase == null) return [];
    return _secretCodeUseCase.search(
      enteredCode,
      broadcastAddresses: broadcasts,
    );
  }

  Future<List<String>> _computeBroadcastAddresses() async {
    final destinations = <String>{'255.255.255.255'};
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final broadcast = _subnetBroadcast(addr.address);
          if (broadcast != null) destinations.add(broadcast);
        }
      }
    } catch (_) {}
    return destinations.toList();
  }

  String? _subnetBroadcast(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((o) => o == null || o < 0 || o > 255)) return null;
    if (octets[0] == 127 || (octets[0] == 169 && octets[1] == 254)) return null;
    return '${octets[0]}.${octets[1]}.${octets[2]}.255';
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _lastConfig = null;
    _lastConnectivitySignature = null;
    _restartDebounce?.cancel();
    _restartDebounce = null;
    await _connectivitySub?.cancel();
    _connectivitySub = null;

    await _mdnsSub?.cancel();
    await _udpSub?.cancel();
    _mdnsSub = null;
    _udpSub = null;

    await Future.wait([_mdns.stop(), _udp.stop()]);
    _registry.clear();
  }

  Future<void> restart() async {
    final config = _lastConfig;
    if (!_running || config == null || _restarting) return;

    _restarting = true;
    try {
      await _mdnsSub?.cancel();
      await _udpSub?.cancel();
      _mdnsSub = null;
      _udpSub = null;

      await Future.wait([_mdns.stop(), _udp.stop()]);
      _registry.clear();
      _startRegistrySubscriptions();
      await _startDiscoverySources(config);
    } catch (_) {
      await _mdns.stop().catchError((_) {});
      await _udp.stop().catchError((_) {});
      _running = false;
      rethrow;
    } finally {
      _restarting = false;
    }
  }

  Future<void> updateDiscoverability(bool discoverable) async {
    final config = _lastConfig;
    if (config != null) {
      _lastConfig = config.copyWith(discoverable: discoverable);
    }
    await Future.wait([
      _mdns.updateDiscoverability(discoverable),
      _udp.updateDiscoverability(discoverable),
    ]);
  }

  Future<Peer?> probeDirectIp(
    String host,
    int port,
    String localSessionId,
  ) async {
    if (!isLanCandidate(host)) return null;
    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );

      final sidBytes = utf8.encode(localSessionId);
      final probeLen = 2 + sidBytes.length;
      final probe = Uint8List(probeLen);
      probe[0] = 0xFF; // type: probe
      probe[1] = sidBytes.length;
      probe.setRange(2, 2 + sidBytes.length, sidBytes);
      socket.add(probe);
      await socket.flush();

      final responseBytes = <int>[];
      await for (final chunk in socket.timeout(const Duration(seconds: 5))) {
        responseBytes.addAll(chunk);
        if (responseBytes.length >= 256) break;
      }

      socket.destroy();
      socket = null;

      return _parsePeerInfoFrame(Uint8List.fromList(responseBytes), host);
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  Future<void> dispose() async {
    _restartDebounce?.cancel();
    await _connectivitySub?.cancel();
    await _mdnsSub?.cancel();
    await _udpSub?.cancel();
    _mdnsSub = null;
    _udpSub = null;
    await _mdns.dispose();
    await _udp.dispose();
    _registry.dispose();
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  void _startRegistrySubscriptions() {
    _registry.start();
    _mdnsSub = _mdns.discovered.listen((peer) {
      if (isLanCandidate(peer.host)) _registry.upsert(peer);
    });
    _udpSub = _udp.discovered.listen((peer) {
      if (isLanCandidate(peer.host)) _registry.upsert(peer);
    });
  }


  Future<void> _startDiscoverySources(_DiscoveryStartConfig config) async {
    if (Platform.isWindows) {
      await Future.wait([
        _mdns.start(
          config.sessionId,
          config.displayName,
          config.deviceSuffix,
          config.tcpPort,
          config.discoverable,
        ),
        _udp.start(
          config.sessionId,
          config.displayName,
          config.deviceSuffix,
          config.tcpPort,
          config.discoverable,
          config.secretCodeVerifier,
        ),
      ]);
      return;
    }

    await _mdns.start(
      config.sessionId,
      config.displayName,
      config.deviceSuffix,
      config.tcpPort,
      config.discoverable,
    );
    await _udp.start(
      config.sessionId,
      config.displayName,
      config.deviceSuffix,
      config.tcpPort,
      config.discoverable,
      config.secretCodeVerifier,
    );
  }

  void _startConnectivityWatcher() {
    _connectivitySub ??= Connectivity().onConnectivityChanged.listen((results) {
      final signature = _connectivitySignature(results);
      if (_lastConnectivitySignature == null) {
        _lastConnectivitySignature = signature;
        return;
      }
      if (_lastConnectivitySignature == signature) return;
      _lastConnectivitySignature = signature;

      _restartDebounce?.cancel();
      _restartDebounce = Timer(const Duration(seconds: 1), restart);
    });
  }

  String _connectivitySignature(List<ConnectivityResult> results) {
    final names = results.map((r) => r.name).toList()..sort();
    return names.join(',');
  }

  Peer? _parsePeerInfoFrame(Uint8List data, String host) {
    if (data.length < 7) return null;
    if (data[0] != 0x01) return null; // expect info frame

    final pmaj = data[1];
    final pmin = data[2];
    final tcpPort = (data[3] << 8) | data[4];

    int offset = 5;

    // sessionId
    if (offset >= data.length) return null;
    final sidLen = data[offset++];
    if (offset + sidLen > data.length) return null;
    final sessionId = utf8.decode(data.sublist(offset, offset + sidLen));
    offset += sidLen;

    // displayName
    if (offset >= data.length) return null;
    final dnLen = data[offset++];
    if (offset + dnLen > data.length) return null;
    final displayName = utf8.decode(data.sublist(offset, offset + dnLen));
    offset += dnLen;

    // deviceSuffix
    String deviceSuffix = '';
    if (offset < data.length) {
      final sfxLen = data[offset++];
      if (offset + sfxLen <= data.length) {
        deviceSuffix = utf8.decode(data.sublist(offset, offset + sfxLen));
      }
    }

    if (sessionId.isEmpty || displayName.isEmpty) return null;

    return Peer(
      sessionId: sessionId,
      displayName: displayName,
      deviceSuffix: deviceSuffix,
      host: host,
      port: tcpPort,
      source: PeerSource.directIp,
      seenAt: DateTime.now(),
      protocolMajor: pmaj,
      protocolMinor: pmin,
    );
  }
}

class _DiscoveryStartConfig {
  const _DiscoveryStartConfig({
    required this.sessionId,
    required this.displayName,
    required this.deviceSuffix,
    required this.tcpPort,
    required this.discoverable,
    required this.secretCodeVerifier,
  });

  final String sessionId;
  final String displayName;
  final String deviceSuffix;
  final int tcpPort;
  final bool discoverable;
  final String? secretCodeVerifier;

  _DiscoveryStartConfig copyWith({bool? discoverable}) {
    return _DiscoveryStartConfig(
      sessionId: sessionId,
      displayName: displayName,
      deviceSuffix: deviceSuffix,
      tcpPort: tcpPort,
      discoverable: discoverable ?? this.discoverable,
      secretCodeVerifier: secretCodeVerifier,
    );
  }
}
