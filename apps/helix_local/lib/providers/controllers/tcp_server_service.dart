import 'dart:async';
import 'dart:io';

import 'package:helix_local_protocol/application/contracts/use_cases.dart';
class TcpServerService {
  final TcpServerUseCase _useCase;

  TcpServerService({required this._useCase});

  bool get isRunning => _useCase.isRunning;

  int get port => _useCase.port;

  Stream<SecureSocket> get incomingConnections => _useCase.incomingConnections;

  Future<void> start(SecurityContext context) => _useCase.start(context);

  Future<void> stop() => _useCase.stop();

  void dispose() => _useCase.dispose();
}
