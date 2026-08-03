import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/phone_hash.dart';

class ContactsModule {
  final BackendDatabase db;
  final Set<String> adminAccountIds;
  final void Function(String deviceId, Map<String, dynamic> payload)?
  notifyDevice;
  final Map<String, List<int>> _searchAttempts = {};
  static const int contactRequestDailyLimit = 20;
  static const int accountSearchMinuteLimit = 30;
  static const int contactsMatchDailyLimit = 5;
  static const int contactsMatchBatchLimit = 500;
  final Map<String, List<int>> _matchAttempts = {};

  ContactsModule(this.db, {Set<String>? adminAccountIds, this.notifyDevice})
    : adminAccountIds = adminAccountIds ?? const {'admin'};

  Router get router {
    final router = Router();
    router.get('/discovery-salt', _discoverySaltHandler);
    router.get('/', _listHandler);
    router.get('/requests', _requestsHandler);
    router.post('/requests', _createRequestHandler);
    router.post('/requests/accept', _acceptRequestHandler);
    router.post('/requests/reject', _rejectRequestHandler);
    router.post('/requests/cancel', _cancelRequestHandler);
    router.post('/add', _addHandler);
    router.post('/remove', _removeHandler);
    router.post('/block', _blockHandler);
    router.post('/unblock', _unblockHandler);
    router.get('/search', _searchHandler);
    router.post('/match', _matchPhoneHashesHandler);
    router.get('/privacy', _getPrivacyHandler);
    router.post('/privacy', _setPrivacyHandler);
    router.post('/presence', _presenceHeartbeatHandler);
    router.get('/presence/<accountId>', _presenceHandler);
    router.post('/report', _reportHandler);
    router.post('/reports/action', _safetyActionHandler);
    return router;
  }

  /// Returns the per-deployment, non-secret discovery salt used to hash
  /// phone numbers for privacy-preserving contact matching. Unauthenticated
  /// on purpose: it's needed before an account exists (signup) and by the
  /// contacts-sync flow. Self-heals on first call; never rotated afterward,
  /// since that would silently invalidate every existing phone-hash match.
  Future<Response> _discoverySaltHandler(Request request) async {
    var salt = db.getServerConfig(discoverySaltConfigKey);
    if (salt == null) {
      salt = generateDiscoverySalt();
      db.setServerConfig(discoverySaltConfigKey, salt);
    }
    return Response.ok(jsonEncode({'salt': salt}));
  }

  Future<Response> _listHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    final accountId = auth['account_id'] as String;
    final contacts = db.getContacts(accountId);

