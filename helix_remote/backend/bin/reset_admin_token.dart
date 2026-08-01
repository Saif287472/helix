// ignore_for_file: avoid_print
//
// Offline recovery tool for a lost Helix Admin token. If the server is
// currently RUNNING, prefer the live pairing flow instead -- it needs no
// downtime:
//
//   curl -s -X POST http://127.0.0.1:8080/api/v1/admin-pairing/generate
//
// then enter the printed code in the Helix Admin app's "Enter Pairing
// Code" option. This script is for when the server won't start at all, or
// you have no network access to it but do have a shell.
//
// The server MUST be stopped first: this opens the same database file
// server.dart does, and SQLite only allows one writer at a time.
//
//   nssm stop HelixBackend        (or however you run the server)
//   dart run bin/reset_admin_token.dart
//   nssm start HelixBackend
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/server_identity.dart';
import 'src/admin_token_file.dart';
import 'src/terminal_qr.dart';

void main() async {
  if (Platform.isWindows) {
    DynamicLibrary.open('sqlite3.dll');
  }

  final dbPath =
      Platform.environment['HELIX_REMOTE_DB_PATH'] ?? 'remote_backend.db';

  if (!File(dbPath).existsSync()) {
    stderr.writeln(
      'No database found at "$dbPath". This tool resets the admin token for '
      'an existing server -- start the server normally first if this is a '
      'brand new deployment (it prints the token on first boot).',
    );
    exit(1);
  }

  late final Database sqliteDb;
  try {
    sqliteDb = sqlite3.open(dbPath);
  } on SqliteException catch (e) {
    stderr.writeln(
      'Could not open "$dbPath": $e\n'
      'If the server is still running, stop it first -- SQLite only allows '
      'one writer at a time.',
    );
    exit(1);
  }

  final db = BackendDatabase(sqliteDb);
  try {
    final serverId = db.getServerConfig('server_id');
    if (serverId == null) {
      stderr.writeln(
        'This database has no server identity yet -- start the server '
        'normally instead; it will bootstrap both the identity and the '
        'admin token and print the token on first boot.',
      );
      exit(1);
    }

    final identity = await rotateAdminToken(db);
    final newToken = identity.adminToken!;

    final tokenFile = writeAdminTokenFile(
      dbPath: dbPath,
      serverId: identity.serverId,
      adminToken: newToken,
    );

    print('==================================================');
    print('New Helix Admin Token generated.');
    print('Server ID: ${identity.serverId}');
    print('Token: $newToken');
    print('Also saved to: ${tokenFile.path}');
    print('The old admin token, if any, no longer works.');
    try {
      print('');
      print('Scan with the Helix Admin app to fill in the token:');
      print(renderTerminalQr(newToken));
    } catch (_) {
      // Cosmetic only - never let QR rendering block token reset.
    }
    final envOverride = Platform.environment['HELIX_REMOTE_ADMIN_TOKEN'];
    if (envOverride != null && envOverride.isNotEmpty) {
      print('');
      print(
        'NOTE: HELIX_REMOTE_ADMIN_TOKEN is set in this environment and '
        'takes priority over the generated token above whenever the server '
        'runs with it set -- unset it if you want the token above to work.',
      );
    }
    print('==================================================');
  } finally {
    db.close();
  }
}
