// ignore_for_file: avoid_print
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:helix_remote_backend/src/admin_password.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/startup_env.dart';

void main(List<String> args) async {
  if (Platform.isWindows) {
    DynamicLibrary.open('sqlite3.dll');
  }

  final env = loadEffectiveEnv();
  final dbPath = env['HELIX_REMOTE_DB_PATH'] ?? 'remote_backend.db';

  if (!File(dbPath).existsSync()) {
    stderr.writeln('No database found at "$dbPath".');
    exit(1);
  }

  final Database sqliteDb;
  try {
    sqliteDb = sqlite3.open(dbPath);
  } on SqliteException catch (e) {
    stderr.writeln(
      'Could not open "$dbPath": $e\n'
      'If the server is currently running, stop it first.',
    );
    exit(1);
  }

  final db = BackendDatabase(sqliteDb);
  try {
    if (args.isEmpty) {
      db.deleteServerConfig('admin_password_hash');
      db.deleteServerConfig('admin_password_salt');
      print('==================================================');
      print('Database admin password cleared.');
      print('First-time setup mode is now active.');
      print('Connect with the Helix Admin App to set a new password,');
      print('or set HELIX_REMOTE_ADMIN_PASSWORD in .env.');
      print('==================================================');
    } else {
      final newPassword = args.first;
      if (newPassword.trim().length < 6) {
        stderr.writeln('Error: Password must be at least 6 characters long.');
        exit(1);
      }
      final salt = generatePasswordSalt();
      final hash = hashAdminPassword(newPassword, salt);
      db.setServerConfig('admin_password_salt', salt);
      db.setServerConfig('admin_password_hash', hash);
      print('==================================================');
      print('Admin password updated successfully in database.');
      print('You can now log in using this password in Helix Admin.');
      print('==================================================');
    }
  } finally {
    db.close();
  }
}
