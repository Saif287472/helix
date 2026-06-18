import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:helix_local_groups/domain/lobby_constants.dart';

/// Incoming UDP datagram with parsed frame + sender address.
typedef LobbyDatagram = ({
  Map<String, dynamic> frame,
  InternetAddress sender,
  int senderPort,
});

/// Manages the UDP multicast socket for LAN lobby discovery.
///
/// One socket is used for both sending and receiving.  The host sends periodic
/// ANNOUNCE frames; any device sends DISC_REQ on lobby open.
class LanLobbyDiscovery {
  RawDatagramSocket? _socket;
  StreamController<LobbyDatagram>? _controller;
  final _random = Random();

  bool get isOpen => _socket != null;

  /// Opens the multicast socket and starts listening.
  /// Must be called before any send/stream access.
  Future<void> open() async {
    if (_socket != null) return;

    RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kLobbyMulticastPort,
        reuseAddress: true,
        reusePort: true,
      );
    } catch (_) {
      // reusePort unsupported on some platforms (Windows)
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kLobbyMulticastPort,
        reuseAddress: true,
      );
    }

    socket.multicastLoopback = false;
    try {
      socket.joinMulticast(InternetAddress(kLobbyMulticastGroup));
    } catch (_) {
      // Best-effort; may fail if the interface doesn't support multicast.
    }

    _socket = socket;
    final controller = StreamController<LobbyDatagram>.broadcast();
    _controller = controller;

    socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        if (datagram.data.length > kLobbyMaxUdpBytes) return;
        try {
          final raw = jsonDecode(utf8.decode(datagram.data));
          if (raw is! Map<String, dynamic>) return;
          if ((raw['v'] as int?) != kLobbyProtocolVersion) return;
          if (!controller.isClosed) {
            controller.add((
              frame: raw,
              sender: datagram.address,
              senderPort: datagram.port,
            ));
          }
        } catch (_) {}
      },
      onError: (_) {},
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
      cancelOnError: false,
    );
  }

  /// Stream of all valid incoming datagrams (filtered to protocol version 1).
  Stream<LobbyDatagram> get incoming =>
      _controller?.stream ?? Stream.empty();

  /// Sends an ANNOUNCE to the multicast group.
  void sendAnnounce({
    required String sid,
    required int gen,
    required String hostFp,
    required int tcpPort,
    required int memberCount,
    String? replyToNonce,
  }) {
    final frame = <String, dynamic>{
      'v': kLobbyProtocolVersion,
      't': kFtAnnounce,
      'sid': sid,
      'gen': gen,
      'hostFp': hostFp,
      'port': tcpPort,
      'mc': memberCount,
      'replyTo': ?replyToNonce,
    };
    _send(frame, InternetAddress(kLobbyMulticastGroup), kLobbyMulticastPort);
  }

  /// Sends a DISC_REQ to the multicast group and returns the nonce used.
  String sendDiscoveryRequest(String localFp) {
    final nonce = _nonce();
    final frame = <String, dynamic>{
      'v': kLobbyProtocolVersion,
      't': kFtDiscoveryRequest,
      'fp': localFp,
      'nonce': nonce,
    };
    _send(frame, InternetAddress(kLobbyMulticastGroup), kLobbyMulticastPort);
    return nonce;
  }

  /// Sends a unicast ANNOUNCE (DISC_RESP) back to the requester.
  void sendDiscoveryResponse({
    required InternetAddress target,
    required int targetPort,
    required String sid,
    required int gen,
    required String hostFp,
    required int tcpPort,
    required int memberCount,
    required String replyToNonce,
  }) {
    final frame = <String, dynamic>{
      'v': kLobbyProtocolVersion,
      't': kFtAnnounce,
      'sid': sid,
      'gen': gen,
      'hostFp': hostFp,
      'port': tcpPort,
      'mc': memberCount,
      'replyTo': replyToNonce,
    };
    _send(frame, target, targetPort);
  }

  void _send(Map<String, dynamic> frame, InternetAddress address, int port) {
    final socket = _socket;
    if (socket == null) return;
    try {
      final bytes = utf8.encode(jsonEncode(frame));
      if (bytes.length > kLobbyMaxUdpBytes) return;
      socket.send(bytes, address, port);
    } catch (_) {}
  }

  String _nonce() => _random.nextInt(0xFFFFFFFF).toRadixString(16).padLeft(8, '0') +
      _random.nextInt(0xFFFFFFFF).toRadixString(16).padLeft(8, '0');

  void close() {
    try {
      _socket?.leaveMulticast(InternetAddress(kLobbyMulticastGroup));
    } catch (_) {}
    _socket?.close();
    _socket = null;
    if (!(_controller?.isClosed ?? true)) _controller?.close();
    _controller = null;
  }
}
