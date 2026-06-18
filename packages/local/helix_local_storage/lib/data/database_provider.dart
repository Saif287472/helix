/// Provides the application-wide [HelixDatabase] instance.
///
/// Uses `path_provider` to locate the platform documents directory and opens
/// (or creates) `helix.db` there.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:helix_local_storage/data/database.dart';

/// Factory for the singleton database connection.
///
/// ```dart
/// final db = await DatabaseProvider.initialize();
/// ```
class DatabaseProvider {
  DatabaseProvider._();

  static HelixDatabase? _instance;
  static Future<HelixDatabase>? _initializing;

  /// Opens the database, creating tables if needed, and returns the shared
  /// [HelixDatabase] instance.
  ///
  /// Safe to call multiple times — concurrent calls share a single in-flight
  /// future so only one SQLite connection is ever opened.
  static Future<HelixDatabase> initialize({String databaseFilename = 'helix.db'}) =>
      _initializing ??= _initializeOnce(databaseFilename);

  static Future<HelixDatabase> _initializeOnce(String filename) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(docsDir.path, filename));
    final db = HelixDatabase(dbFile);
    db.initialize();
    _instance = db;
    return db;
  }

  /// Closes the database singleton connection and resets the instance.
  ///
  /// If [initialize] is still in flight, the result is closed as soon as
  /// it completes so no orphaned connection is left open.
  static void close() {
    final inflight = _initializing;
    _initializing = null;
    if (_instance != null) {
      _instance!.close();
      _instance = null;
    } else if (inflight != null) {
      inflight.then((db) => db.close()).catchError((_) {});
    }
  }
}
