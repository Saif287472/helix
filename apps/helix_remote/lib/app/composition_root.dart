// Single wiring point for all concrete Remote infrastructure.
//
// Rules enforced by construction:
//   - No LAN discovery, secret-code lookup, or Local trust store.
//   - No Local wipe scheduler (Remote has its own lifecycle).
//   - Product config is validated at construction time; missing required fields
//     throw StateError before the app reaches its first screen.

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:helix_remote_crypto/helix_remote_crypto.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';

/// Immutable product configuration for the Remote product.
/// All fields must be non-empty; validated by [RemoteCompositionRoot.production].
class RemoteProductConfig {
  const RemoteProductConfig({
    required this.displayName,
    required this.packageId,
    required this.secureStoragePrefix,
    required this.methodChannelNamespace,
    required this.logNamespace,
    required this.databaseDirectory,
  });

  final String displayName;
  final String packageId;
  final String secureStoragePrefix;
  final String methodChannelNamespace;
  final String logNamespace;

  /// Directory on disk where the Remote-only encrypted database will be stored.
  final String databaseDirectory;
}

/// Lifecycle state for the Remote composition root.
enum RemoteStartupState {
  idle,
  validatingConfig,
  loadingDbKey,
  initializingDatabase,
  ready,
  failed,
}

/// Composition root for Helix Remote.
///
/// Wires: RemoteSecureKeyStorage → HelixRemoteDatabase → RemoteSyncEngine.
///
/// Call [initialize] before accessing any service accessor. Accessing a
/// service before [initialize] completes or after a [failed] state throws
/// [StateError].
///
/// ISOLATION: This root creates and owns all Remote-specific infrastructure.
/// It never touches Local databases, key stores, or lifecycle objects.
class RemoteCompositionRoot {
  RemoteCompositionRoot._({required this.config, this._dbKeyLoader});

  /// Creates the production Remote root and validates required configuration.
  /// Throws [StateError] if any required config field is empty.
  factory RemoteCompositionRoot.production({
    required String databaseDirectory,
  }) {
    final config = RemoteProductConfig(
      displayName: 'Helix Remote',
      packageId: 'com.helix.remote',
      secureStoragePrefix: 'helix_remote_v1_',
      methodChannelNamespace: 'com.helix.remote',
      logNamespace: 'helix_remote',
      databaseDirectory: databaseDirectory,
    );
    final root = RemoteCompositionRoot._(config: config);
    root._validate();
    return root;
  }

  /// Test/override constructor — accepts an explicit config.
  factory RemoteCompositionRoot.withConfig(
    RemoteProductConfig config, {
    Future<String?> Function()? dbKeyLoader,
  }) {
    final root = RemoteCompositionRoot._(
      config: config,
      dbKeyLoader: dbKeyLoader,
    );
    root._validate();
    return root;
  }

  final RemoteProductConfig config;
  final Future<String?> Function()? _dbKeyLoader;

  RemoteStartupState _state = RemoteStartupState.idle;
  RemoteStartupState get startupState => _state;

  // Infrastructure instances — null until initialize() completes successfully.
  RemoteSecureKeyStorage? _keyStorage;
  HelixRemoteDatabase? _database;
  RemoteSyncEngine? _syncEngine;

  // ---------------------------------------------------------------------------
  // Service accessors — fail closed if called before ready.
  // ---------------------------------------------------------------------------

  RemoteSecureKeyStorage get keyStorage =>
      _requireReady(_keyStorage, 'keyStorage');
  HelixRemoteDatabase get database => _requireReady(_database, 'database');
  RemoteSyncEngine get syncEngine => _requireReady(_syncEngine, 'syncEngine');

  T _requireReady<T>(T? value, String name) {
    if (_state != RemoteStartupState.ready || value == null) {
      throw StateError(
        'RemoteCompositionRoot.$name accessed before initialize() completed '
        '(state: $_state). Call initialize() and await it first.',
      );
    }
    return value;
  }

