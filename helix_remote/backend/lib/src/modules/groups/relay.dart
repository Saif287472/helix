part of '../groups.dart';

/// Fan-out and last-admin bookkeeping shared by every handler mixin.
mixin GroupsRelayHelpers on GroupsModuleBase {
  void _relayToGroupMembers(
    String groupId,
    Map<String, dynamic> payload, {
    String? excludeDeviceId,
    String? excludeAccountId,
  }) {
    final eventType = payload['type'] as String?;
    if (eventType == null) return;
    final bodyPayload = Map<String, dynamic>.from(payload)..remove('type');

    final now = DateTime.now().millisecondsSinceEpoch;
    final members = db.getConversationMembers(groupId);
    for (final memberId in members) {
      if (memberId == excludeAccountId) continue;
      final devices = db.getDevices(memberId);
      for (final dev in devices) {
        final devId = dev['device_id'] as String;
        if (devId == excludeDeviceId) continue;
        final eventId = '${eventType}_${groupId}_${now}_$devId';
        final envelope = BackendDatabase.buildEnvelope(
          eventId: eventId,
          type: eventType,
          payload: bodyPayload,
          timestamp: now,
        );
        wsRelay.sendToDevice(devId, envelope);
      }
    }
  }

  void _relayToGroupAdmins(String groupId, Map<String, dynamic> payload) {
    final eventType = payload['type'] as String?;
    if (eventType == null) return;
    final bodyPayload = Map<String, dynamic>.from(payload)..remove('type');
    final now = DateTime.now().millisecondsSinceEpoch;
    final members = db.getGroupMembersPaginated(groupId, limit: 500, offset: 0);
    for (final member in members) {
      if (member['role'] != 'ADMIN') continue;
      final memberId = member['account_id'] as String;
      final devices = db.getDevices(memberId);
      for (final dev in devices) {
        final devId = dev['device_id'] as String;
        final envelope = BackendDatabase.buildEnvelope(
          eventId: '${eventType}_${groupId}_admin_${now}_$devId',
          type: eventType,
          payload: bodyPayload,
          timestamp: now,
        );
        wsRelay.sendToDevice(devId, envelope);
      }
    }
  }

  String? _promoteAdminIfNeeded(String groupId) {
    if (!db.hasAnyGroupMembersIncludingFederated(groupId)) return null;
    if (db.countGroupAdminsIncludingFederated(groupId) > 0) return null;
    if (db.getConversationMembers(groupId).isNotEmpty) {
      return db.promoteFirstRemainingGroupMemberToAdmin(groupId);
    }
    // No local members remain (federation-only group as seen from home) —
    // promote the alphabetically-first federated member instead.
    final federatedMembers = db.getFederatedConversationMembers(groupId);
    if (federatedMembers.isEmpty) return null;
    final sorted = [...federatedMembers]
      ..sort(
        (a, b) =>
            (a['account_id'] as String).compareTo(b['account_id'] as String),
      );
    final promoted = sorted.first['account_id'] as String;
    db.changeGroupMemberRole(groupId, promoted, 'ADMIN');
    return promoted;
  }

  /// The one 401 every handler in this module raises when the request
  /// carries no session. Returns the error rather than throwing it so the
  /// call sites stay `throw _unauthorized();` - visibly an exit, and
  /// type-checked as one.
  AppError _unauthorized() =>
      AppError.unauthorized('Unauthorized', code: RemoteErrorCode.unauthorized);
}
