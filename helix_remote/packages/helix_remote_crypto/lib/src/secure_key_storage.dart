import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class RemoteSecureKeyRecord {
  const RemoteSecureKeyRecord({
    required this.role,
    required this.version,
    required this.deviceId,
    required this.value,
    required this.createdAt,
    this.rotationState = 'active',
    this.metadata = const {},
  });

  final String role;
  final int version;
  final String deviceId;
  final String value;
  final DateTime createdAt;
  final String rotationState;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => {
    'role': role,
    'version': version,
    'device_id': deviceId,
    'value': value,
    'created_at': createdAt.millisecondsSinceEpoch,
    'rotation_state': rotationState,
    'metadata': metadata,
  };

  static RemoteSecureKeyRecord fromJson(Map<String, Object?> json) {
    return RemoteSecureKeyRecord(
      role: json['role'] as String,
      version: json['version'] as int,
      deviceId: json['device_id'] as String,
      value: json['value'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
      rotationState: json['rotation_state'] as String? ?? 'active',
      metadata: (json['metadata'] as Map?)?.cast<String, Object?>() ?? const {},
    );
  }
}

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

  Future<void> writeKeyRecord(String key, RemoteSecureKeyRecord record) async {
    _assertValidKey(key);
    _assertValidKey(record.role);
    _assertValidKey(record.deviceId);
    await storage.write(
      key: '$keyPrefix$key',
      value: jsonEncode(record.toJson()),
    );
  }

  Future<String?> readKey(String key) async {
    _assertValidKey(key);
    return storage.read(key: '$keyPrefix$key');
  }

  Future<RemoteSecureKeyRecord?> readKeyRecord(String key) async {
    final raw = await readKey(key);
    if (raw == null) return null;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return RemoteSecureKeyRecord.fromJson(decoded.cast<String, Object?>());
  }

  Future<void> migrateLegacyKey({
    required String legacyKey,
    required String role,
    required String deviceId,
    required DateTime createdAt,
    int version = 1,
  }) async {
    final value = await readKey(legacyKey);
    if (value == null) return;
    if (value.trimLeft().startsWith('{')) return;
    await writeKeyRecord(
      legacyKey,
      RemoteSecureKeyRecord(
        role: role,
        version: version,
        deviceId: deviceId,
        value: value,
        createdAt: createdAt,
        rotationState: 'legacy_migrated',
      ),
    );
  }

  Future<List<Map<String, Object?>>> keyInventory() async {
    final allKeys = await storage.readAll();
    final inventory = <Map<String, Object?>>[];
    for (final entry in allKeys.entries) {
      if (!entry.key.startsWith(keyPrefix)) continue;
      final logicalKey = entry.key.substring(keyPrefix.length);
      try {
        final decoded = jsonDecode(entry.value) as Map<String, dynamic>;
        final record = RemoteSecureKeyRecord.fromJson(
          decoded.cast<String, Object?>(),
        );
        inventory.add({
          'key': logicalKey,
          'role': record.role,
          'version': record.version,
          'device_id': record.deviceId,
          'created_at': record.createdAt.millisecondsSinceEpoch,
          'rotation_state': record.rotationState,
        });
      } catch (_) {
        inventory.add({
          'key': logicalKey,
          'role': 'legacy_unversioned',
          'version': 0,
          'device_id': '',
          'created_at': 0,
          'rotation_state': 'needs_migration',
        });
      }
    }
    inventory.sort((a, b) => '${a['key']}'.compareTo('${b['key']}'));
    return inventory;
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
