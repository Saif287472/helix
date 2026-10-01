import 'dart:async';
import 'dart:io';

import 'package:helix_remote_server/helix_remote_server.dart';
import 'package:helix_remote_server/src/platform/config/env_file.dart';

/// Starts one server node. Configuration comes from the environment, with
/// `server/.env` (if present) filling in anything the environment does not
/// set. Operators edit `.env` themselves.
Future<void> main() async {
  final log = Log();
  final ServerConfig config;
  try {
    config = ServerConfig.fromEnv(loadEnvironment());
  } on ConfigError catch (e) {
    stderr.writeln(e);
    exitCode = 78; // EX_CONFIG
    return;
  }

  final platform = await HelixPlatform.open(config, log: log);
  final server = await HelixServer.start(platform, allModules());

  final done = Completer<void>();
  Future<void> shutdown(ProcessSignal signal) async {
    if (done.isCompleted) return;
    log.info('shutdown', {'signal': signal.toString()});
    await server.stop();
    done.complete();
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(shutdown);
  await done.future;
}
