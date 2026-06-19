import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:helix_remote_backend/src/database.dart';

class ContactsModule {
  final BackendDatabase db;

  ContactsModule(this.db);

  Router get router {
    final router = Router();
    router.get('/', _listHandler);
    router.post('/add', _addHandler);
    router.post('/block', _blockHandler);
    router.post('/unblock', _unblockHandler);
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
}
