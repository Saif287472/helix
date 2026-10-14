import 'dart:async';
import 'dart:io';

import 'package:helix_remote_server/helix_remote_server.dart';
import 'package:helix_remote_server/src/platform/config/env_file.dart';
import 'package:helix_remote_server/src/platform/startup.dart';

/// Starts one server node. Configuration comes from the environment, with
/// `server/.env` (if present) filling in anything the environment does not
/// set. Operators edit `.env` themselves.
///
/// Any configuration problem, core or module (pepper, SMS, TURN, push,
/// federation), prints the variable names and exits with 78 (EX_CONFIG).
///
/// A database that is not reachable yet (the PC just booted) is retried for
/// a minute. Ctrl+C stops gracefully; so does creating the file named by
/// `HELIX_STOP_FILE`, which is how the Windows scheduled task stops it
/// (`deploy/windows/`).
Future<void> main() async {
  final ServerConfig config;
  try {
    config = ServerConfig.fromEnv(loadEnvironment());
  } on ConfigError catch (e) {
    stderr.writeln(e);
    exitCode = 78; // EX_CONFIG
    return;
  }

  FileSink? file;
  final logFile = config.logFile;
  if (logFile != null) {
    try {
      file = FileSink.open(logFile, keepDays: config.logKeepDays);
    } on FileSystemException {
      stderr.writeln(
        'Invalid configuration:\n  HELIX_LOG_FILE cannot be opened for writing',
      );
      exitCode = 78;
      return;
    }
  }
  final log = Log(
    sink: file == null
        ? const StdoutSink()
        : TeeSink([const StdoutSink(), file]),
  );

  HelixPlatform? platform;
  final HelixServer server;
  try {
    platform = await retryStartup<HelixPlatform>(
      () => HelixPlatform.open(config, log: log),
      log: log,
    );
    server = await HelixServer.start(platform, allModules());
  } on ConfigError catch (e) {
    stderr.writeln(e);
    exitCode = 78;
    await platform?.close();
    await file?.close();
    return;
  }

  final done = Completer<void>();
  Future<void> shutdown(ProcessSignal signal) async {
    if (done.isCompleted) return;
    log.info('shutdown', {'signal': signal.toString()});
    await server.stop();
    await file?.close();
    done.complete();
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(shutdown);
  final stopFile = config.env['HELIX_STOP_FILE']?.trim();
  if (stopFile != null && stopFile.isNotEmpty) {
    unawaited(
      watchStopFile(stopFile).then((_) => shutdown(ProcessSignal.sigint)),
    );
  }
  await done.future;
}
