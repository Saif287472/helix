import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:helix_local_groups/domain/lobby_constants.dart';

/// A connected client managed by the host's TCP server.
class _ClientConn {
  _ClientConn(this.socket) {
    _writeFuture = Future.value();
    final List<int> pending = [];
    _sub = socket.listen(
      (chunk) {
        if (pending.length + chunk.length > kLobbyMaxTcpFrameBytes) {
          socket.destroy();
          close();
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
            if (raw is Map<String, dynamic>) {
              if (!_inbound.isClosed) _inbound.add(raw);
            }
          } catch (_) {}
        }
      },
      onError: (_) => close(),
      onDone: () => close(),
      cancelOnError: false,
    );
  }

  final Socket socket;
  String fp = '';
  late final StreamSubscription<dynamic> _sub;
  final _inbound = StreamController<Map<String, dynamic>>.broadcast();
  late Future<void> _writeFuture;
  DateTime _lastSeen = DateTime.now();

  Stream<Map<String, dynamic>> get frames => _inbound.stream;
  bool get isClosed => _inbound.isClosed;
  DateTime get lastSeen => _lastSeen;
  void touch() => _lastSeen = DateTime.now();

  void send(Map<String, dynamic> frame) {
    if (isClosed) return;
    final bytes = utf8.encode('${jsonEncode(frame)}\n');
    _writeFuture = _writeFuture.then((_) async {
      try {
        socket.add(bytes);
        await socket.flush();
      } catch (_) {
        await close();
      }
    });
  }

  Future<void> close() async {
    await _sub.cancel();
    if (!_inbound.isClosed) _inbound.close();
    try {
      await socket.close();
    } catch (_) {}
  }
}

/// TCP server that manages connections from lobby members (host role).
class LanLobbyServer {
  ServerSocket? _server;
  Timer? _pingTimer;

  final _clients = <String, _ClientConn>{}; // fp → conn
  final _pending = <_ClientConn>[]; // not yet identified

  final _joinRequests =
      StreamController<
        ({Socket socket, Map<String, dynamic> frame})
      >.broadcast();
  final _clientFrames =
      StreamController<({String fp, Map<String, dynamic> frame})>.broadcast();
  final _disconnections = StreamController<String>.broadcast();

  Stream<({Socket socket, Map<String, dynamic> frame})> get joinRequests =>
      _joinRequests.stream;
  Stream<({String fp, Map<String, dynamic> frame})> get clientFrames =>
      _clientFrames.stream;
  Stream<String> get disconnections => _disconnections.stream;

  int get port => _server?.port ?? 0;
  bool get isOpen => _server != null;

  Future<void> open({required String sid, required int gen}) async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _server!.listen(
      (socket) => _acceptClient(socket, sid: sid, gen: gen),
      onError: (_) {},
      cancelOnError: false,
    );
    _startPingTimer(sid: sid, gen: gen);
  }

  void _acceptClient(Socket socket, {required String sid, required int gen}) {
    final conn = _ClientConn(socket);
    _pending.add(conn);

    final joinTimer = Timer(kLobbyHostTimeout, () {
      if (_pending.remove(conn)) {
        conn.close();
      }
    });

    conn.frames.listen(
      (frame) {
        conn.touch();
        final type = frame['t'];
        final fp = frame['fp'];
        final name = frame['name'];
        final gen = frame['gen'];

        if (type is! String ||
            fp is! String ||
            fp.isEmpty ||
            (name != null && name is! String) ||
            (gen != null && gen is! int)) {
          conn.close().catchError((_) {});
          return;
        }

        if (type == kFtJoin) {
          joinTimer.cancel();
          _pending.remove(conn);
          conn.fp = fp;
          final previous = _clients[fp];
          if (previous != null && !identical(previous, conn)) {
            previous.close().catchError((_) {});
          }
          _clients[fp] = conn;
          _joinRequests.add((socket: socket, frame: frame));
        } else if (type == kFtPong) {
          // heartbeat handled above via touch()
        } else {
          if (conn.fp.isNotEmpty && !_clientFrames.isClosed) {
            _clientFrames.add((fp: conn.fp, frame: frame));
          }
        }
      },
      onDone: () {
        joinTimer.cancel();
        _pending.remove(conn);
        final fp = conn.fp;
        if (fp.isNotEmpty && identical(_clients[fp], conn)) {
          _clients.remove(fp);
          if (!_disconnections.isClosed) _disconnections.add(fp);
        }
      },
      cancelOnError: false,
    );
  }

  void _startPingTimer({required String sid, required int gen}) {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(kLobbyBroadcastInterval, (_) {
      final ping = {
        'v': kLobbyProtocolVersion,
        't': kFtPing,
        'sid': sid,
        'gen': gen,
      };
      final now = DateTime.now();
      final stale = <String>[];
      for (final entry in _clients.entries) {
        if (now.difference(entry.value.lastSeen) > kLobbyHostTimeout) {
          stale.add(entry.key);
        } else {
          entry.value.send(ping);
        }
      }
      for (final fp in stale) {
        _clients.remove(fp)?.close();
        if (!_disconnections.isClosed) _disconnections.add(fp);
      }
    });
  }

  /// Broadcasts a frame to all identified clients.
  void broadcastFrame(Map<String, dynamic> frame, {String? exceptFp}) {
    for (final entry in _clients.entries) {
      if (entry.key == exceptFp) continue;
      entry.value.send(frame);
    }
  }

  /// Sends a frame to a single identified client.
  void sendToFp(String fp, Map<String, dynamic> frame) {
    _clients[fp]?.send(frame);
  }

  List<String> get connectedFps => List.unmodifiable(_clients.keys);

  Future<void>? _closeFuture;
  Future<void> close() => _closeFuture ??= _closeImpl();

  Future<void> _closeImpl() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    final clients = {..._pending, ..._clients.values}.toList();
    _pending.clear();
    _clients.clear();
    for (final c in clients) {
      await c.close().catchError((_) {});
    }
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
    if (!_joinRequests.isClosed) {
      await _joinRequests.close().catchError((_) {});
    }
    if (!_clientFrames.isClosed) {
      await _clientFrames.close().catchError((_) {});
    }
    if (!_disconnections.isClosed) {
      await _disconnections.close().catchError((_) {});
    }
  }
}
