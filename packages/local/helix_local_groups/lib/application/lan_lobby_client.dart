import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:helix_local_groups/domain/lobby_constants.dart';

/// Manages the TCP connection from a non-host member to the current host.
class LanLobbyClient {
  Socket? _socket;
  StreamSubscription<dynamic>? _sub;
  Timer? _pingTimer;
  Timer? _timeoutTimer;

  Future<void> _writeFuture = Future.value();

  final _frames        = StreamController<Map<String, dynamic>>.broadcast();
  final _disconnected  = StreamController<void>.broadcast();

  Stream<Map<String, dynamic>> get frames       => _frames.stream;
  Stream<void>                 get disconnected  => _disconnected.stream;

  bool get isConnected => _socket != null && !_frames.isClosed;

  /// Connects to the host's lobby TCP server and starts the heartbeat.
  Future<void> connect({
    required String hostIp,
    required int    hostPort,
    required String sid,
    required int    gen,
    required String localFp,
    required String name,
    required String suffix,
  }) async {
    final socket = await Socket.connect(hostIp, hostPort);
    _socket = socket;

    final List<int> pending = [];
    _sub = socket.listen(
      (chunk) {
        if (pending.length + chunk.length > kLobbyMaxTcpFrameBytes) {
          socket.destroy();
          _onDisconnect();
          return;
        }
        pending.addAll(chunk);

        int newlineIndex;
        while ((newlineIndex = pending.indexOf(10)) != -1) {
          final lineBytes = pending.sublist(0, newlineIndex);
          pending.removeRange(0, newlineIndex + 1);

          String line = '';
          try {
            line = utf8.decode(lineBytes, allowMalformed: true);
          } catch (_) {}

          if (line.length > kLobbyMaxTcpFrameBytes) continue;

          try {
            final raw = jsonDecode(line);
            if (raw is! Map<String, dynamic>) continue;
            _resetTimeout(sid: sid, gen: gen);
            if (!_frames.isClosed) _frames.add(raw);
          } catch (_) {}
        }
      },
      onError: (_) => _onDisconnect(),
      onDone: _onDisconnect,
      cancelOnError: false,
    );

    // Send JOIN immediately
    send({
      'v': kLobbyProtocolVersion,
      't': kFtJoin,
      'sid': sid,
      'gen': gen,
      'fp': localFp,
      'name': name,
      'suffix': suffix,
    });

    _startPingTimer(sid: sid, gen: gen);
    _resetTimeout(sid: sid, gen: gen);
  }

  void send(Map<String, dynamic> frame) {
    final socket = _socket;
    if (socket == null || _frames.isClosed) return;
    final bytes = utf8.encode('${jsonEncode(frame)}\n');
    _writeFuture = _writeFuture.then((_) async {
      try {
        socket.add(bytes);
        await socket.flush();
      } catch (_) {
        _onDisconnect();
      }
    });
  }

  void _startPingTimer({required String sid, required int gen}) {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(kLobbyBroadcastInterval, (_) {
      send({'v': kLobbyProtocolVersion, 't': kFtPing, 'sid': sid, 'gen': gen});
    });
  }

  void _resetTimeout({required String sid, required int gen}) {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(kLobbyHostTimeout, _onDisconnect);
  }

  void _onDisconnect() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    if (!_disconnected.isClosed) _disconnected.add(null);
    close();
  }

  Future<void> close() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    await _sub?.cancel();
    try { await _socket?.close(); } catch (_) {}
    _socket = null;
    if (!_frames.isClosed) _frames.close();
    if (!_disconnected.isClosed) _disconnected.close();
  }
}
