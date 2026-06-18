import 'dart:async';
import 'dart:io';

import 'package:helix_local_protocol/application/contracts/use_cases.dart';
import 'package:helix/application/tcp_server/tcp_server_use_case_impl.dart';

/// Singleton TCP/TLS server that survives widget lifecycle.
///
/// Binds a [SecureServerSocket] on an ephemeral port and exposes incoming
/// [SecureSocket] connections as a broadcast stream. Intended to be created
/// once by a Riverpod provider and kept alive for the app lifetime.
class TcpServerService {
  static TcpServerUseCase? globalUseCase;
  static final _defaultUseCase = TcpServerUseCaseImpl();

  final TcpServerUseCase? _useCase;

  TcpServerService({this._useCase});

  TcpServerUseCase get _effectiveUseCase =>
      _useCase ?? globalUseCase ?? _defaultUseCase;

  /// Whether the server is currently accepting connections.
  bool get isRunning => _effectiveUseCase.isRunning;

  /// The port the server is listening on, or 0 if not running.
  int get port => _effectiveUseCase.port;

  /// Incoming TLS connections from peers.
  Stream<SecureSocket> get incomingConnections =>
      _effectiveUseCase.incomingConnections;

  /// Start listening on an ephemeral port.
  ///
  /// Binds to [InternetAddress.anyIPv4] with port 0, letting the OS assign a
  /// free port.  Each accepted connection is forwarded to
  /// [incomingConnections].
  Future<void> start(SecurityContext context) =>
      _effectiveUseCase.start(context);

  /// Stop the server and close all pending connections.
  Future<void> stop() => _effectiveUseCase.stop();

  /// Permanently disposes this service, closing the connection stream.
  void dispose() => _effectiveUseCase.dispose();
}
