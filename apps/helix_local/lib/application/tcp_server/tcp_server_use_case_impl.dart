import 'dart:async';
import 'dart:io';

import 'package:helix_local_protocol/application/contracts/use_cases.dart';

class TcpServerUseCaseImpl implements TcpServerUseCase {
  SecureServerSocket? _server;
  final _connectionController = StreamController<SecureSocket>.broadcast();
  StreamSubscription<SecureSocket>? _serverSub;
  bool _running = false;
  bool _disposed = false;

  @override
  bool get isRunning => _running;

  @override
  int get port => _server?.port ?? 0;

  @override
  Stream<SecureSocket> get incomingConnections => _connectionController.stream;

  @override
  Future<void> start(SecurityContext context) async {
    if (_running) return;

    try {
      final secureServer = await SecureServerSocket.bind(
        InternetAddress.anyIPv4,
        0, // ephemeral port
        context,
      );

      _server = secureServer;
      _running = true;

      _serverSub = secureServer.listen(
        (socket) {
          if (!_connectionController.isClosed) {
            _connectionController.add(socket);
          }
        },
        onError: (Object error) {
          if (!_connectionController.isClosed) {
            _connectionController.addError(error);
          }
        },
        onDone: () {
          _running = false;
        },
      );
    } catch (e) {
      _running = false;
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _serverSub?.cancel();
    _serverSub = null;
    await _server?.close();
    _server = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
    _connectionController.close();
  }
}
