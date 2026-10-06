import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_cli/src/v2/cli_args.dart';
import 'package:helix_remote_db/helix_remote_db.dart';

/// Where the CLI keeps its state: a directory with the encrypted database
/// (`helix.db`), optionally the database key (`db.key`) and the server
/// address (`config.json`, not secret).
///
/// The database key comes from the environment variable named by
/// [keyEnvName] (64 hex characters) or from `db.key`; with neither, the
/// first command that needs the database makes a key file. The key is never
/// printed. A key file next to the database protects against nothing a
/// stolen directory exposes: for anything but a test machine keep the key
/// in the environment of a password manager.
final class CliHome {
  CliHome(this.directory, {this._env = const {}});

  static const keyEnvName = 'HELIX_DB_KEY';

  final Directory directory;
  final Map<String, String> _env;

  File get databaseFile => File('${directory.path}/helix.db');
  File get keyFile => File('${directory.path}/db.key');
  File get configFile => File('${directory.path}/config.json');

  /// The default home: `$HELIX_CLI_HOME` or `~/.helix_cli_v2`.
  static CliHome resolve(String? option, Map<String, String> env) {
    final path =
        option ??
        env['HELIX_CLI_HOME'] ??
        '${env['HOME'] ?? env['USERPROFILE'] ?? '.'}/.helix_cli_v2';
    return CliHome(Directory(path), env: env);
  }

  /// The saved server address, if any.
  String? savedServer() {
    if (!configFile.existsSync()) return null;
    try {
      final json = jsonDecode(configFile.readAsStringSync());
      return json is Map ? json['server'] as String? : null;
    } on Object {
      return null;
    }
  }

  void saveServer(String server) {
    directory.createSync(recursive: true);
    configFile.writeAsStringSync(jsonEncode({'server': server}));
  }

  /// The database key. With [create] a missing key is generated into
  /// `db.key` (unless the environment names the key's variable and it is
  /// unset: then there is nothing to create and nothing to find).
  DatabaseKey key({required bool create}) {
    final fromEnv = _env[keyEnvName];
    if (fromEnv != null && fromEnv.isNotEmpty) return _parse(fromEnv.trim());
    if (keyFile.existsSync()) return _parse(keyFile.readAsStringSync().trim());
    if (!create) {
      throw CliError(
        'no database key: set $keyEnvName or run a command that creates the '
        'account first (register, login or link)',
      );
    }
    final key = DatabaseKey.generate();
    directory.createSync(recursive: true);
    keyFile.writeAsStringSync(
      key.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    );
    return key;
  }

  static DatabaseKey _parse(String hex) {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex)) {
      throw CliError('the database key must be 64 hexadecimal characters');
    }
    return DatabaseKey([
      for (var i = 0; i < 64; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }
}
