import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/schema_names.dart';

/// One schema change of one module (ADR-025).
///
/// Migrations are Dart constants rather than `.sql` files so they compile
/// into the server binary. [sql] receives the module's schema name. Applied
/// migrations are checksummed: editing one that already ran stops the
/// server, so history is never rewritten. Changes follow expand → migrate →
/// contract: never drop or rename something the previous release still uses.
final class Migration {
  const Migration(this.version, this.name, this.sql);

  final int version;
  final String name;
  final String Function(String schema) sql;

  /// Over the SQL rendered with a placeholder schema, so a migration has the
  /// same checksum under any schema prefix.
  String get checksum =>
      crypto.sha256.convert(utf8.encode(sql(r'$schema'))).toString();
}

final class MigrationSet {
  const MigrationSet({required this.module, required this.migrations});

  final String module;
  final List<Migration> migrations;
}

final class MigrationReport {
  const MigrationReport(this.applied);

  /// `module:version` of migrations applied by this run.
  final List<String> applied;
}

/// Thrown when an applied migration's checksum changed or versions are not
/// strictly increasing.
final class MigrationIntegrityError extends Error {
  MigrationIntegrityError(this.message);

  final String message;

  @override
  String toString() => 'MigrationIntegrityError: $message';
}

/// Applies module migrations in order. Safe to run on every node at start:
/// an advisory lock lets one node migrate while the others wait.
final class MigrationRunner {
  MigrationRunner(this.db, this.schemas);

  final Db db;
  final SchemaNames schemas;

  static const _lockKey = 7240001;

  String get _table => '${schemas.platform}.schema_migrations';

  Future<MigrationReport> run(List<MigrationSet> sets) async {
    _validate(sets);
    return db.tx((tx) async {
      // Transaction-scoped: released at commit or rollback.
      await tx.execute('SELECT pg_advisory_xact_lock($_lockKey)');
      await tx.execute('CREATE SCHEMA IF NOT EXISTS ${schemas.platform}');
      await tx.execute('''
        CREATE TABLE IF NOT EXISTS $_table (
          module text NOT NULL,
          version integer NOT NULL,
          name text NOT NULL,
          checksum text NOT NULL,
          applied_at timestamptz NOT NULL DEFAULT now(),
          PRIMARY KEY (module, version)
        )''');
      final appliedRows = await tx.query(
        'SELECT module, version, checksum FROM $_table',
      );
      final applied = {
        for (final r in appliedRows)
          '${r.string('module')}:${r.integer('version')}': r.string('checksum'),
      };
      final done = <String>[];
      for (final set in sets) {
        final schema = schemas.of(set.module);
        await tx.execute('CREATE SCHEMA IF NOT EXISTS $schema');
        for (final migration in set.migrations) {
          final key = '${set.module}:${migration.version}';
          final checksum = migration.checksum;
          final existing = applied[key];
          if (existing != null) {
            if (existing != checksum) {
              throw MigrationIntegrityError(
                'migration $key (${migration.name}) changed after it was applied',
              );
            }
            continue;
          }
          await tx.execute(migration.sql(schema));
          await tx.execute(
            'INSERT INTO $_table (module, version, name, checksum) '
            'VALUES (@module:text, @version:int4, @name:text, @checksum:text)',
            {
              'module': set.module,
              'version': migration.version,
              'name': migration.name,
              'checksum': checksum,
            },
          );
          done.add(key);
        }
      }
      return MigrationReport(done);
    }, retries: 0);
  }

  void _validate(List<MigrationSet> sets) {
    final modules = <String>{};
    for (final set in sets) {
      if (!modules.add(set.module)) {
        throw MigrationIntegrityError('module ${set.module} listed twice');
      }
      var last = 0;
      for (final m in set.migrations) {
        if (m.version <= last) {
          throw MigrationIntegrityError(
            '${set.module} migrations must have strictly increasing versions',
          );
        }
        last = m.version;
      }
    }
  }
}
