import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:helix_remote_backend/src/database.dart';

class ContactsModule {
  final BackendDatabase db;
  final Set<String> adminAccountIds;
  static const int contactRequestDailyLimit = 20;

  ContactsModule(this.db, {Set<String>? adminAccountIds})
    : adminAccountIds = adminAccountIds ?? const {'admin'};

  Router get router {
    final router = Router();
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
    router.get('/privacy', _getPrivacyHandler);
    router.post('/privacy', _setPrivacyHandler);
    router.post('/presence', _presenceHeartbeatHandler);
    router.get('/presence/<accountId>', _presenceHandler);
    router.post('/report', _reportHandler);
    router.post('/reports/action', _safetyActionHandler);
    return router;
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
        body: jsonEncode({'error': e.toString()}),
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
      final peerUsername = body['peer_username'] as String?;
      final nickname = body['nickname'] as String?;

      if (peerAccountId == null && peerUsername == null) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'Missing peer_account_id or peer_username',
          }),
        );
      }

      final accountId = auth['account_id'] as String;
      String targetId = peerAccountId ?? '';

      if (targetId.isEmpty && peerUsername != null) {
        final peerAcc = db.getAccountByUsername(peerUsername);
        if (peerAcc == null) {
          return Response.notFound(
            jsonEncode({'error': 'Peer account not found'}),
          );
        }
        targetId = peerAcc['account_id'] as String;
      }

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
        body: jsonEncode({'error': e.toString()}),
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
        body: jsonEncode({'error': e.toString()}),
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
        body: jsonEncode({'error': e.toString()}),
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
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  Future<Response> _searchHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }
    final query = request.url.queryParameters['q'] ?? '';
    if (query.length < 2) {
      return Response.ok(jsonEncode({'accounts': <Map<String, dynamic>>[]}));
    }

    final accountId = auth['account_id'] as String;
    return Response.ok(
      jsonEncode({'accounts': db.searchAccounts(accountId, query)}),
    );
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

      db.setPrivacy(
        accountId: auth['account_id'] as String,
        searchDiscoverable: searchDiscoverable,
        presenceVisibility: presenceVisibility,
        lastSeenVisibility: lastSeenVisibility,
      );

      return Response.ok(
        jsonEncode({'privacy': db.getPrivacy(auth['account_id'] as String)}),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
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
        body: jsonEncode({'error': e.toString()}),
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
        body: jsonEncode({'error': e.toString()}),
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
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  Future<String?> _resolvePeerAccountId(Map<String, dynamic> body) async {
    final peerAccountId = body['peer_account_id'] as String?;
    if (peerAccountId != null) {
      return db.getAccount(peerAccountId) == null ? null : peerAccountId;
    }
    final peerUsername = body['peer_username'] as String?;
    if (peerUsername == null) return null;
    final account = db.getAccountByUsername(peerUsername);
    return account?['account_id'] as String?;
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
