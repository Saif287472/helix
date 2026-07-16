part of '../auth.dart';

mixin AuthProfileHandlers on AuthModuleBase {
  Future<Response> _updateProfileHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final displayName = (body['display_name'] as String?)?.trim();
      if (displayName == null ||
          displayName.isEmpty ||
          displayName.length > 80) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid display_name'}),
        );
      }

      final accountId = auth['account_id'] as String;
      final profile = db.upsertAccountProfile(
        accountId: accountId,
        displayName: displayName,
      );
      db.logAudit(
        accountId,
        auth['device_id'] as String?,
        'PROFILE_UPDATED',
        request.context['client_ip'] as String?,
        null,
      );

      _notifySiblingDevices(
        accountId,
        exceptDeviceId: auth['device_id'] as String,
        payload: {
          'type': 'profile_updated',
          'account_id': accountId,
          'display_name': displayName,
          'profile_version': profile['profile_version'],
          'updated_at': profile['updated_at'],
        },
      );

      return Response.ok(jsonEncode({'profile': profile}));
    } catch (_) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<Response> _getProfileHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }
    final accountId = auth['account_id'] as String;
    final account = db.getAccount(accountId);
    final profile = db.getAccountProfile(accountId);
    return Response.ok(
      jsonEncode({
        'account_id': accountId,
        'username': account?['username'] ?? '',
        'display_name': profile?['display_name'] ?? '',
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _changeUsernameHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final username = body['username'] as String?;
      if (username == null || !_isValidUsername(username)) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid username'}),
        );
      }

      final existing = db.getAccountByUsername(username);
      final accountId = auth['account_id'] as String;
      if (existing != null && existing['account_id'] != accountId) {
        return Response.forbidden(
          jsonEncode({'error': 'Username is not available'}),
        );
      }

      db.updateUsername(accountId, username);
      db.logAudit(
        accountId,
        auth['device_id'] as String?,
        'USERNAME_CHANGED',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(
        jsonEncode({'message': 'Username changed', 'username': username}),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }
}
