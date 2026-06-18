import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:helix_domain/core/constants.dart';
import 'package:helix_domain/domain/models.dart';
import 'package:helix_protocol/application/contracts/use_cases.dart';

/// Presence packet layout (binary, big-endian):
///   [0]      version        = kProtocolMajor           (uint8)
///   [1]      type           = 0x01 (presence)          (uint8)
///   [2..3]   proto minor    = kProtocolMinor            (uint16 BE)
///   [4..5]   tcp port                                   (uint16 BE)
///   [6]      discoverable   = 1 | 0                    (uint8)
///   [7]      sid len                                    (uint8)  ≤ 64
///   [8..N]   sessionId      UTF-8
///   [N+1]    name len                                   (uint8)  ≤ 64
///   [N+2..M] displayName    UTF-8
///   [M+1]    sfx len                                    (uint8)  ≤ 8
///   [M+2..K] deviceSuffix   UTF-8
class UdpDiscovery {
  UdpDiscovery({this._secretCodeUseCase});

  final SecretCodeUseCase? _secretCodeUseCase;

  RawDatagramSocket? _socket;
  Timer? _announceTimer;
  StreamSubscription<RawSocketEvent>? _socketSub;

  bool _running = false;
  bool _discoverable = false;

  String _sessionId = '';
  String _displayName = '';
  String _deviceSuffix = '';
  String? _secretCodeVerifier;
  int _tcpPort = 0;

  // Dedup map: sessionId → last-seen timestamp
  final Map<String, DateTime> _recentlySeen = {};
  static const _dedupWindow = Duration(seconds: 5);

  final StreamController<Peer> _discoveredController =
      StreamController<Peer>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  Stream<Peer> get discovered => _discoveredController.stream;
  Stream<String> get errors => _errorController.stream;

  // ---------------------------------------------------------------------------
  // Start
  // ---------------------------------------------------------------------------

  Future<void> start(
    String sessionId,
    String displayName,
    String deviceSuffix,
    int tcpPort,
    bool discoverable,
    String? secretCodeVerifier,
  ) async {
    if (_running) return;

    _sessionId = sessionId;
    _displayName = displayName;
    _deviceSuffix = deviceSuffix;
    _secretCodeVerifier = secretCodeVerifier;
    _tcpPort = tcpPort;
    _discoverable = discoverable;
    _running = true;
    try {
      await _bindSocket();
      if (_socket == null) {
        throw const SocketException('UDP discovery bind failed');
      }
    } catch (_) {
      _running = false;
      await stop();
      rethrow;
    }
    if (_discoverable) _scheduleAnnounce();
  }