    return Response.ok(jsonEncode({'contacts': contacts}));
  }

  Future<Response> _requestsHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    final accountId = auth['account_id'] as String;
    return Response.ok(
      jsonEncode({'requests': db.getContactRequests(accountId)}),
    );
  }

  Future<Response> _createRequestHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final peerAccountId = await _resolvePeerAccountId(body);
      if (peerAccountId == null) {
        return Response.notFound(
          jsonEncode({'error': 'Peer account not found'}),
        );
      }

      final accountId = auth['account_id'] as String;
      if (peerAccountId == accountId) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Cannot contact yourself'}),
        );
      }
      if (db.isBlocked(peerAccountId, accountId) ||
          db.isBlocked(accountId, peerAccountId)) {
        return Response.forbidden(jsonEncode({'error': 'Contact unavailable'}));
      }
      if (db.hasOpenContactRequest(accountId, peerAccountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Contact request already pending'}),
        );
      }

      final since = DateTime.now()
          .subtract(const Duration(days: 1))
          .millisecondsSinceEpoch;
      if (db.countContactRequestsSince(accountId, since) >=
          contactRequestDailyLimit) {
        return Response(
          429,
          body: jsonEncode({'error': 'Request quota exceeded'}),
        );
      }

      final requestId =
          body['request_id'] as String? ??
          'cr_${DateTime.now().microsecondsSinceEpoch}';
      db.createContactRequest(
        requestId: requestId,
        requesterAccountId: accountId,
        targetAccountId: peerAccountId,
      );
      final updatedAt = DateTime.now().millisecondsSinceEpoch;
      final senderProfile = db.getAccountProfile(accountId);
      final senderDisplayName = senderProfile?['display_name'] as String? ?? '';
      _publishContactUpdate(
        accountId: accountId,
        peerAccountId: peerAccountId,
        requestId: requestId,
        direction: 'sent',
        status: 'PendingSent',
        updatedAt: updatedAt,
      );
      _publishContactUpdate(
        accountId: peerAccountId,
        peerAccountId: accountId,
        requestId: requestId,
        direction: 'received',
        status: 'PendingReceived',
        updatedAt: updatedAt,
        peerDisplayName: senderDisplayName,
      );
      db.logAudit(
        accountId,
        auth['device_id'] as String?,
        'CONTACT_REQUEST_CREATED',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(
        jsonEncode({'request_id': requestId, 'peer_account_id': peerAccountId}),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<Response> _acceptRequestHandler(Request request) {
    return _closeRequest(
      request,
      expectedActor: 'target',
      action: 'ACCEPT',
      close: db.acceptContactRequest,
    );
  }

  Future<Response> _rejectRequestHandler(Request request) {
    return _closeRequest(
      request,
      expectedActor: 'target',
      action: 'REJECT',
      close: (requestId) => db.closeContactRequest(requestId, 'REJECTED'),
    );
  }

  Future<Response> _cancelRequestHandler(Request request) {
    return _closeRequest(
      request,
      expectedActor: 'requester',
      action: 'CANCEL',
      close: (requestId) => db.closeContactRequest(requestId, 'CANCELLED'),
    );
  }

  Future<Response> _addHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final peerAccountId = body['peer_account_id'] as String?;
      final nickname = body['nickname'] as String?;

      if (peerAccountId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing peer_account_id'}),
        );
      }

      final accountId = auth['account_id'] as String;
      final targetId = peerAccountId;

      // Check if target exists
      final targetAcc = db.getAccount(targetId);
      if (targetAcc == null) {
        return Response.notFound(
          jsonEncode({'error': 'Peer account not found'}),
        );
      }

      db.addContact(accountId, targetId, nickname);
      db.logAudit(
        accountId,
        auth['device_id'] as String?,
        'CONTACT_ADDED',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(
        jsonEncode({
          'message': 'Contact added successfully',
          'peer_account_id': targetId,
          'nickname': nickname,
        }),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<Response> _removeHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final peerAccountId = body['peer_account_id'] as String?;
      if (peerAccountId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing peer_account_id'}),
        );
      }

      final accountId = auth['account_id'] as String;
      db.removeContact(accountId, peerAccountId);
      db.logAudit(
        accountId,
        auth['device_id'] as String?,
        'CONTACT_REMOVED',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(jsonEncode({'message': 'Contact removed'}));
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<Response> _blockHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final peerAccountId = body['peer_account_id'] as String?;

      if (peerAccountId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing peer_account_id'}),
        );
      }

      final accountId = auth['account_id'] as String;
      db.blockContact(accountId, peerAccountId);
      db.logAudit(
        accountId,
        auth['device_id'] as String?,
        'CONTACT_BLOCKED',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(
        jsonEncode({'message': 'Contact blocked successfully'}),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<Response> _unblockHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final peerAccountId = body['peer_account_id'] as String?;

      if (peerAccountId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing peer_account_id'}),
        );
      }

      final accountId = auth['account_id'] as String;
      db.unblockContact(accountId, peerAccountId);
      db.logAudit(
        accountId,
        auth['device_id'] as String?,
        'CONTACT_UNBLOCKED',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(
        jsonEncode({'message': 'Contact unblocked successfully'}),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<Response> _searchHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }
    final query = request.url.queryParameters['q'] ?? '';
    if (query.trim().length < 3) {
      return Response.ok(jsonEncode({'accounts': <Map<String, dynamic>>[]}));
    }

    final accountId = auth['account_id'] as String;
    if (!_allowAccountSearch(accountId)) {
      return Response(
        429,
        body: jsonEncode({'error': 'Search quota exceeded'}),
      );
    }
    return Response.ok(
      jsonEncode({'accounts': db.searchAccounts(accountId, query)}),
    );
  }

  bool _allowAccountSearch(String accountId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - const Duration(minutes: 1).inMilliseconds;
    final attempts = _searchAttempts.putIfAbsent(accountId, () => <int>[]);
    attempts.removeWhere((timestamp) => timestamp < cutoff);
    if (attempts.length >= accountSearchMinuteLimit) return false;
    attempts.add(now);
    return true;
  }

  /// Batch phone-contact discovery for the "sync phone contacts" flow.
  /// Authenticated and rate-limited (unlike /discovery-salt) since, even
  /// hashed, this is an oracle for "is phone number X a Helix user" to
  /// anyone who can call it - auth + a hard per-account daily cap + a
  /// batch-size cap are the required mitigations, not optional hardening.
  Future<Response> _matchPhoneHashesHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }
    final accountId = auth['account_id'] as String;

    if (!_allowContactsMatch(accountId)) {
      return Response(
        429,
        body: jsonEncode({'error': 'Contacts match quota exceeded'}),
      );
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final phoneHashes = (body['phone_hashes'] as List<dynamic>?)
          ?.cast<String>();
      if (phoneHashes == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing phone_hashes'}),
        );
      }
      if (phoneHashes.length > contactsMatchBatchLimit) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'phone_hashes exceeds the $contactsMatchBatchLimit limit',
          }),
        );
      }

      // Only the request's volume is logged here, never the hashes/numbers
      // themselves.
      db.logAudit(
        accountId,
        auth['device_id'] as String?,
        'CONTACTS_MATCH_REQUESTED',
        request.context['client_ip'] as String?,
        null,
      );

      final rows = db.matchPhoneHashes(phoneHashes);
      final matches = <String, dynamic>{
        for (final row in rows)
          row['phone_hash'] as String: {
            'account_id': row['account_id'],
            'display_name': row['display_name'],
          },
      };
      return Response.ok(jsonEncode({'matches': matches}));
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  bool _allowContactsMatch(String accountId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - const Duration(days: 1).inMilliseconds;
    final attempts = _matchAttempts.putIfAbsent(accountId, () => <int>[]);
    attempts.removeWhere((timestamp) => timestamp < cutoff);
    if (attempts.length >= contactsMatchDailyLimit) return false;
    attempts.add(now);
    return true;
  }

  Future<Response> _getPrivacyHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    return Response.ok(
      jsonEncode({'privacy': db.getPrivacy(auth['account_id'] as String)}),
    );
  }

  Future<Response> _setPrivacyHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final searchDiscoverable = body['search_discoverable'] as bool? ?? true;
      final presenceVisibility = _visibility(
        body['presence_visibility'] as String?,
      );
      final lastSeenVisibility = _visibility(
        body['last_seen_visibility'] as String?,
      );
      final phoneDiscoverable = body['phone_discoverable'] as bool?;

      db.setPrivacy(
        accountId: auth['account_id'] as String,
        searchDiscoverable: searchDiscoverable,
        presenceVisibility: presenceVisibility,
        lastSeenVisibility: lastSeenVisibility,
        phoneDiscoverable: phoneDiscoverable,
      );

      return Response.ok(
        jsonEncode({'privacy': db.getPrivacy(auth['account_id'] as String)}),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<Response> _presenceHeartbeatHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    db.updateDeviceLastSeen(
      auth['account_id'] as String,
      auth['device_id'] as String,
      DateTime.now().millisecondsSinceEpoch,
    );
    return Response.ok(jsonEncode({'message': 'Presence updated'}));
  }

  Future<Response> _presenceHandler(Request request, String accountId) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    final presence = db.getPresenceForViewer(
      auth['account_id'] as String,
      accountId,
    );
    return Response.ok(jsonEncode({'presence': presence}));
  }

  Future<Response> _reportHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final subjectAccountId = body['subject_account_id'] as String?;
      final category = body['category'] as String?;
      final reasonCode = body['reason_code'] as String?;
      final contextHash = body['context_hash'] as String?;
      if (subjectAccountId == null || category == null || reasonCode == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing report fields'}),
        );
      }
      if (body.containsKey('message_text') || body.containsKey('plaintext')) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Reports must not include plaintext'}),
        );
      }

      final reportId =
          body['report_id'] as String? ??
          'r_${DateTime.now().microsecondsSinceEpoch}';
      db.createReport(
        reportId: reportId,
        reporterAccountId: auth['account_id'] as String,
        subjectAccountId: subjectAccountId,
        category: category,
        reasonCode: reasonCode,
        contextHash: contextHash,
      );

      return Response.ok(jsonEncode({'report_id': reportId}));
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<Response> _safetyActionHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final reportId = body['report_id'] as String?;
      final action = body['action'] as String?;
      if (reportId == null || action == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing safety action fields'}),
        );
      }

      final actorAccountId = auth['account_id'] as String;
      if (!adminAccountIds.contains(actorAccountId)) {
        db.logAudit(
          actorAccountId,
          auth['device_id'] as String?,
          'ADMIN_ACCESS_DENIED',
          request.context['client_ip'] as String?,
          null,
        );
        return Response.forbidden(
          jsonEncode({'error': 'Admin privileges required'}),
        );
      }

      final actionId =
          body['action_id'] as String? ??
          'sa_${DateTime.now().microsecondsSinceEpoch}';
      db.addSafetyAction(
        actionId: actionId,
        reportId: reportId,
        actorAccountId: actorAccountId,
        action: action,
      );
      db.logAudit(
        actorAccountId,
        auth['device_id'] as String?,
        'ADMIN_SAFETY_ACTION',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(jsonEncode({'action_id': actionId}));
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<Response> _closeRequest(
    Request request, {
    required String expectedActor,
    required String action,
    required void Function(String requestId) close,
  }) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final requestId = body['request_id'] as String?;
      if (requestId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing request_id'}),
        );
      }

      final contactRequest = db.getContactRequest(requestId);
      if (contactRequest == null) {
        return Response.notFound(jsonEncode({'error': 'Request not found'}));
      }

      final accountId = auth['account_id'] as String;
      final allowedAccountId = expectedActor == 'target'
          ? contactRequest['target_account_id']
          : contactRequest['requester_account_id'];
      if (allowedAccountId != accountId) {
        return Response.forbidden(jsonEncode({'error': 'Forbidden'}));
      }

      close(requestId);
      final requester = contactRequest['requester_account_id'] as String;
      final target = contactRequest['target_account_id'] as String;
      final updatedAt = DateTime.now().millisecondsSinceEpoch;
      if (action == 'ACCEPT') {
        final requesterProfile = db.getAccountProfile(requester);
        final requesterDisplayName =
            requesterProfile?['display_name'] as String? ?? '';
        final targetProfile = db.getAccountProfile(target);
        final targetDisplayName =
            targetProfile?['display_name'] as String? ?? '';
        // Notify the original sender: their request was accepted by `target`
        _publishContactUpdate(
          accountId: requester,
          peerAccountId: target,
          requestId: requestId,
          direction: 'sent',
          status: 'Accepted',
          updatedAt: updatedAt,
          peerDisplayName: targetDisplayName,
        );
        // Notify the accepter: the contact is `requester`
        _publishContactUpdate(
          accountId: target,
          peerAccountId: requester,
          requestId: requestId,
          direction: 'received',
          status: 'Accepted',
          updatedAt: updatedAt,
          peerDisplayName: requesterDisplayName,
        );
      } else {
        final status = action == 'REJECT' ? 'Rejected' : 'Cancelled';
        _publishContactRemoved(
          accountId: requester,
          peerAccountId: target,
          requestId: requestId,
          status: status,
          updatedAt: updatedAt,
        );
        _publishContactRemoved(
          accountId: target,
          peerAccountId: requester,
          requestId: requestId,
          status: status,
          updatedAt: updatedAt,
        );
      }
      db.logAudit(
        accountId,
        auth['device_id'] as String?,
        'CONTACT_REQUEST_$action',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(jsonEncode({'message': 'Contact request $action'}));
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<String?> _resolvePeerAccountId(Map<String, dynamic> body) async {
    final peerAccountId = body['peer_account_id'] as String?;
    if (peerAccountId != null) {
      return db.getAccount(peerAccountId) == null ? null : peerAccountId;
    }
    return null;
  }

  void _publishContactUpdate({
    required String accountId,
    required String peerAccountId,
    required String requestId,
    required String direction,
    required String status,
    required int updatedAt,
    String? peerDisplayName,
  }) {
    _publishContactEvent(
      accountId: accountId,
      eventType: 'contact_updated',
      eventKey: '${requestId}_${direction}_$status',
      payload: {
        'peer_account_id': peerAccountId,
        'request_id': requestId,
        'direction': direction,
        'status': status,
        'updated_at': updatedAt,
        if (peerDisplayName != null && peerDisplayName.isNotEmpty)
          'peer_display_name': peerDisplayName,
      },
    );
  }

  void _publishContactRemoved({
    required String accountId,
    required String peerAccountId,
    required String requestId,
    required String status,
    required int updatedAt,
  }) {
    _publishContactEvent(
      accountId: accountId,
      eventType: 'contact_removed',
      eventKey: '${requestId}_$status',
      payload: {
        'peer_account_id': peerAccountId,
        'request_id': requestId,
        'status': status,
        'updated_at': updatedAt,
      },
    );
  }

  void _publishContactEvent({
    required String accountId,
    required String eventType,
    required String eventKey,
    required Map<String, dynamic> payload,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final device in db.getDevices(accountId)) {
      final deviceId = device['device_id'] as String;
      final eventId = 'evt_${eventType}_${eventKey}_$deviceId';
      final sequence = db.writeDeviceEvent(
        eventId: eventId,
        recipientDeviceId: deviceId,
        eventType: eventType,
        payload: jsonEncode(payload),
      );
      notifyDevice?.call(deviceId, {
        'event_id': eventId,
        'schema_version': 1,
        'timestamp': now,
        'type': eventType,
        'payload': payload,
        'server_sequence': sequence,
      });
    }
  }

  String _visibility(String? value) {
    const allowed = {'EVERYONE', 'CONTACTS', 'NOBODY'};
    final normalized = (value ?? 'CONTACTS').toUpperCase();
    if (!allowed.contains(normalized)) {
      throw FormatException('Invalid visibility value');
    }
    return normalized;
  }
}
