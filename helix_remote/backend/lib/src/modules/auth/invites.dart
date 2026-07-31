part of '../auth.dart';

mixin AuthInviteHandlers on AuthModuleBase {
  static const _globalAutoIssueHourlyLimitPerIp = 3;
  static const _globalInviteValidity = Duration(days: 7);

  final Map<String, List<int>> _globalAutoIssueAttempts = {};

  /// Validates an invite code without consuming it, so the client can fail
  /// fast on a bad/expired code before starting the phone+OTP signup flow.
  Future<Response> _lookupInviteHandler(Request request) async {
    final code = request.url.queryParameters['invite_code'];
    if (code == null || code.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing invite_code'}),
      );
    }

    final invite = db.getInviteByCodeHash(hashInviteCode(code));
    final now = _now().millisecondsSinceEpoch;
    final valid =
        invite != null &&
        invite['status'] == 'PENDING' &&
        (invite['expires_at'] as int) > now;

    if (!valid) {
      return Response.ok(
        jsonEncode({'valid': false}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode({
        'valid': true,
        'server_address': invite['server_address'],
        'issuer_type': invite['issuer_type'],
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Self-issues an invite for Helix Global's free signup path. Gated
  /// server-side by the `global_instance_mode` server_configuration flag -
  /// this must never be honored on a self-hosted deployment regardless of
  /// what the calling client claims, or self-hosted servers could be
  /// tricked into bypassing their own invite-only registration.
  Future<Response> _autoIssueInviteHandler(Request request) async {
    if (!globalInstanceMode) {
      return Response(
        403,
        body: jsonEncode({
          'error': 'Global auto-issue is not enabled on this server',
        }),
      );
    }

    final clientIp = request.context['client_ip'] as String? ?? 'unknown';
    if (!_allowGlobalAutoIssue(clientIp)) {
      return Response(
        429,
        body: jsonEncode({'error': 'Too many invite requests'}),
      );
    }

    final now = _now().millisecondsSinceEpoch;
    final inviteId = generateInviteId();
    final code = generateInviteCode();
    final expiresAt = now + _globalInviteValidity.inMilliseconds;

    db.createInviteCredential(
      inviteId: inviteId,
      inviteCodeHash: hashInviteCode(code),
      serverAddress: publicBaseUrl,
      issuerType: 'SYSTEM_GLOBAL',
      createdAt: now,
      expiresAt: expiresAt,
    );

    return Response.ok(
      jsonEncode({'invite_code': code, 'expires_at': expiresAt}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  bool _allowGlobalAutoIssue(String clientIp) {
    final now = _now().millisecondsSinceEpoch;
    final cutoff = now - const Duration(hours: 1).inMilliseconds;
    final attempts = _globalAutoIssueAttempts.putIfAbsent(
      clientIp,
      () => <int>[],
    );
    attempts.removeWhere((timestamp) => timestamp < cutoff);
    if (attempts.length >= _globalAutoIssueHourlyLimitPerIp) return false;
    attempts.add(now);
    return true;
  }
}
