import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Whether the configured TURN relay actually answers, as opposed to merely
/// being configured.
///
/// The admin dashboard used to show a green "configured" dot whenever a URL
/// and secret were present - including for a relay that no longer existed.
/// This sends the same STUN Binding Request a WebRTC client starts with and
/// reports whether a matching response came back.
///
/// Checked from the server itself, so a `reachable` result proves coturn is
/// running and answering on that address; it cannot prove the router's port
/// forwarding works for clients outside the network.
class TurnProbe {
  TurnProbe({
    this.timeout = const Duration(seconds: 2),
    this.cacheFor = const Duration(seconds: 60),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration timeout;
  final Duration cacheFor;
  final DateTime Function() _now;

  String _status = 'not_checked';
  DateTime? _checkedAt;
  String? _checkedUrl;
  Future<void>? _inFlight;

  /// The last known status for [url] - `reachable`, `unreachable`,
  /// `checking` or `not_checked` - starting a background re-check when the
  /// cached one is stale. Never waits on the network, because the dashboard
  /// polls the metrics endpoint every few seconds.
  String statusFor(String? url) {
    if (url == null) return 'not_checked';
    final fresh =
        _checkedUrl == url &&
        _checkedAt != null &&
        _now().difference(_checkedAt!) < cacheFor;
    if (!fresh && _inFlight == null) {
      if (_checkedUrl != url) _status = 'checking';
      _inFlight = probe(url)
          .then((ok) {
            _status = ok ? 'reachable' : 'unreachable';
            _checkedUrl = url;
            _checkedAt = _now();
          })
          .whenComplete(() => _inFlight = null);
    }
    return _checkedUrl == url ? _status : 'checking';
  }

  /// Probes one `turn:` URL: a STUN Binding Request over UDP, or a TCP
  /// connect when the URL asks for `transport=tcp`.
  Future<bool> probe(String url) async {
    final target = parseTurnTarget(url);
    if (target == null) return false;
    try {
      final addresses = await InternetAddress.lookup(
        target.host,
      ).timeout(timeout);
      if (addresses.isEmpty) return false;
      final address = addresses.firstWhere(
        (a) => a.type == InternetAddressType.IPv4,
        orElse: () => addresses.first,
      );
      return target.tcp
          ? await _tcpConnects(address, target.port)
          : await _stunAnswers(address, target.port);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _tcpConnects(InternetAddress address, int port) async {
    final socket = await Socket.connect(address, port, timeout: timeout);
    socket.destroy();
    return true;
  }

  Future<bool> _stunAnswers(InternetAddress address, int port) async {
    final socket = await RawDatagramSocket.bind(
      address.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4,
      0,
    );
    try {
      final request = stunBindingRequest();
      final transactionId = request.sublist(8, 20);
      final answered = Completer<bool>();
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram != null &&
            isStunBindingSuccess(datagram.data, transactionId) &&
            !answered.isCompleted) {
          answered.complete(true);
        }
      });
      socket.send(request, address, port);
      return await answered.future.timeout(timeout, onTimeout: () => false);
    } finally {
      socket.close();
    }
  }
}

/// Host, port and transport of a `turn:`/`turns:` URL such as
/// `turn:example.com:3478?transport=udp`. Null when it cannot be parsed.
({String host, int port, bool tcp})? parseTurnTarget(String url) {
  final match = RegExp(
    r'^turns?:([^:?]+)(?::(\d+))?(?:\?transport=(udp|tcp))?$',
  ).firstMatch(url.trim());
  if (match == null) return null;
  final isTurns = url.trim().startsWith('turns:');
  return (
    host: match.group(1)!,
    port: int.tryParse(match.group(2) ?? '') ?? (isTurns ? 5349 : 3478),
    // turns: is TLS over TCP; a TCP connect is the honest check for it.
    tcp: isTurns || match.group(3) == 'tcp',
  );
}

const _stunMagicCookie = 0x2112A442;

/// A 20-byte STUN Binding Request (RFC 5389) with a random transaction id.
Uint8List stunBindingRequest([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = ByteData(20)
    ..setUint16(0, 0x0001) // Binding Request
    ..setUint16(2, 0) // no attributes
    ..setUint32(4, _stunMagicCookie);
  for (var i = 8; i < 20; i++) {
    bytes.setUint8(i, rng.nextInt(256));
  }
  return bytes.buffer.asUint8List();
}

/// Whether [data] is a Binding Success Response to [transactionId].
bool isStunBindingSuccess(Uint8List data, List<int> transactionId) {
  if (data.length < 20) return false;
  final view = ByteData.sublistView(data);
  if (view.getUint16(0) != 0x0101) return false;
  if (view.getUint32(4) != _stunMagicCookie) return false;
  for (var i = 0; i < 12; i++) {
    if (data[8 + i] != transactionId[i]) return false;
  }
  return true;
}
