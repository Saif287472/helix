part of '../auth.dart';

mixin AuthInviteHandlers on AuthModuleBase {
  static const _globalAutoIssueHourlyLimitPerIp = 3;
  static const _globalInviteValidity = Duration(days: 7);

  final Map<String, List<int>> _globalAutoIssueAttempts = {};

  RateLimiter get _lookupRateLimiter => lookupRateLimiter;

  /// Validates an invite code without consuming it, so the client can fail
  /// fast on a bad/expired code before starting the phone+OTP signup flow.
  /// On failure, `reason` distinguishes *why* (not_found / already_used /
  /// cancelled / expired) so the client can show a specific explanation
  /// instead of a generic "invalid" message.
  /// Looks up an invite by code.
  ///
  /// Accepts the code in a POST body (preferred) or, for older clients, in a
  /// query parameter. An invite code is a bearer credential: in a query string
  /// it lands in the reverse proxy's access log, in browser and proxy history,
  /// and in any `Referer` a redirect would carry — none of which are places a
  /// credential should be readable at rest. The GET form is kept only so a
  /// client that predates this change keeps working, and should be removed
  /// once none remain in the field.
  Future<Response> _lookupInviteHandler(Request request) async {
    final clientIp = request.context['client_ip'] as String? ?? 'unknown';
    if (!_lookupRateLimiter.isAllowed('invite_lookup:$clientIp')) {
      throw AppError.tooManyRequests('Too many invite lookup attempts');
    }

    String? code;
    if (request.method == 'POST') {
      final raw = await request.readAsString();
      if (raw.isNotEmpty) {
        final body = jsonDecode(raw) as Map<String, dynamic>;
        code = body['invite_code'] as String?;
      }
    } else {
      code = request.url.queryParameters['invite_code'];
    }
    if (code == null || code.isEmpty) {
      throw AppError.badRequest('Missing invite_code');
    }

    final invite = db.getInviteByCodeHash(hashInviteCode(code));
    if (invite == null) {
      return Response.ok(
        jsonEncode({'valid': false, 'reason': 'not_found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    if (invite['status'] == 'REDEEMED') {
      return Response.ok(
        jsonEncode({'valid': false, 'reason': 'already_used'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    if (invite['status'] == 'CANCELLED') {
      return Response.ok(
        jsonEncode({'valid': false, 'reason': 'cancelled'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final now = _now().millisecondsSinceEpoch;
    if ((invite['expires_at'] as int) <= now) {
      return Response.ok(
        jsonEncode({'valid': false, 'reason': 'expired'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode({
        'valid': true,
        'server_address': invite['server_address'],
        'issuer_type': invite['issuer_type'],
        // Lets the join screen say which server the invite is for by the
        // name its admin chose, instead of only by hostname. Empty when
        // unnamed - the client falls back to the host.
        'server_name': db.getServerConfig(serverNameConfigKey) ?? '',
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
      throw AppError.tooManyRequests('Too many invite requests');
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
