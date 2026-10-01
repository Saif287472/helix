import 'dart:io';
import 'dart:math';

import 'package:helix_remote_server/helix_remote_server.dart';
import 'package:helix_remote_server/src/platform/blobs/object_storage.dart';
import 'package:helix_remote_server/src/platform/clock.dart';
import 'package:helix_remote_server/src/platform/db/postgres_db.dart';
import 'package:postgres/postgres.dart' as pg;

import 'test_database.dart';

final Random _random = Random.secure();

String randomPrefix() =>
    't${List.generate(8, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[_random.nextInt(36)]).join()}_';

/// Base64url of 32 fixed bytes: a test-only JWT key.
const testJwtKey = 'dGVzdC1vbmx5LWp3dC1rZXktdGhhdC1pcy0zMi1ieXRlcw';

/// A config for tests: the test database, a fresh schema prefix, a
/// throwaway blob directory, port 0.
ServerConfig testConfig({
  required String prefix,
  Map<String, String> extra = const {},
}) {
  final url = Platform.environment[testDatabaseUrlVariable]!;
  return ServerConfig.fromEnv({
    'HELIX_DATABASE_URL': url,
    'HELIX_PORT': '0',
    'HELIX_JWT_KEYS': '{"test":"$testJwtKey"}',
    'HELIX_SCHEMA_PREFIX': prefix,
    'HELIX_BLOB_DIR': Directory.systemTemp.createTempSync('helix_blobs_').path,
    'HELIX_DEV_MODE': 'true',
    ...extra,
  });
}

/// A platform on the test database under its own schema prefix. Call
/// [dispose] in tearDown: it closes connections and drops the schemas.
final class TestPlatform {
  TestPlatform._(this.platform, this.prefix, this.log);

  final HelixPlatform platform;
  final String prefix;
  final MemorySink log;

  static Future<TestPlatform> open({
    Map<String, String> extra = const {},
    Clock clock = const SystemClock(),
    ObjectStorage? blobs,
  }) async {
    final prefix = randomPrefix();
    final sink = MemorySink();
    final platform = await HelixPlatform.open(
      testConfig(prefix: prefix, extra: extra),
      log: Log(sink: sink, minLevel: LogLevel.debug),
      clock: clock,
      blobs: blobs,
    );
    return TestPlatform._(platform, prefix, sink);
  }

  Future<void> dispose() async {
    await platform.close();
    await dropSchemas(prefix);
    final dir = platform.config.blobs.directory;
    if (dir != null && Directory(dir).existsSync()) {
      Directory(dir).deleteSync(recursive: true);
    }
  }
}

/// Drops every schema whose name starts with [prefix].
Future<void> dropSchemas(String prefix) async {
  final connection = await pg.Connection.openFromUrl(
    Platform.environment[testDatabaseUrlVariable]!,
  );
  try {
    final rows = await connection.execute(
      pg.Sql.named(
        "SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE @p",
      ),
      parameters: {'p': '$prefix%'},
    );
    for (final row in rows) {
      await connection.execute('DROP SCHEMA IF EXISTS "${row[0]}" CASCADE');
    }
  } finally {
    await connection.close();
  }
}

/// A bare [PostgresDb] on the test database (no platform).
Future<PostgresDb> openTestDb() =>
    PostgresDb.open(Platform.environment[testDatabaseUrlVariable]!);