  // ---------------------------------------------------------------------------
  // Startup state machine
  // ---------------------------------------------------------------------------

  /// Initialises all Remote infrastructure.
  ///
  /// Steps:
  ///   1. Validate config (synchronous, done at construction)
  ///   2. Load the existing database encryption key from secure storage
  ///   3. Open the Remote-only database file
  ///   4. Run schema migrations
  ///
  /// On any failure, [startupState] transitions to [RemoteStartupState.failed]
  /// and the exception is rethrown.  The root fails closed — no partially
  /// initialised services are accessible.
  Future<void> initialize() async {
    if (_state == RemoteStartupState.ready) return;
    if (_state == RemoteStartupState.failed) {
      throw StateError(
        'RemoteCompositionRoot is in the failed state. '
        'Dispose and recreate the root before retrying.',
      );
    }

    try {
      // Step 1 — config already validated at construction; begin boot.
      _state = RemoteStartupState.validatingConfig;
      _validate();

      // Step 2 — load DB key from secure storage.
      _state = RemoteStartupState.loadingDbKey;
      const keyStorageAdapter = RemoteSecureKeyStorage();
      _keyStorage = keyStorageAdapter;
      final dbKey = await _loadRequiredDbKey(keyStorageAdapter);

      // Step 3+4 — open and migrate the database.
      // NOTE (DEFECT-4 / BLOCKED): the password passed here activates a
      // `PRAGMA key` call which is a no-op on standard sqlite3. The database
      // is NOT encrypted at rest until a SQLCipher-capable library is used.
      // See: docs/architecture/PHASE_9_11_CLOSURE.md DEFECT-4.
      _state = RemoteStartupState.initializingDatabase;
      final dbFile = File(p.join(config.databaseDirectory, 'helix_remote.db'));
      final db = HelixRemoteDatabase(dbFile, password: dbKey);
      db.initialize();
      _database = db;

      _syncEngine = RemoteSyncEngine(db);

      _state = RemoteStartupState.ready;
    } catch (e) {
      _state = RemoteStartupState.failed;
      rethrow;
    }
  }

  /// Retrieves the database encryption key from secure storage.
  ///
  /// Startup fails closed when the key is absent. Do not silently create a
  /// plaintext fallback database or invent a replacement key here.
  Future<String> _loadRequiredDbKey(RemoteSecureKeyStorage storage) async {
    const keyName = 'db_key';
    final existing = _dbKeyLoader == null
        ? await storage.readKey(keyName)
        : await _dbKeyLoader();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    throw StateError('Remote database key is unavailable');
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  void _validate() {
    if (config.displayName.isEmpty) {
      throw StateError('RemoteProductConfig.displayName must not be empty');
    }
    if (config.packageId.isEmpty) {
      throw StateError('RemoteProductConfig.packageId must not be empty');
    }
    if (config.secureStoragePrefix.isEmpty) {
      throw StateError(
        'RemoteProductConfig.secureStoragePrefix must not be empty',
      );
    }
    if (!config.secureStoragePrefix.endsWith('_')) {
      throw StateError(
        'RemoteProductConfig.secureStoragePrefix must end with "_" '
        'to prevent key collisions between products',
      );
    }
    if (config.methodChannelNamespace.isEmpty) {
      throw StateError(
        'RemoteProductConfig.methodChannelNamespace must not be empty',
      );
    }
    if (config.logNamespace.isEmpty) {
      throw StateError('RemoteProductConfig.logNamespace must not be empty');
    }
    if (config.databaseDirectory.isEmpty) {
      throw StateError(
        'RemoteProductConfig.databaseDirectory must not be empty',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Disposal
  // ---------------------------------------------------------------------------

  void dispose() {
    if (_state == RemoteStartupState.ready) {
      _database?.close();
    }
    _database = null;
    _syncEngine = null;
    _keyStorage = null;
    _state = RemoteStartupState.idle;
  }
}