  // ---------------------------------------------------------------------------
  // Stop
  // ---------------------------------------------------------------------------

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _announceTimer?.cancel();
    _announceTimer = null;
    await _socketSub?.cancel();
    _socketSub = null;
    _socket?.close();
    _socket = null;
    _recentlySeen.clear();
  }

  // ---------------------------------------------------------------------------
  // Update discoverability at runtime
  // ---------------------------------------------------------------------------

  Future<void> updateDiscoverability(bool discoverable) async {
    _discoverable = discoverable;
    if (_discoverable) {
      _scheduleAnnounce();
    } else {
      _announceTimer?.cancel();
      _announceTimer = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Private: bind UDP socket
  // ---------------------------------------------------------------------------

  Future<void> _bindSocket() async {
    try {
      // Prefer binding to a Wi-Fi interface so discovery works reliably on
      // devices with multiple network interfaces (e.g. cellular + Wi-Fi).
      InternetAddress bindAddress = InternetAddress.anyIPv4;
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        );
        final wifiInterface = interfaces.cast<NetworkInterface?>().firstWhere((
          iface,
        ) {
          final name = iface!.name.toLowerCase();
          return name.contains('wlan') || name.contains('wi-fi');
        }, orElse: () => null);
        if (wifiInterface != null && wifiInterface.addresses.isNotEmpty) {
          bindAddress = wifiInterface.addresses.first;
        }
      } catch (_) {
        // NetworkInterface.list() can fail on some platforms — fall back to
        // anyIPv4 silently.
      }

      bindAddress = InternetAddress.anyIPv4;
      _socket = await RawDatagramSocket.bind(
        bindAddress,
        kUdpDiscoveryPort,
        reuseAddress: true,
        reusePort: false,
      );
      _socket!.broadcastEnabled = true;
      _socket!.readEventsEnabled = true;

      _socketSub = _socket!.listen(
        _onSocketEvent,
        onError: (Object e) => _errorController.add('UDP socket error: $e'),
        cancelOnError: false,
      );
    } catch (e) {
      _errorController.add('UDP bind error: $e');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Private: receive path
  // ---------------------------------------------------------------------------

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null) return;

    final data = datagram.data;
    if (data.length < 8 || data.length > kUdpMaxPacketSize) return;

    try {
      if (_secretCodeUseCase?.isChallengePacket(data) ?? false) {
        final verifier = _secretCodeVerifier;
        if (verifier != null && verifier.isNotEmpty) {
          unawaited(
            _secretCodeUseCase!.handleChallenge(
              data,
              verifier,
              _socket!,
              datagram.address,
              datagram.port,
              _sessionId,
              _displayName,
              _deviceSuffix,
              _tcpPort,
            ),
          );
        }
        return;
      }

      final peer = _parsePresencePacket(data, datagram.address.address);
      if (peer == null) return;
      if (peer.sessionId == _sessionId) return; // own announcement

      // Dedup: skip if seen in last 5 seconds
      final now = DateTime.now();
      final lastSeen = _recentlySeen[peer.sessionId];
      if (lastSeen != null && now.difference(lastSeen) < _dedupWindow) return;
      _recentlySeen[peer.sessionId] = now;
      _pruneRecentlySeen(now);

      if (!_discoveredController.isClosed) {
        _discoveredController.add(peer);
      }
    } catch (_) {
      // Malformed packet — silently ignore
    }
  }

  Peer? _parsePresencePacket(Uint8List data, String senderIp) {
    if (data.length < 8) return null;

    final version = data[0];
    final type = data[1];
    if (version != kProtocolMajor || type != 0x01) return null;

    final protoMinor = (data[2] << 8) | data[3];
    final port = (data[4] << 8) | data[5];
    final disc = data[6];
    if (disc == 0) return null; // hidden peer

    int offset = 7;

    // sessionId
    if (offset >= data.length) return null;
    final sidLen = data[offset++];
    if (offset + sidLen > data.length) return null;
    final sessionId = utf8.decode(data.sublist(offset, offset + sidLen));
    offset += sidLen;

    // displayName
    if (offset >= data.length) return null;
    final nameLen = data[offset++];
    if (offset + nameLen > data.length) return null;
    final displayName = utf8.decode(data.sublist(offset, offset + nameLen));
    offset += nameLen;

    // deviceSuffix
    if (offset >= data.length) return null;
    final sfxLen = data[offset++];
    if (offset + sfxLen > data.length) return null;
    final deviceSuffix = utf8.decode(data.sublist(offset, offset + sfxLen));

    if (sessionId.isEmpty || displayName.isEmpty) return null;

    return Peer(
      sessionId: sessionId,
      displayName: displayName,
      deviceSuffix: deviceSuffix,
      host: senderIp,
      port: port,
      source: PeerSource.udpBroadcast,
      seenAt: DateTime.now(),
      protocolMajor: kProtocolMajor,
      protocolMinor: protoMinor,
    );
  }

  void _pruneRecentlySeen(DateTime now) {
    _recentlySeen.removeWhere(
      (_, ts) => now.difference(ts) >= _dedupWindow * 2,
    );
  }

  // ---------------------------------------------------------------------------
  // Private: announce path
  // ---------------------------------------------------------------------------

  void _scheduleAnnounce() {
    _announceTimer?.cancel();
    // Send once immediately, then on interval
    _sendAnnouncement();
    _announceTimer = Timer.periodic(kPresenceInterval, (_) {
      if (_running && _discoverable) _sendAnnouncement();
    });
  }

  void _sendAnnouncement() {
    if (_socket == null) return;
    try {
      final packet = _buildPresencePacket();
      if (packet.length > kUdpMaxPacketSize) return; // safety guard
      unawaited(_sendToBroadcastAddresses(packet));
    } catch (e) {
      _errorController.add('UDP send error: $e');
    }
  }

  Future<void> _sendToBroadcastAddresses(Uint8List packet) async {
    final destinations = <String>{'255.255.255.255'};

    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final broadcast = _classCBroadcastAddress(address.address);
          if (broadcast != null) destinations.add(broadcast);
        }
      }
    } catch (_) {}

    for (final destination in destinations) {
      try {
        _socket?.send(packet, InternetAddress(destination), kUdpDiscoveryPort);
      } catch (e) {
        _errorController.add('UDP send error to $destination: $e');
      }
    }
  }

  String? _classCBroadcastAddress(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((o) => o == null || o < 0 || o > 255)) return null;
    if (octets[0] == 127 || (octets[0] == 169 && octets[1] == 254)) {
      return null;
    }
    return '${octets[0]}.${octets[1]}.${octets[2]}.255';
  }

  Uint8List _buildPresencePacket() {
    final sidBytes = utf8.encode(_sessionId);
    final nameBytes = utf8.encode(_displayName);
    final sfxBytes = utf8.encode(_deviceSuffix);

    // Truncate fields to fit uint8 length prefix limits
    final sid = sidBytes.length <= 64 ? sidBytes : sidBytes.sublist(0, 64);
    final name = nameBytes.length <= 64 ? nameBytes : nameBytes.sublist(0, 64);
    final sfx = sfxBytes.length <= 8 ? sfxBytes : sfxBytes.sublist(0, 8);

    final totalLen = 7 + 1 + sid.length + 1 + name.length + 1 + sfx.length;
    final buf = Uint8List(totalLen);
    int offset = 0;

    buf[offset++] = kProtocolMajor; // version
    buf[offset++] = 0x01; // type: presence
    buf[offset++] = (kProtocolMinor >> 8) & 0xFF;
    buf[offset++] = kProtocolMinor & 0xFF;
    buf[offset++] = (_tcpPort >> 8) & 0xFF;
    buf[offset++] = _tcpPort & 0xFF;
    buf[offset++] = _discoverable ? 1 : 0;

    buf[offset++] = sid.length;
    buf.setRange(offset, offset + sid.length, sid);
    offset += sid.length;

    buf[offset++] = name.length;
    buf.setRange(offset, offset + name.length, name);
    offset += name.length;

    buf[offset++] = sfx.length;
    buf.setRange(offset, offset + sfx.length, sfx);

    return buf;
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    await stop();
    await _discoveredController.close();
    await _errorController.close();
  }
}
