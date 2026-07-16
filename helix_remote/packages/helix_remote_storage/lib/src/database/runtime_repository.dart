part of '../database.dart';

class RemoteAccountRuntimeProfile {
  const RemoteAccountRuntimeProfile({
    required this.accountId,
    required this.displayName,
    required this.databasePath,
    required this.secureStorageNamespace,
    required this.attachmentCachePath,
    required this.notificationChannelId,
    required this.serverBaseUrl,
    required this.active,
    required this.status,
    required this.lastUsedAt,
  });

  final String accountId;
  final String displayName;
  final String databasePath;
  final String secureStorageNamespace;
  final String attachmentCachePath;
  final String notificationChannelId;
  final String serverBaseUrl;
  final bool active;
  final String status;
  final int lastUsedAt;
}

class RemoteProxyProfile {
  const RemoteProxyProfile({
    required this.profileId,
    required this.accountId,
    required this.mode,
    required this.host,
    required this.port,
    this.username = '',
    this.encryptedPasswordRef = '',
    this.allowInvalidCertificates = false,
    required this.updatedAt,
  });

  final String profileId;
  final String accountId;
  final String mode;
  final String host;
  final int port;
  final String username;
  final String encryptedPasswordRef;
  final bool allowInvalidCertificates;
  final int updatedAt;
}

class RemotePlatformCapabilityProfile {
  const RemotePlatformCapabilityProfile({
    required this.platformId,
    required this.capabilitiesJson,
    required this.updatedAt,
  });

  final String platformId;
  final String capabilitiesJson;
  final int updatedAt;
}

