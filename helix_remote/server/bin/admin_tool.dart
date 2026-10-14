import 'dart:io';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/helix_remote_server.dart';
import 'package:helix_remote_server/src/modules/admin/module.dart';
import 'package:helix_remote_server/src/platform/config/env_file.dart';

const _usage = '''
Operator maintenance, run on the server's machine from helix_remote/server
(it reads server/.env like bin/server.dart):

  dart run bin/admin_tool.dart reset-password

reset-password asks for the new operator password twice (it is not shown),
sets it (creating the operator if there is none), ends every admin session
and clears every sign-in lock. The action is written to the audit log.''';

/// Operator maintenance (review B-07). A configuration problem exits with 78
/// (EX_CONFIG), a usage problem with 64 (EX_USAGE), a refused password with
/// 65 (EX_DATAERR).
Future<void> main(List<String> args) async {
  if (args.length != 1 || args.single != 'reset-password') {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  final password = _readNewPassword();
  if (password == null) {
    exitCode = 65;
    return;
  }
  HelixPlatform? platform;
  try {
    final config = ServerConfig.fromEnv(loadEnvironment());
    platform = await HelixPlatform.open(config);
    final context = platform.moduleContext();
    final modules = [for (final create in allModules()) create(context)];
    await modules.whereType<AdminModule>().single.resetPassword(password);
    stdout.writeln(
      'The admin password is set. Every admin session has ended: sign in '
      'again in the console.',
    );
  } on ConfigError catch (e) {
    stderr.writeln(e);
    exitCode = 78;
  } on ApiError catch (e) {
    stderr.writeln(e.message ?? 'The password was refused.');
    exitCode = 65;
  } on Object catch (e) {
    // The type only: a message could quote the database URL.
    stderr.writeln(
      'The change failed (${e.runtimeType}). If this server has never '
      'started, run `dart run bin/migrate.dart` first.',
    );
    exitCode = 1;
  } finally {
    await platform?.close();
  }
}

/// Reads the password from the terminal without echo, twice; from a pipe,
/// one line. Never printed. Null (with the reason on stderr) if it is
/// missing or the two do not match.
String? _readNewPassword() {
  final terminal = stdin.hasTerminal;
  String? ask(String prompt) {
    if (!terminal) return stdin.readLineSync();
    stdout.write(prompt);
    stdin.echoMode = false;
    try {
      return stdin.readLineSync();
    } finally {
      stdin.echoMode = true;
      stdout.writeln();
    }
  }

  final first = ask('New admin password (12 to 256 characters): ');
  if (first == null || first.isEmpty) {
    stderr.writeln('No password was given.');
    return null;
  }
  if (terminal && ask('Type it again: ') != first) {
    stderr.writeln('The two passwords do not match.');
    return null;
  }
  return first;
}
