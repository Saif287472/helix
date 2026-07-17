import 'dart:convert';
import 'dart:io';
import 'package:helix_remote_crypto/helix_remote_crypto.dart';

class CliSecureStorage {
  CliSecureStorage(this.file);

  final File file;

  Map<String, String> _load() {
    if (!file.existsSync()) return {};
    try {
      final content = file.readAsStringSync();
      return Map<String, String>.from(jsonDecode(content) as Map);
    } catch (_) {
      return {};
    }
  }

  void _save(Map<String, String> data) {
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    file.writeAsStringSync(jsonEncode(data));
  }

  Future<void> writeKey(String key, String value) async {
    final data = _load();
    data[key] = value;
    _save(data);
  }

  Future<String?> readKey(String key) async {
    final data = _load();
    return data[key];
  }

  Future<void> writeKeyRecord(String key, RemoteSecureKeyRecord record) async {
    await writeKey(key, jsonEncode(record.toJson()));
  }

  Future<RemoteSecureKeyRecord?> readKeyRecord(String key) async {
    final raw = await readKey(key);
    if (raw == null) return null;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return RemoteSecureKeyRecord.fromJson(decoded.cast<String, Object?>());
  }

  Future<void> deleteKey(String key) async {
    final data = _load();
    data.remove(key);
    _save(data);
  }
}
