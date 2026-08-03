part of '../auth.dart';

mixin AuthProfileHandlers on AuthModuleBase {
  static const _displayNameChangeCooldown = Duration(days: 30);

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
      final now = _now();

      // Rate-limited to once every 30 days, but only counted from the
      // user's own explicit change - never from whatever name (including
      // the phone-number default from skipping) registration set, so a
      // first-ever change is always allowed regardless of when the account
      // was created.
      final existingProfile = db.getAccountProfile(accountId);
      final lastChangedAt =
          existingProfile?['display_name_changed_at'] as int?;
      if (lastChangedAt != null) {
        final nextAllowedAt = DateTime.fromMillisecondsSinceEpoch(
          lastChangedAt,
        ).add(_displayNameChangeCooldown);
        if (now.isBefore(nextAllowedAt)) {
          return Response(
            429,
            body: jsonEncode({
              'error':
                  'You can only change your display name once every '
                  '${_displayNameChangeCooldown.inDays} days. Try again on '
                  '${_formatDate(nextAllowedAt)}.',
              'next_allowed_at': nextAllowedAt.millisecondsSinceEpoch,
            }),
          );
        }
      }

      final profile = db.upsertAccountProfile(
        accountId: accountId,
        displayName: displayName,
        recordDisplayNameChange: true,
        now: now,
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
    final lastChangedAt = profile?['display_name_changed_at'] as int?;
    return Response.ok(
      jsonEncode({
        'account_id': accountId,
        'display_name': profile?['display_name'] ?? '',
        'next_display_name_change_allowed_at': lastChangedAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                lastChangedAt,
              ).add(_displayNameChangeCooldown).millisecondsSinceEpoch,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  String _formatDate(DateTime date) {
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${pad2(date.month)}-${pad2(date.day)}';
  }
}
