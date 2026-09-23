part of '../database.dart';

extension BackendContactsRepository on BackendDatabase {
  // Contacts
  void createContactRequest({
    required String requestId,
    required String requesterAccountId,
    required String targetAccountId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute('BEGIN TRANSACTION;');
    try {
      final requestStmt = _db.prepare('''
        INSERT INTO contact_requests (
          request_id,
          requester_account_id,
          target_account_id,
          status,
          created_at,
          updated_at
        )
        VALUES (?, ?, ?, 'PENDING', ?, ?);
      ''');
      requestStmt.execute([
        requestId,
        requesterAccountId,
        targetAccountId,
        now,
        now,
      ]);
      requestStmt.close();

      _upsertContactInTransaction(
        requesterAccountId,
        targetAccountId,
        null,
        'PENDING_SENT',
      );
      _upsertContactInTransaction(
        targetAccountId,
        requesterAccountId,
        null,
        'PENDING_RECEIVED',
      );
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Map<String, dynamic>? getContactRequest(String requestId) {
    final stmt = _db.prepare(
      'SELECT * FROM contact_requests WHERE request_id = ?;',
    );
    final res = stmt.select([requestId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'request_id': row['request_id'],
      'requester_account_id': row['requester_account_id'],
      'target_account_id': row['target_account_id'],
      'status': row['status'],
      'created_at': row['created_at'],
      'updated_at': row['updated_at'],
    };
  }

  List<Map<String, dynamic>> getContactRequests(String accountId) {
    final stmt = _db.prepare('''
      SELECT * FROM contact_requests
      WHERE requester_account_id = ? OR target_account_id = ?
      ORDER BY created_at DESC;
    ''');
    final res = stmt.select([accountId, accountId]);
    stmt.close();
    return res
        .map(
          (row) => {
            'request_id': row['request_id'],
            'requester_account_id': row['requester_account_id'],
            'target_account_id': row['target_account_id'],
            'status': row['status'],
            'created_at': row['created_at'],
            'updated_at': row['updated_at'],
          },
        )
        .toList();
  }

  int countContactRequestsSince(String accountId, int sinceTimestamp) {
    final stmt = _db.prepare('''
      SELECT COUNT(*) AS count FROM contact_requests
      WHERE requester_account_id = ? AND created_at >= ?;
    ''');
    final res = stmt.select([accountId, sinceTimestamp]);
    stmt.close();
    return res.first['count'] as int;
  }

  bool hasOpenContactRequest(
    String requesterAccountId,
    String targetAccountId,
  ) {
    final stmt = _db.prepare('''
      SELECT 1 FROM contact_requests
      WHERE (
          (requester_account_id = ? AND target_account_id = ?)
          OR (requester_account_id = ? AND target_account_id = ?)
        )
        AND status = 'PENDING';
    ''');
    final res = stmt.select([
      requesterAccountId,
      targetAccountId,
      targetAccountId,
      requesterAccountId,
    ]);
    stmt.close();
    return res.isNotEmpty;
  }

  void acceptContactRequest(String requestId) {
    final request = getContactRequest(requestId);
    if (request == null) {
      throw StateError('Contact request not found');
    }
    final requester = request['requester_account_id'] as String;
    final target = request['target_account_id'] as String;
    final now = DateTime.now().millisecondsSinceEpoch;

    _db.execute('BEGIN TRANSACTION;');
    try {
      final stmt = _db.prepare('''
        UPDATE contact_requests
        SET status = 'ACCEPTED', updated_at = ?
        WHERE request_id = ?;
      ''');
      stmt.execute([now, requestId]);
      stmt.close();
      _upsertContactInTransaction(requester, target, null, 'ACCEPTED');
      _upsertContactInTransaction(target, requester, null, 'ACCEPTED');
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void closeContactRequest(String requestId, String status) {
    final request = getContactRequest(requestId);
    if (request == null) {
      throw StateError('Contact request not found');
    }
    final requester = request['requester_account_id'] as String;
    final target = request['target_account_id'] as String;
    final now = DateTime.now().millisecondsSinceEpoch;

    _db.execute('BEGIN TRANSACTION;');
    try {
      final stmt = _db.prepare('''
        UPDATE contact_requests
        SET status = ?, updated_at = ?
        WHERE request_id = ?;
      ''');
      stmt.execute([status, now, requestId]);
      stmt.close();
      _deleteContactInTransaction(requester, target, onlyPending: true);
      _deleteContactInTransaction(target, requester, onlyPending: true);
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void addContact(String accountId, String peerAccountId, String? nickname) {
    _upsertContact(accountId, peerAccountId, nickname, 'ACCEPTED');
  }

  void blockContact(String accountId, String peerAccountId) {
    _upsertContact(accountId, peerAccountId, null, 'BLOCKED');
  }

  void unblockContact(String accountId, String peerAccountId) {
    removeContact(accountId, peerAccountId, onlyStatus: 'BLOCKED');
  }

  void removeContact(
    String accountId,
    String peerAccountId, {
    String? onlyStatus,
  }) {
    final sql = onlyStatus == null
        ? 'DELETE FROM contacts WHERE account_id = ? AND peer_account_id = ?;'
        : 'DELETE FROM contacts WHERE account_id = ? AND peer_account_id = ? AND status = ?;';
    final stmt = _db.prepare(sql);
    stmt.execute(
      onlyStatus == null
          ? [accountId, peerAccountId]
          : [accountId, peerAccountId, onlyStatus],
    );
    stmt.close();
  }

  List<Map<String, dynamic>> getContacts(String accountId) {
    final stmt = _db.prepare('SELECT * FROM contacts WHERE account_id = ?;');
    final result = stmt.select([accountId]);
    stmt.close();
    return result
        .map(
          (row) => {
            'peer_account_id': row['peer_account_id'],
            'nickname': row['nickname'],
            'status': row['status'],
          },
        )
        .toList();
  }

  bool isBlocked(String accountId, String peerAccountId) {
    final stmt = _db.prepare(
      "SELECT 1 FROM contacts WHERE account_id = ? AND peer_account_id = ? AND status = 'BLOCKED';",
    );
    final res = stmt.select([accountId, peerAccountId]);
    stmt.close();
    return res.isNotEmpty;
  }

  bool areContacts(String accountId, String peerAccountId) {
    final stmt = _db.prepare(
      "SELECT 1 FROM contacts WHERE account_id = ? AND peer_account_id = ? AND status = 'ACCEPTED';",
    );
    final res = stmt.select([accountId, peerAccountId]);
    stmt.close();
    return res.isNotEmpty;
  }

  void _upsertContact(
    String accountId,
    String peerAccountId,
    String? nickname,
    String status,
  ) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO contacts (account_id, peer_account_id, nickname, status)
      VALUES (?, ?, ?, ?);
    ''');
    stmt.execute([accountId, peerAccountId, nickname, status]);
    stmt.close();
  }

  void _upsertContactInTransaction(
    String accountId,
    String peerAccountId,
    String? nickname,
    String status,
  ) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO contacts (account_id, peer_account_id, nickname, status)
      VALUES (?, ?, ?, ?);
    ''');
    stmt.execute([accountId, peerAccountId, nickname, status]);
    stmt.close();
  }

  void _deleteContactInTransaction(
    String accountId,
    String peerAccountId, {
    bool onlyPending = false,
  }) {
    final stmt = _db.prepare(
      onlyPending
          ? "DELETE FROM contacts WHERE account_id = ? AND peer_account_id = ? AND status IN ('PENDING_SENT', 'PENDING_RECEIVED');"
          : 'DELETE FROM contacts WHERE account_id = ? AND peer_account_id = ?;',
    );
    stmt.execute([accountId, peerAccountId]);
    stmt.close();
  }

  Map<String, dynamic> getPrivacy(String accountId) {
    _ensurePrivacyRow(accountId);
    final stmt = _db.prepare(
      'SELECT * FROM account_privacy WHERE account_id = ?;',
    );
    final res = stmt.select([accountId]);
    stmt.close();
    final row = res.first;
    return {
      'account_id': row['account_id'],
      'search_discoverable': row['search_discoverable'] == 1,
      'presence_visibility': row['presence_visibility'],
      'last_seen_visibility': row['last_seen_visibility'],
      'phone_discoverable': row['phone_discoverable'] == 1,
      'profile_version': row['profile_version'],
    };
  }

  void setPrivacy({
    required String accountId,
    required bool searchDiscoverable,
    required String presenceVisibility,
    required String lastSeenVisibility,
    bool? phoneDiscoverable,
  }) {
    final current = getPrivacy(accountId);
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO account_privacy (
        account_id,
        search_discoverable,
        presence_visibility,
        last_seen_visibility,
        phone_discoverable,
        profile_version
      )
      VALUES (?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      accountId,
      searchDiscoverable ? 1 : 0,
      presenceVisibility,
      lastSeenVisibility,
      // INSERT OR REPLACE rewrites the whole row, so an omitted toggle must
      // explicitly carry forward its current value rather than silently
      // reset to the column default.
      (phoneDiscoverable ?? current['phone_discoverable'] as bool) ? 1 : 0,
      (current['profile_version'] as int) + 1,
    ]);
    stmt.close();
  }

  List<Map<String, dynamic>> searchAccounts(
    String requesterAccountId,
    String query, {
    int limit = 20,
  }) {
    final normalizedQuery = _normalizeSearchText(query);
    if (normalizedQuery.length < 2) return const [];

    final stmt = _db.prepare('''
      SELECT a.account_id, ap.display_name
      FROM accounts a
      JOIN account_profiles ap ON ap.account_id = a.account_id
      LEFT JOIN account_privacy p ON p.account_id = a.account_id
      WHERE a.account_id != ?
        AND (p.search_discoverable IS NULL OR p.search_discoverable = 1)
        AND TRIM(ap.display_name) != ''
        AND NOT EXISTS (
          SELECT 1 FROM contacts b 
          WHERE ((b.account_id = a.account_id AND b.peer_account_id = ?)
             OR (b.account_id = ? AND b.peer_account_id = a.account_id))
            AND b.status = 'BLOCKED'
        );
    ''');
    final res = stmt.select([
      requesterAccountId,
      requesterAccountId,
      requesterAccountId,
    ]);
    stmt.close();
    final matches = <Map<String, dynamic>>[];
    for (final row in res) {
      final accountId = row['account_id'] as String;
      final displayName = (row['display_name'] as String?) ?? '';
      if (displayName.isEmpty) continue;
      final similarity = _displayNameSimilarity(normalizedQuery, displayName);
      if (similarity < 0.45) continue;
      matches.add({
        'account_id': accountId,
        'display_name': displayName,
        'similarity': similarity,
      });
    }
    matches.sort((a, b) {
      final scoreCompare = (b['similarity'] as double).compareTo(
        a['similarity'] as double,
      );
      if (scoreCompare != 0) return scoreCompare;
      return (a['display_name'] as String).toLowerCase().compareTo(
        (b['display_name'] as String).toLowerCase(),
      );
    });
    return matches.take(limit).toList();
  }

  /// Remaining contact-discovery budget for [accountId], as
  /// (hashesRemaining, windowResetsAt). The window is a rolling 24h from the
  /// first charged hash; both fields are what the client is told so it can
  /// report honest progress rather than guessing.
  ({int hashesRemaining, int windowResetsAt}) getContactsMatchBudget({
    required String accountId,
    required int limit,
    required int now,
    required int windowMs,
  }) {
    final stmt = _db.prepare(
      'SELECT window_started_at, hashes_used FROM contacts_match_budget '
      'WHERE account_id = ?;',
    );
    final rows = stmt.select([accountId]);
    stmt.close();
    if (rows.isEmpty) {
      return (hashesRemaining: limit, windowResetsAt: now + windowMs);
    }
    final started = rows.first['window_started_at'] as int;
    final used = rows.first['hashes_used'] as int;
    if (now - started >= windowMs) {
      // Window elapsed - the row is stale, so the full budget is available.
      return (hashesRemaining: limit, windowResetsAt: now + windowMs);
    }
    final remaining = limit - used;
    return (
      hashesRemaining: remaining < 0 ? 0 : remaining,
      windowResetsAt: started + windowMs,
    );
  }

  /// Charges [hashes] against the account's budget, rolling the window over
  /// if the previous one has elapsed. Callers check the budget first; this
  /// only records the spend.
  void chargeContactsMatchBudget({
    required String accountId,
    required int hashes,
    required int now,
    required int windowMs,
  }) {
    final stmt = _db.prepare(
      'SELECT window_started_at FROM contacts_match_budget '
      'WHERE account_id = ?;',
    );
    final rows = stmt.select([accountId]);
    stmt.close();
    final rolling =
        rows.isEmpty ||
        now - (rows.first['window_started_at'] as int) >= windowMs;
    if (rolling) {
      final reset = _db.prepare(
        'INSERT INTO contacts_match_budget '
        '(account_id, window_started_at, hashes_used, last_request_at) '
        'VALUES (?, ?, ?, ?) '
        'ON CONFLICT(account_id) DO UPDATE SET '
        'window_started_at = excluded.window_started_at, '
        'hashes_used = excluded.hashes_used, '
        'last_request_at = excluded.last_request_at;',
      );
      reset.execute([accountId, now, hashes, now]);
      reset.close();
      return;
    }
    final bump = _db.prepare(
      'UPDATE contacts_match_budget '
      'SET hashes_used = hashes_used + ?, last_request_at = ? '
      'WHERE account_id = ?;',
    );
    bump.execute([hashes, now, accountId]);
    bump.close();
  }

  /// Drops budget rows whose window elapsed longer ago than [olderThanMs].
  /// The in-memory map this replaced grew one entry per account forever;
  /// this is the bounded equivalent, swept alongside the other operational
  /// retention jobs.
  int purgeExpiredContactsMatchBudgets(int now, int olderThanMs) {
    final stmt = _db.prepare(
      'DELETE FROM contacts_match_budget WHERE window_started_at < ?;',
    );
    stmt.execute([now - olderThanMs]);
    stmt.close();
    return _db.updatedRows;
  }

  /// The cached result for [accountId] when its phone book still hashes to
  /// [fingerprint], or null. Re-syncing an unchanged phone book asks the
  /// same questions and gets the same answers, so it should not cost budget.
  Map<String, dynamic>? getContactsMatchCache({
    required String accountId,
    required String fingerprint,
  }) {
    final stmt = _db.prepare(
      'SELECT matched_json FROM contacts_match_fingerprints '
      'WHERE account_id = ? AND fingerprint = ?;',
    );
    final rows = stmt.select([accountId, fingerprint]);
    stmt.close();
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['matched_json'] as String)
        as Map<String, dynamic>;
  }

  void setContactsMatchCache({
    required String accountId,
    required String fingerprint,
    required Map<String, dynamic> matched,
    required int now,
  }) {
    final stmt = _db.prepare(
      'INSERT INTO contacts_match_fingerprints '
      '(account_id, fingerprint, matched_json, created_at) '
      'VALUES (?, ?, ?, ?) '
      'ON CONFLICT(account_id) DO UPDATE SET '
      'fingerprint = excluded.fingerprint, '
      'matched_json = excluded.matched_json, '
      'created_at = excluded.created_at;',
    );
    stmt.execute([accountId, fingerprint, jsonEncode(matched), now]);
    stmt.close();
  }

  /// Batch phone-contact discovery: given a set of salted phone hashes (see
  /// `phone_hash.dart`), returns the account_id/display_name for every one
  /// that belongs to a registered, phone-discoverable account. Never
  /// returns anything for a hash with no match, so this can't be used to
  /// enumerate accounts beyond confirming ones the caller already had the
  /// real phone number for.
  List<Map<String, dynamic>> matchPhoneHashes(List<String> phoneHashes) {
    if (phoneHashes.isEmpty) return const [];
    final placeholders = List.filled(phoneHashes.length, '?').join(', ');
    final stmt = _db.prepare('''
      SELECT a.phone_hash, a.account_id, ap.display_name
      FROM accounts a
      JOIN account_profiles ap ON ap.account_id = a.account_id
      LEFT JOIN account_privacy p ON p.account_id = a.account_id
      WHERE a.phone_hash IN ($placeholders)
        AND (p.phone_discoverable IS NULL OR p.phone_discoverable = 1);
    ''');
    final res = stmt.select(phoneHashes);
    stmt.close();
    return res
        .map(
          (row) => {
            'phone_hash': row['phone_hash'] as String,
            'account_id': row['account_id'] as String,
            'display_name': (row['display_name'] as String?) ?? '',
          },
        )
        .toList();
  }

  double _displayNameSimilarity(String normalizedQuery, String displayName) {
    final normalizedName = _normalizeSearchText(displayName);
    if (normalizedName.isEmpty) return 0;
    if (normalizedName == normalizedQuery) return 1;

    var tokenScore = 0.0;
    for (final token in normalizedName.split(' ')) {
      if (token.isEmpty) continue;
      double currentTokenScore;
      if (token == normalizedQuery) {
        currentTokenScore = 0.98;
      } else if (token.startsWith(normalizedQuery)) {
        currentTokenScore = 0.94;
      } else if (token.contains(normalizedQuery)) {
        currentTokenScore = 0.82;
      } else {
        final tokenDistance = _levenshtein(token, normalizedQuery);
        currentTokenScore =
            1 -
            tokenDistance /
                (token.length > normalizedQuery.length
                    ? token.length
                    : normalizedQuery.length);
      }
      if (currentTokenScore > tokenScore) tokenScore = currentTokenScore;
    }

    final namePrefixScore = normalizedName.startsWith(normalizedQuery)
        ? 0.96 - (normalizedName.length - normalizedQuery.length) * 0.002
        : 0.0;
    final nameSubstringScore = normalizedName.contains(normalizedQuery)
        ? 0.86
        : 0.0;
    final nameDistance = _levenshtein(normalizedName, normalizedQuery);
    final editRatio =
        1 -
        nameDistance /
            (normalizedName.length > normalizedQuery.length
                ? normalizedName.length
                : normalizedQuery.length);
    final dice = _diceCoefficient(normalizedName, normalizedQuery);
    return [
      tokenScore,
      namePrefixScore,
      nameSubstringScore,
      editRatio,
      dice,
    ].reduce((a, b) => a > b ? a : b);
  }

  String _normalizeSearchText(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final current = <int>[i + 1];
      for (var j = 0; j < b.length; j++) {
        final insertion = current[j] + 1;
        final deletion = previous[j + 1] + 1;
        final substitution =
            previous[j] + (a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1);
        current.add(
          insertion < deletion
              ? (insertion < substitution ? insertion : substitution)
              : (deletion < substitution ? deletion : substitution),
        );
      }
      previous = current;
    }
    return previous.last;
  }

  double _diceCoefficient(String a, String b) {
    if (a.length < 2 || b.length < 2) return 0;
    final aPairs = <String, int>{};
    for (var i = 0; i < a.length - 1; i++) {
      final pair = a.substring(i, i + 2);
      aPairs[pair] = (aPairs[pair] ?? 0) + 1;
    }
    var intersection = 0;
    for (var i = 0; i < b.length - 1; i++) {
      final pair = b.substring(i, i + 2);
      final count = aPairs[pair] ?? 0;
      if (count == 0) continue;
      aPairs[pair] = count - 1;
      intersection++;
    }
    return (2 * intersection) / (a.length + b.length - 2);
  }

  Map<String, dynamic>? getPresenceForViewer(
    String viewerAccountId,
    String targetAccountId,
  ) {
    final privacy = getPrivacy(targetAccountId);
    final visibility = privacy['presence_visibility'] as String;
    if (visibility == 'NOBODY') return null;
    final isContact = areContacts(targetAccountId, viewerAccountId);
    if (visibility == 'CONTACTS' && !isContact) {
      return null;
    }

    final stmt = _db.prepare('''
      SELECT MAX(last_seen_at) AS last_seen_at
      FROM devices
      WHERE account_id = ? AND status = 'ACTIVE';
    ''');
    final res = stmt.select([targetAccountId]);
    stmt.close();
    final lastSeen = res.first['last_seen_at'];
    if (lastSeen == null) return null;

    return {
      'account_id': targetAccountId,
      'presence': 'RECENTLY_ACTIVE',
      'last_seen_at':
          _lastSeenVisible(privacy['last_seen_visibility'] as String, isContact)
          ? lastSeen
          : null,
    };
  }

  bool _lastSeenVisible(String visibility, bool isContact) {
    if (visibility == 'NOBODY') return false;
    if (visibility == 'CONTACTS') return isContact;
    return true;
  }

  String createReport({
    required String reportId,
    required String reporterAccountId,
    required String subjectAccountId,
    required String category,
    required String reasonCode,
    String? contextHash,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO reports (
        report_id,
        reporter_account_id,
        subject_account_id,
        category,
        reason_code,
        context_hash,
        status,
        created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, 'OPEN', ?);
    ''');
    stmt.execute([
      reportId,
      reporterAccountId,
      subjectAccountId,
      category,
      reasonCode,
      contextHash,
      now,
    ]);
    stmt.close();
    return reportId;
  }

  List<Map<String, dynamic>> getReports() {
    final stmt = _db.prepare('SELECT * FROM reports ORDER BY created_at DESC;');
    final res = stmt.select();
    stmt.close();
    return res
        .map(
          (row) => {
            'report_id': row['report_id'],
            'reporter_account_id': row['reporter_account_id'],
            'subject_account_id': row['subject_account_id'],
            'category': row['category'],
            'reason_code': row['reason_code'],
            'context_hash': row['context_hash'],
            'status': row['status'],
            'created_at': row['created_at'],
          },
        )
        .toList();
  }

  void addSafetyAction({
    required String actionId,
    required String reportId,
    required String actorAccountId,
    required String action,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute('BEGIN TRANSACTION;');
    try {
      final actionStmt = _db.prepare('''
        INSERT INTO safety_actions (action_id, report_id, actor_account_id, action, created_at)
        VALUES (?, ?, ?, ?, ?);
      ''');
      actionStmt.execute([actionId, reportId, actorAccountId, action, now]);
      actionStmt.close();

      final statusStmt = _db.prepare(
        "UPDATE reports SET status = 'ACTIONED' WHERE report_id = ?;",
      );
      statusStmt.execute([reportId]);
      statusStmt.close();
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void _ensurePrivacyRow(String accountId) {
    final stmt = _db.prepare('''
      INSERT OR IGNORE INTO account_privacy (account_id)
      VALUES (?);
    ''');
    stmt.execute([accountId]);
    stmt.close();
  }
}
