import 'dart:convert';

import 'package:crypto/crypto.dart';

enum MigrationPhase { expand, migrate, contract }

final class BackendMigration {
  const BackendMigration({
    required this.version,
    required this.phase,
    required this.name,
    required this.sql,
    required this.checksum,
    this.requiresBackup = true,
  });

  final int version;
  final MigrationPhase phase;
  final String name;
  final String sql;
  final String checksum;
  final bool requiresBackup;

  String computedChecksum() => sha256.convert(utf8.encode(sql)).toString();

  void validate() {
    if (checksum != computedChecksum()) {
      throw StateError('Migration checksum mismatch for $version:$name');
    }
  }
}

final class BackendMigrationPlan {
  BackendMigrationPlan(Iterable<BackendMigration> migrations)
    : migrations = List.unmodifiable(migrations) {
    _validateOrder();
  }

  final List<BackendMigration> migrations;

  Iterable<BackendMigration> pendingAfter(int currentVersion) =>
      migrations.where((migration) => migration.version > currentVersion);

  void validateChecksums() {
    for (final migration in migrations) {
      migration.validate();
    }
  }

  void _validateOrder() {
    var lastVersion = 0;
    final phasesByVersion = <int, List<MigrationPhase>>{};
    for (final migration in migrations) {
      if (migration.version < lastVersion) {
        throw ArgumentError('Migrations must be sorted by version.');
      }
      lastVersion = migration.version;
      phasesByVersion
          .putIfAbsent(migration.version, () => <MigrationPhase>[])
          .add(migration.phase);
    }

    for (final entry in phasesByVersion.entries) {
      final phases = entry.value;
      final numeric = phases.map((phase) => phase.index).toList();
      final sorted = [...numeric]..sort();
      if (numeric.join(',') != sorted.join(',')) {
        throw ArgumentError(
          'Migration ${entry.key} must run expand, migrate, contract order.',
        );
      }
    }
  }
}

final class BackendMigrationPolicy {
  const BackendMigrationPolicy({
    required this.backupVerified,
    required this.rollbackRunbook,
  });

  final bool backupVerified;
  final Uri rollbackRunbook;

  void validateFor(BackendMigration migration) {
    migration.validate();
    if (migration.requiresBackup && !backupVerified) {
      throw StateError(
        'Backup verification is required before migration ${migration.version}.',
      );
    }
  }
}
