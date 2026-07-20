import 'dart:io';
import 'package:path/path.dart' as p;

/// Persists a freshly-generated admin token next to the database, so a
/// server operator who misses the one-time console line isn't locked out
/// forever. Shared by bin/server.dart (first boot) and
/// bin/reset_admin_token.dart (recovery).
File writeAdminTokenFile({
  required String dbPath,
  required String serverId,
  required String adminToken,
}) {
  final dbDir = p.dirname(p.absolute(dbPath));
  final file = File(p.join(dbDir, 'ADMIN_TOKEN.txt'));
  file.writeAsStringSync(
    'Helix Admin Token\n'
    '==================\n'
    'Server ID: $serverId\n'
    'Generated: ${DateTime.now().toIso8601String()}\n'
    '\n'
    '$adminToken\n'
    '\n'
    'Use this token (with the backend server URL) to sign in to Helix\n'
    'Admin. This file is written once, the moment the token is first\n'
    'generated -- save the token somewhere safe, then delete this file.\n'
    '\n'
    'Lost the token? Stop the server and run:\n'
    '  dart run bin/reset_admin_token.dart\n'
    'That regenerates the admin token only -- it does not touch accounts,\n'
    'messages, or the federation identity of the server.\n',
  );
  return file;
}
