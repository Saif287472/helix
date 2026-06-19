// ignore_for_file: avoid_print
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:helix_remote_backend/src/server_impl.dart';

void main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final host = Platform.environment['HOST'] ?? '127.0.0.1';
  final jwtSecret =
      Platform.environment['JWT_SECRET'] ??
      'helix_development_master_secret_key_change_in_production';
  final dbPath = Platform.environment['DB_PATH'] ?? 'remote_backend.db';

  print('Starting Helix Remote backend database at: $dbPath');
  final sqliteDb = sqlite3.open(dbPath);

  print('Initializing server configuration...');
  final server = BackendServer.create(sqliteDb: sqliteDb, jwtSecret: jwtSecret);

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
