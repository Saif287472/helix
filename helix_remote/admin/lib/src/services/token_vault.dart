import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The admin session kept between runs: which server it belongs to, the
/// bearer token and when it expires (12 hours after sign-in).
final class StoredSession {
  const StoredSession({required this.serverUrl, required this.session});

  final String serverUrl;
  final AdminSession session;

  /// Never prints the token.
  @override
  String toString() =>
      'StoredSession($serverUrl, expires ${session.expiresAt})';
}

/// Where the admin token lives. It is a secret: platform secure storage
/// (Android Keystore, Windows credential store), never plain preferences,
/// never a log line.
abstract interface class TokenVault {
  Future<StoredSession?> read();

  Future<void> write(StoredSession stored);

  Future<void> clear();
}

final class SecureTokenVault implements TokenVault {
  SecureTokenVault([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'admin_session';

  final FlutterSecureStorage _storage;

  @override
  Future<StoredSession?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = JsonReader.decode(raw);
      return StoredSession(
        serverUrl: json.nonEmpty('server_url'),
        session: AdminSession.fromJson(json.object('session')),
      );
    } on FormatException {
      // Unreadable (an older console's value): treat as signed out.
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(StoredSession stored) => _storage.write(
    key: _key,
    value: jsonEncode({
      'server_url': stored.serverUrl,
      'session': stored.session.toJson(),
    }),
  );

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// For tests.
final class MemoryTokenVault implements TokenVault {
  MemoryTokenVault([this.stored]);

  StoredSession? stored;

  @override
  Future<StoredSession?> read() async => stored;

  @override
  Future<void> write(StoredSession stored) async => this.stored = stored;

  @override
  Future<void> clear() async => stored = null;
}
