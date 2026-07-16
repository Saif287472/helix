import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ServerUrlStore {
  const ServerUrlStore._();
  static const ServerUrlStore instance = ServerUrlStore._();
  static const _key = 'helix_remote_server_url';
  final _storage = const FlutterSecureStorage();

  Future<String?> load() => _storage.read(key: _key);
  Future<void> save(String url) => _storage.write(key: _key, value: url);
  Future<void> clear() => _storage.delete(key: _key);
}
