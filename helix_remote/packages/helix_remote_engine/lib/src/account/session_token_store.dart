import 'dart:convert';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/settings_keys.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Keeps the device session (access and refresh token) in the encrypted
/// local database, so a host needs no second secret store. Pass it to
/// `HelixApi(sessions: DbSessionTokenStore(db))`.
///
/// The tokens are as protected as everything else in the database (the
/// SQLCipher key, held by the platform keystore). A host that prefers its
/// keystore for tokens can inject its own `SessionStore` instead; the
/// engine only ever talks to the `SessionStore` interface.
final class DbSessionTokenStore implements SessionStore {
  DbSessionTokenStore(this._db);

  final HelixDb _db;

  @override
  Future<Session?> read() async {
    final stored = await _db.settingsDao.get(EngineState.session);
    if (stored == null) return null;
    try {
      return Session.fromJson(JsonReader.decode(stored));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(Session session) =>
      _db.settingsDao.set(EngineState.session, jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _db.settingsDao.reset(EngineState.session);
}
