import 'dart:io';
import 'dart:math';

import 'package:postgres/postgres.dart';

/// Environment variable holding the test database URL, for example
/// `postgresql://helix:<password>@127.0.0.1:5432/helix_test?sslmode=disable`.
///
/// Locally it is set once by `tool/setup_local_postgres.ps1`. CI sets it to
/// its Postgres service container.
const testDatabaseUrlVariable = 'HELIX_TEST_DATABASE_URL';

/// When `1`, a missing [testDatabaseUrlVariable] fails the tests instead of
/// skipping them. CI sets it so database tests can never silently not run.
const requireTestDatabaseVariable = 'HELIX_REQUIRE_TEST_DATABASE';

String? get _url {
  final value = Platform.environment[testDatabaseUrlVariable];
  return (value == null || value.trim().isEmpty) ? null : value.trim();
}

bool get _required => Platform.environment[requireTestDatabaseVariable] == '1';

/// The `skip:` value for database tests: null when a database is configured,
/// otherwise the reason. Throws when a database is required but missing.
String? get databaseTestSkipReason {
  if (_url != null) return null;
  if (_required) {
    throw StateError(
      '$testDatabaseUrlVariable is not set but $requireTestDatabaseVariable=1.',
    );
  }
  return '$testDatabaseUrlVariable is not set; see server/README.md to '
      'create the local test database.';
}

/// Opens a connection to the test database. The URL is never printed: it
/// holds a password.
Future<Connection> openTestConnection() {
  final url = _url;
  if (url == null) {
    throw StateError(databaseTestSkipReason ?? 'no test database configured');
  }
  return Connection.openFromUrl(url);
}

final Random _random = Random.secure();

/// Runs [body] with a connection whose `search_path` is a fresh, uniquely
/// named schema, and drops the schema afterwards, so tests never see each
/// other's tables and can run in parallel against one database.
Future<T> withTestSchema<T>(
  Future<T> Function(Connection connection, String schema) body,
) async {
  final connection = await openTestConnection();
  final suffix = List.generate(
    12,
    (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[_random.nextInt(36)],
  ).join();
  final schema = 'test_$suffix';
  try {
    await connection.execute('CREATE SCHEMA $schema');
    await connection.execute('SET search_path TO $schema');
    return await body(connection, schema);
  } finally {
    try {
      await connection.execute('DROP SCHEMA IF EXISTS $schema CASCADE');
    } finally {
      await connection.close();
    }
  }
}
