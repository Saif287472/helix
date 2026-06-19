// ignore_for_file: avoid_print
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:helix_remote_backend/src/server_impl.dart';

void main() async {
  final port =
      int.tryParse(Platform.environment['HELIX_REMOTE_PORT'] ?? '') ?? 8080;
  final host = Platform.environment['HELIX_REMOTE_HOST'] ?? '127.0.0.1';
  final devMode = Platform.environment['HELIX_REMOTE_DEV_MODE'] == '1';
  final jwtSecret = Platform.environment['HELIX_REMOTE_JWT_SECRET'];
  if (!devMode && (jwtSecret == null || jwtSecret.length < 32)) {
    stderr.writeln(
      'HELIX_REMOTE_JWT_SECRET must be set to at least 32 bytes outside explicit HELIX_REMOTE_DEV_MODE=1.',
    );
    exit(78);
  }
  final resolvedJwtSecret =
      jwtSecret ?? 'helix_remote_explicit_dev_mode_secret_min_32_bytes';
  final dbPath =
      Platform.environment['HELIX_REMOTE_DB_PATH'] ?? 'remote_backend.db';

  print('Starting Helix Remote backend database at: $dbPath');
  final sqliteDb = sqlite3.open(dbPath);

  print('Initializing server configuration...');
  final server = BackendServer.create(
    sqliteDb: sqliteDb,
    jwtSecret: resolvedJwtSecret,
  );

  print('Starting server on http://$host:$port...');
  await server.start(host, port);
  print('Helix Remote backend monolith is online.');

  // Handle graceful shutdown
  ProcessSignal.sigint.watch().listen((signal) async {
    print('Shutdown signal (SIGINT) received. Disposing services...');
    await server.stop();
    print('Server cleanly shutdown.');
    exit(0);
  });

  ProcessSignal.sigterm.watch().listen((signal) async {
    print('Shutdown signal (SIGTERM) received. Disposing services...');
    await server.stop();
    print('Server cleanly shutdown.');
    exit(0);
  });
}
