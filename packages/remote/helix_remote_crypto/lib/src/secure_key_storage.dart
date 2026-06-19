import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class RemoteSecureKeyStorage {
  const RemoteSecureKeyStorage({
    this.storage = const FlutterSecureStorage(),
    this.keyPrefix = 'helix_remote_v1_',
  });

  final FlutterSecureStorage storage;
  final String keyPrefix;

  /// Strict check protecting against path traversal or cross-product namespace leaks.
  void _assertValidKey(String key) {
    if (key.contains('/') || key.contains('\\') || key.contains('..')) {
      throw ArgumentError('Invalid key path structure: $key');
    }
  }

  Future<void> writeKey(String key, String value) async {
    _assertValidKey(key);
    await storage.write(key: '$keyPrefix$key', value: value);
  }

  Future<String?> readKey(String key) async {
    _assertValidKey(key);
    return storage.read(key: '$keyPrefix$key');
  }

  Future<void> deleteKey(String key) async {
    _assertValidKey(key);
    await storage.delete(key: '$keyPrefix$key');
  }

  /// Clears only Remote keys.
  Future<void> clearAllRemoteKeys() async {
    final allKeys = await storage.readAll();
    final toDelete = allKeys.keys
        .where((k) => k.startsWith(keyPrefix))
        .toList();
    for (final key in toDelete) {
      await storage.delete(key: key);
    }
  }
}