mixin RemoteRuntimeRepository on HelixRemoteDatabaseBase {
  void upsertAccountRuntimeProfile(RemoteAccountRuntimeProfile profile) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO account_runtime_profiles (
        account_id,
        display_name,
        database_path,
        secure_storage_namespace,
        attachment_cache_path,
        notification_channel_id,
        server_base_url,
        active,
        status,
        last_used_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      profile.accountId,
      profile.displayName,
      profile.databasePath,
      profile.secureStorageNamespace,
      profile.attachmentCachePath,
      profile.notificationChannelId,
      profile.serverBaseUrl,
      profile.active ? 1 : 0,
      profile.status,
      profile.lastUsedAt,
    ]);
    stmt.close();
    if (profile.active) {
      activateAccountRuntime(profile.accountId, profile.lastUsedAt);
    }
  }

  RemoteAccountRuntimeProfile? accountRuntimeProfile(String accountId) {
    final rows = _db.select(
      'SELECT * FROM account_runtime_profiles WHERE account_id = ?;',
      [accountId],
    );
    if (rows.isEmpty) return null;
    return _runtimeProfileFromRow(rows.first);
  }

  List<RemoteAccountRuntimeProfile> accountRuntimeProfiles({
    bool includeDeleted = false,
  }) {
    final rows = _db.select(
      '''
      SELECT * FROM account_runtime_profiles
      WHERE ? OR status != 'deleted'
      ORDER BY active DESC, last_used_at DESC, display_name ASC;
      ''',
      [includeDeleted ? 1 : 0],
    );
    return rows.map(_runtimeProfileFromRow).toList();
  }

  RemoteAccountRuntimeProfile? activeAccountRuntimeProfile() {
    final rows = _db.select('''
      SELECT * FROM account_runtime_profiles
      WHERE active = 1 AND status != 'deleted'
      ORDER BY last_used_at DESC
      LIMIT 1;
      ''');
    if (rows.isEmpty) return null;
    return _runtimeProfileFromRow(rows.first);
  }

  void activateAccountRuntime(String accountId, int nowMs) {
    _db.execute('SAVEPOINT activate_account_runtime;');
    try {
      _db.execute('UPDATE account_runtime_profiles SET active = 0;');
      final stmt = _db.prepare('''
        UPDATE account_runtime_profiles
        SET active = 1, last_used_at = ?, status = 'active'
        WHERE account_id = ? AND status != 'deleted';
      ''');
      stmt.execute([nowMs, accountId]);
      stmt.close();
      _db.execute('RELEASE SAVEPOINT activate_account_runtime;');
    } catch (_) {
      _db.execute('ROLLBACK TO SAVEPOINT activate_account_runtime;');
      _db.execute('RELEASE SAVEPOINT activate_account_runtime;');
      rethrow;
    }
  }

  void markAccountRuntimeInactive(String accountId, int nowMs) {
    final stmt = _db.prepare('''
      UPDATE account_runtime_profiles
      SET active = 0, status = 'inactive', last_used_at = ?
      WHERE account_id = ? AND status != 'deleted';
    ''');
    stmt.execute([nowMs, accountId]);
    stmt.close();
  }

  void markAccountRuntimeDeleted(String accountId, int nowMs) {
    final stmt = _db.prepare('''
      UPDATE account_runtime_profiles
      SET active = 0, status = 'deleted', last_used_at = ?
      WHERE account_id = ?;
    ''');
    stmt.execute([nowMs, accountId]);
    stmt.close();
  }

  int purgeDeletedAccountRuntimes() {
    final deletedAccounts = _db
        .select(
          "SELECT account_id FROM account_runtime_profiles WHERE status = 'deleted';",
        )
        .map((row) => row['account_id'] as String)
        .toList();
    if (deletedAccounts.isEmpty) return 0;
    final placeholders = List.filled(deletedAccounts.length, '?').join(', ');
    final deletedProxyCount =
        _db
                .select(
                  'SELECT count(*) AS count FROM proxy_profiles '
                  'WHERE account_id IN ($placeholders);',
                  deletedAccounts,
                )
                .first['count']
            as int;
    _db.execute(
      "DELETE FROM proxy_profiles WHERE account_id IN ("
      "SELECT account_id FROM account_runtime_profiles "
      "WHERE status = 'deleted'"
      ');',
    );
    _db.execute(
      "DELETE FROM account_runtime_profiles WHERE status = 'deleted';",
    );
    return deletedAccounts.length + deletedProxyCount;
  }

  void upsertProxyProfile(RemoteProxyProfile profile) {
    if (profile.allowInvalidCertificates) {
      throw ArgumentError(
        'Proxy certificate validation cannot be disabled for Remote traffic',
      );
    }
    if (profile.mode != 'direct' && profile.host.trim().isEmpty) {
      throw ArgumentError('Proxy host is required when proxy mode is enabled');
    }
    if (profile.port < 0 || profile.port > 65535) {
      throw ArgumentError('Proxy port must be between 0 and 65535');
    }
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO proxy_profiles (
        profile_id,
        account_id,
        mode,
        host,
        port,
        username,
        encrypted_password_ref,
        allow_invalid_certificates,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      profile.profileId,
      profile.accountId,
      profile.mode,
      profile.host,
      profile.port,
      profile.username,
      profile.encryptedPasswordRef,
      profile.allowInvalidCertificates ? 1 : 0,
      profile.updatedAt,
    ]);
    stmt.close();
  }

  RemoteProxyProfile? proxyProfile(String profileId) {
    final rows = _db.select(
      'SELECT * FROM proxy_profiles WHERE profile_id = ?;',
      [profileId],
    );
    if (rows.isEmpty) return null;
    return _proxyProfileFromRow(rows.first);
  }

  List<RemoteProxyProfile> proxyProfilesForAccount(String accountId) {
    final rows = _db.select(
      '''
      SELECT * FROM proxy_profiles
      WHERE account_id = ?
      ORDER BY updated_at DESC, profile_id ASC;
      ''',
      [accountId],
    );
    return rows.map(_proxyProfileFromRow).toList();
  }

  Map<String, dynamic> proxyDiagnostics(String profileId) {
    final proxy = proxyProfile(profileId);
    if (proxy == null) return const {};
    return {
      'profile_id': proxy.profileId,
      'account_id': proxy.accountId,
      'mode': proxy.mode,
      'host': proxy.host,
      'port': proxy.port,
      'username_present': proxy.username.isNotEmpty,
      'password_ref_present': proxy.encryptedPasswordRef.isNotEmpty,
      'certificate_validation': proxy.allowInvalidCertificates
          ? 'invalid'
          : 'required',
      'turn_media_proxy': 'separate',
    };
  }

  void upsertPlatformCapabilityProfile(
    RemotePlatformCapabilityProfile profile,
  ) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO platform_capability_profiles (
        platform_id,
        capabilities_json,
        updated_at
      )
      VALUES (?, ?, ?);
    ''');
    stmt.execute([
      profile.platformId,
      profile.capabilitiesJson,
      profile.updatedAt,
    ]);
    stmt.close();
  }

  RemotePlatformCapabilityProfile? platformCapabilityProfile(
    String platformId,
  ) {
    final rows = _db.select(
      'SELECT * FROM platform_capability_profiles WHERE platform_id = ?;',
      [platformId],
    );
    if (rows.isEmpty) return null;
    return RemotePlatformCapabilityProfile(
      platformId: rows.first['platform_id'] as String,
      capabilitiesJson: rows.first['capabilities_json'] as String,
      updatedAt: rows.first['updated_at'] as int,
    );
  }

  RemoteAccountRuntimeProfile _runtimeProfileFromRow(Map<String, dynamic> row) {
    return RemoteAccountRuntimeProfile(
      accountId: row['account_id'] as String,
      displayName: row['display_name'] as String,
      databasePath: row['database_path'] as String,
      secureStorageNamespace: row['secure_storage_namespace'] as String,
      attachmentCachePath: row['attachment_cache_path'] as String,
      notificationChannelId: row['notification_channel_id'] as String,
      serverBaseUrl: row['server_base_url'] as String,
      active: (row['active'] as int? ?? 0) != 0,
      status: row['status'] as String,
      lastUsedAt: row['last_used_at'] as int,
    );
  }

  RemoteProxyProfile _proxyProfileFromRow(Map<String, dynamic> row) {
    return RemoteProxyProfile(
      profileId: row['profile_id'] as String,
      accountId: row['account_id'] as String,
      mode: row['mode'] as String,
      host: row['host'] as String,
      port: row['port'] as int,
      username: row['username'] as String? ?? '',
      encryptedPasswordRef: row['encrypted_password_ref'] as String? ?? '',
      allowInvalidCertificates:
          (row['allow_invalid_certificates'] as int? ?? 0) != 0,
      updatedAt: row['updated_at'] as int,
    );
  }
}
