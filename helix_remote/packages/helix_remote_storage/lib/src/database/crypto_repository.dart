part of '../database.dart';

mixin RemoteCryptoRepository on HelixRemoteDatabaseBase {
  // ---------------------------------------------------------------------------
  // Remote crypto session, prekey, and trust state
  // ---------------------------------------------------------------------------

  String getOrCreateLocalHistorySessionSeed(String conversationId) {
    final existing = getCryptoSession('local_history:$conversationId');
    if (existing != null) {
      return existing['root_key'] as String;
    }
    final random = math.Random.secure();
    final seed = base64Url.encode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    upsertCryptoSession(
      sessionId: 'local_history:$conversationId',
      conversationId: conversationId,
      role: 'local_history',
      protocolVersion: 1,
      rootKey: seed,
      sendingChainKey: seed,
      receivingChainKey: seed,
      createdAt: now,
      updatedAt: now,
    );
    return seed;
  }

  void upsertCryptoSession({
    required String sessionId,
    required String conversationId,
    required String role,
    required int protocolVersion,
    required String rootKey,
    required String sendingChainKey,
    required String receivingChainKey,
    required int createdAt,
    required int updatedAt,
    String? peerAccountId,
    String? peerDeviceId,
    int sendCount = 0,
    int receiveCount = 0,
    int previousChainLength = 0,
    String skippedKeysJson = '[]',
  }) {
    final stmt = _db.prepare('''
      INSERT INTO crypto_sessions (
        session_id,
        conversation_id,
        peer_account_id,
        peer_device_id,
        role,
        protocol_version,
        root_key,
        sending_chain_key,
        receiving_chain_key,
        send_count,
        receive_count,
        previous_chain_length,
        skipped_keys_json,
        created_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(session_id) DO UPDATE SET
        root_key = excluded.root_key,
        sending_chain_key = excluded.sending_chain_key,
        receiving_chain_key = excluded.receiving_chain_key,
        send_count = excluded.send_count,
        receive_count = excluded.receive_count,
        previous_chain_length = excluded.previous_chain_length,
        skipped_keys_json = excluded.skipped_keys_json,
        updated_at = excluded.updated_at;
    ''');
    stmt.execute([
      sessionId,
      conversationId,
      peerAccountId,
      peerDeviceId,
      role,
      protocolVersion,
      rootKey,
      sendingChainKey,
      receivingChainKey,
      sendCount,
      receiveCount,
      previousChainLength,
      skippedKeysJson,
      createdAt,
      updatedAt,
    ]);
    stmt.close();
  }

  Map<String, dynamic>? getCryptoSession(String sessionId) {
    final stmt = _db.prepare(
      'SELECT * FROM crypto_sessions WHERE session_id = ?;',
    );
    final res = stmt.select([sessionId]);
    stmt.close();
    if (res.isEmpty) return null;
    return Map<String, dynamic>.from(res.first);
  }

  void deleteCryptoSession(String sessionId) {
    final stmt = _db.prepare(
      'DELETE FROM crypto_sessions WHERE session_id = ?;',
    );
    stmt.execute([sessionId]);
    stmt.close();
  }

  List<Map<String, dynamic>> getCryptoSessionsForConversation(
    String conversationId,
  ) {
    final stmt = _db.prepare(
      'SELECT * FROM crypto_sessions WHERE conversation_id = ? ORDER BY session_id;',
    );
    final res = stmt.select([conversationId]);
    stmt.close();
    return res.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void saveLocalPrekey({
    required int keyId,
    required String role,
    required String deviceId,
    required String publicKey,
    required String privateKeyRef,
    required int createdAt,
    required String rotationState,
    String? signature,
    int? expiresAt,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO local_prekeys (
        key_id,
        role,
        device_id,
        public_key,
        private_key_ref,
        signature,
        created_at,
        expires_at,
        rotation_state
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      keyId,
      role,
      deviceId,
      publicKey,
      privateKeyRef,
      signature,
      createdAt,
      expiresAt,
      rotationState,
    ]);
    stmt.close();
  }

  List<Map<String, dynamic>> getLocalPrekeys({
    required String deviceId,
    String? role,
    String? rotationState,
  }) {
    final where = <String>['device_id = ?'];
    final args = <Object?>[deviceId];
    if (role != null) {
      where.add('role = ?');
      args.add(role);
    }
    if (rotationState != null) {
      where.add('rotation_state = ?');
      args.add(rotationState);
    }
    final stmt = _db.prepare(
      'SELECT * FROM local_prekeys WHERE ${where.join(' AND ')} ORDER BY key_id;',
    );
    final res = stmt.select(args);
    stmt.close();
    return res.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  int countActiveOneTimePrekeys(String deviceId) {
    final stmt = _db.prepare('''
      SELECT count(*) AS c FROM local_prekeys
      WHERE device_id = ? AND role = 'one_time_prekey' AND rotation_state = 'active';
    ''');
    final res = stmt.select([deviceId]);
    stmt.close();
    return res.first['c'] as int;
  }

  void markLocalPrekeyState({
    required int keyId,
    required String role,
    required String deviceId,
    required String rotationState,
  }) {
    final stmt = _db.prepare('''
      UPDATE local_prekeys
      SET rotation_state = ?
      WHERE key_id = ? AND role = ? AND device_id = ?;
    ''');
    stmt.execute([rotationState, keyId, role, deviceId]);
    stmt.close();
  }

  void upsertTrustDecision({
    required String accountId,
    required String deviceId,
    required String identityFingerprint,
    required String safetyNumber,
    required String status,
    required int timestamp,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO trusted_devices (
        account_id,
        device_id,
        identity_fingerprint,
        safety_number,
        status,
        first_seen_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(account_id, device_id) DO UPDATE SET
        identity_fingerprint = excluded.identity_fingerprint,
        safety_number = excluded.safety_number,
        status = excluded.status,
        updated_at = excluded.updated_at;
    ''');
    stmt.execute([
      accountId,
      deviceId,
      identityFingerprint,
      safetyNumber,
      status,
      timestamp,
      timestamp,
    ]);
    stmt.close();
  }

  Map<String, dynamic>? getTrustDecision({
    required String accountId,
    required String deviceId,
  }) {
    final stmt = _db.prepare('''
      SELECT * FROM trusted_devices WHERE account_id = ? AND device_id = ?;
    ''');
    final res = stmt.select([accountId, deviceId]);
    stmt.close();
    if (res.isEmpty) return null;
    return Map<String, dynamic>.from(res.first);
  }
}
