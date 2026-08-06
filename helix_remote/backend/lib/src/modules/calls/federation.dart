part of '../calls.dart';

/// Milestone 5.1: deciding whose account an id belongs to, and moving a
/// signal across a server boundary in either direction.
mixin CallsFederationHelpers on CallsModuleBase {
  @override
  bool _isExternal(String accountId) {
    final at = accountId.lastIndexOf('@');
    if (at <= 0 || at == accountId.length - 1) return false;
    final domain = accountId.substring(at + 1).toLowerCase();
    return localDomain == null || domain != localDomain!.toLowerCase();
  }

  @override
  String _qualify(String accountId) {
    if (accountId.contains('@') ||
        localDomain == null ||
        localDomain!.isEmpty) {
      return accountId;
    }
    return '$accountId@${localDomain!.toLowerCase()}';
  }

  String _localAccountId(String accountId) {
    final at = accountId.lastIndexOf('@');
    if (at <= 0 || at == accountId.length - 1) return accountId;
    final domain = accountId.substring(at + 1).toLowerCase();
    if (localDomain != null && domain == localDomain!.toLowerCase()) {
      return accountId.substring(0, at);
    }
    return accountId;
  }

  /// Entry point for `POST /api/v1/s2s/calls/signal`: relays a signal that
  /// a trusted remote server asserts one of its own local devices sent.
  /// Reuses the exact same dispatch as a local WS/REST signal
  /// (`_routeSignal`/`_routeOffer`/`_routeSessionSignal`) with
  /// `trustedRemote: true`, which skips the local-device-active checks that
  /// can't be verified for a device that lives on another server, and
  /// skips re-running the trust gate (the sending server already enforced
  /// it before proxying — same trust posture as `/s2s/messages/proxy`).
  Future<Map<String, dynamic>> receiveFederatedSignal({
    required String senderAccountId,
    required String senderDeviceId,
    required Map<String, dynamic> signal,
    String? requestId,
  }) {
    final message = Map<String, dynamic>.of(signal);
    final calleeAccountId = message['callee_account_id'];
    if (calleeAccountId is String) {
      message['callee_account_id'] = _localAccountId(calleeAccountId);
    }
    return _routeSignal(
      accountId: senderAccountId,
      deviceId: senderDeviceId,
      clientIp: 's2s',
      message: {'request_id': ?requestId, 'payload': message},
      trustedRemote: true,
    );
  }

  @override
  Future<Map<String, dynamic>?> _proxyCallSignal({
    required String domain,
    required String senderAccountId,
    required String senderDeviceId,
    required Map<String, dynamic> canonicalPayload,
    String? requestId,
  }) async {
    if (federationClient == null) return null;
    try {
      return await federationClient!.proxyCallSignal(
        domain: domain,
        senderAccountId: senderAccountId,
        senderDeviceId: senderDeviceId,
        signal: canonicalPayload,
        requestId: requestId,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  /// Shared proxy path for [_sendToDevice]/[_sendToCalleeDevices]: relays a
  /// post-offer session signal (answer/ice/decline/busy/cancel/end) to
  /// whichever domain `targetAccountId` lives on. `targetDeviceId`, when
  /// known, is meaningful to the remote server (it's one of *its own* local
  /// devices, since device ids always originate from whichever server the
  /// owning account is local to); when null, the remote server resolves
  /// its own fan-out the same way [_sendToCalleeDevices] would locally.
  Future<Map<String, dynamic>?> _proxySessionSignal({
    required _ParsedCallSignal signal,
    required Map<String, dynamic> session,
    required String senderAccountId,
    required String senderDeviceId,
    required String targetAccountId,
    required String? targetDeviceId,
    required String? requestId,
    required int now,
  }) async {
    if (federationClient == null) return null;
    final canonical = signal.toCanonicalPayload(
      callerAccountId: _qualify(senderAccountId),
      callerDeviceId: senderDeviceId,
      calleeAccountId: targetAccountId,
      targetDeviceId: targetDeviceId,
      createdAt: now,
      expiresAt: session['expires_at'] as int,
      // The call's agreed policy, not this frame's declared one. An ICE
      // candidate declares nothing, so taking it from the frame would send
      // relay-only across the hop and tighten a call mid-flight.
      effectivePolicy: CallMediaPolicy.fromWire(session['ip_privacy']),
    );
    return _proxyCallSignal(
      domain: FederationClient.domainOf(targetAccountId)!,
      senderAccountId: _qualify(senderAccountId),
      senderDeviceId: senderDeviceId,
      canonicalPayload: canonical,
      requestId: requestId,
    );
  }
}
