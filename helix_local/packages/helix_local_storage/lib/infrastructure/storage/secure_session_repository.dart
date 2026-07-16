import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:helix_local_domain/application/contracts/repositories.dart';

class SecureSessionRepository implements SessionRepository {
  static const _kSessionIdKey = 'last_session_id';
  final FlutterSecureStorage _storage;
  final String keyPrefix;

  const SecureSessionRepository({
    this._storage = const FlutterSecureStorage(),
    this.keyPrefix = '',
  });

  @override
  Future<String?> loadSessionId() async {
    var session = await _storage.read(key: '$keyPrefix$_kSessionIdKey');
    if (session == null && keyPrefix.startsWith('helix_local_')) {
      session = await _storage.read(key: _kSessionIdKey);
      if (session != null) {
        await _storage.write(key: '$keyPrefix$_kSessionIdKey', value: session);
        await _storage.delete(key: _kSessionIdKey);
      }
    }
    return session;
  }

  @override
  Future<void> saveSessionId(String sessionId) async {
    await _storage.write(key: '$keyPrefix$_kSessionIdKey', value: sessionId);
  }

  @override
  Future<void> clearSessionId() async {
    await _storage.delete(key: '$keyPrefix$_kSessionIdKey');
  }
}
