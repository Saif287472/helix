import 'dart:io';

import 'package:helix_remote_server/helix_remote_server.dart';
import 'package:helix_remote_server/src/platform/config/env_file.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/platform_migrations.dart';

/// Applies migrations and exits (deploy step; also safe to skip, since
/// every node migrates at start under an advisory lock).
Future<void> main() async {
  final config = ServerConfig.fromEnv(loadEnvironment());
  final platform = await HelixPlatform.open(config);
  try {
    final context = platform.moduleContext();
    final modules = [for (final create in allModules()) create(context)];
    final report = await MigrationRunner(platform.db, platform.schemas).run([
      platformMigrations,
      for (final m in modules)
        MigrationSet(module: m.name, migrations: m.migrations),
    ]);
    stdout.writeln(
      report.applied.isEmpty
          ? 'Up to date.'
          : 'Applied: ${report.applied.join(', ')}',
    );
  } finally {
    await platform.close();
  }
}
