part of '../database.dart';

extension BackendFederationRepository on BackendDatabase {
  void upsertFederationServer({
    required String serverId,
    String? domain,
    required String publicKey,
    String? address,
    required String trustSource,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO federation_servers (
        server_id,
        domain,
        public_key,
        address,
        trust_source,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(server_id) DO UPDATE SET
        domain = COALESCE(excluded.domain, federation_servers.domain),
        public_key = excluded.public_key,
        address = COALESCE(excluded.address, federation_servers.address),
        trust_source = excluded.trust_source,
        updated_at = excluded.updated_at;
    ''');
    stmt.execute([serverId, domain, publicKey, address, trustSource, now]);
    stmt.close();
  }

  Map<String, dynamic>? getFederationServerById(String serverId) {
    final stmt = _db.prepare(
      'SELECT * FROM federation_servers WHERE server_id = ?;',
    );
    final res = stmt.select([serverId]);
    stmt.close();
    if (res.isEmpty) return null;
    return _federationServerFromRow(res.first);
  }

  Map<String, dynamic>? getFederationServerByDomain(String domain) {
    final stmt = _db.prepare(
      'SELECT * FROM federation_servers WHERE domain = ?;',
    );
    final res = stmt.select([domain]);
    stmt.close();
    if (res.isEmpty) return null;
    return _federationServerFromRow(res.first);
  }

  List<Map<String, dynamic>> getFederatedConversationMembers(
    String conversationId,
  ) {
    final stmt = _db.prepare('''
      SELECT * FROM federated_conversation_members
      WHERE conversation_id = ?
      ORDER BY account_id ASC;
    ''');
    final res = stmt.select([conversationId]);
    stmt.close();
    return res
        .map(
          (row) => {
            'conversation_id': row['conversation_id'],
            'account_id': row['account_id'],
            'domain': row['domain'],
            'role': row['role'],
          },
        )
        .toList();
  }

  bool isFederatedConversationMember(String conversationId, String accountId) {
    final stmt = _db.prepare('''
      SELECT 1 FROM federated_conversation_members
      WHERE conversation_id = ? AND account_id = ?;
    ''');
    final res = stmt.select([conversationId, accountId]);
    stmt.close();
    return res.isNotEmpty;
  }

  Map<String, dynamic> _federationServerFromRow(Row row) {
    return {
      'server_id': row['server_id'],
      'domain': row['domain'],
      'public_key': row['public_key'],
      'address': row['address'],
      'trust_source': row['trust_source'],
      'updated_at': row['updated_at'],
    };
  }
}
