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
    final profile = db.getAccountProfile(accountId);
    return Response.ok(
      jsonEncode({
        'account_id': accountId,
        'display_name': profile?['display_name'] ?? '',
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
