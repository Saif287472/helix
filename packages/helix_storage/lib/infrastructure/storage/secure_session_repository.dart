import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:helix_domain/application/contracts/repositories.dart';

class SecureSessionRepository implements SessionRepository {
  static const _kSessionIdKey = 'last_session_id';
  final FlutterSecureStorage _storage;

  const SecureSessionRepository({this._storage = const FlutterSecureStorage()});

  @override
  Future<String?> loadSessionId() async {
    return _storage.read(key: _kSessionIdKey);
  }

  @override
  Future<void> saveSessionId(String sessionId) async {
    await _storage.write(key: _kSessionIdKey, value: sessionId);
  }

  @override
  Future<void> clearSessionId() async {
    await _storage.delete(key: _kSessionIdKey);
  }
}
