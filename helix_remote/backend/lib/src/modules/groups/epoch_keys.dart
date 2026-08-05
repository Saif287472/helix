part of '../groups.dart';

/// Milestone 4.2: distributing a group's Sender Key epoch to every member
/// device, including the members whose home server is not this one.
mixin GroupsEpochKeyHandlers on GroupsModuleBase {
  /// Batched delivery of pairwise-wrapped group epoch keys (see
  /// `packages/helix_remote_groups`' `RemoteGroupService`). Any current
  /// admin — home or federated participant — may rotate and redistribute
  /// keys; this is deliberately not gated to the group's home server the
  /// way membership/role mutations are, since key material distribution
  /// doesn't require a single mutation authority, only that the sender is
  /// a legitimate admin (checked via [_isAdmin], which already sees
  /// federated admins once roster sync has run).
  Future<Response> _handleDeliverEpochKey(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();
    final accountId = auth['account_id'] as String;
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final groupId = body['group_id'] as String?;
      final epoch = body['epoch'] as int?;
      final keyId = body['key_id'] as String?;
      final rawDeliveries = body['deliveries'] as List?;
      if (groupId == null ||
          epoch == null ||
          keyId == null ||
          rawDeliveries == null) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'Missing group_id, epoch, key_id, or deliveries',
          }),
        );
      }
      if (!db.resolveGroupAuthority(groupId).exists) {
        return Response.notFound(jsonEncode({'error': 'Group not found'}));
      }
      if (!_isAdmin(groupId, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Only admins can distribute group keys'}),
        );
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final byDomain = <String, List<Map<String, dynamic>>>{};
      var localCount = 0;
      for (final raw in rawDeliveries) {
        final delivery = raw as Map<String, dynamic>;
        final recipientAccountId = delivery['recipient_account_id'] as String?;
        final recipientDeviceId = delivery['recipient_device_id'] as String?;
        final wrappedKey = delivery['wrapped_key'] as String?;
        if (recipientAccountId == null ||
            recipientDeviceId == null ||
            wrappedKey == null) {
          continue;
        }
        if (_isExternal(recipientAccountId)) {
          final domain = FederationClient.domainOf(recipientAccountId)!;
          (byDomain[domain] ??= []).add({
            'group_id': groupId,
            'epoch': epoch,
            'key_id': keyId,
            'sender_account_id': _qualify(accountId),
            'recipient_account_id': recipientAccountId,
            'recipient_device_id': recipientDeviceId,
            'wrapped_key': wrappedKey,
          });
          continue;
        }
        if (!db.isDeviceActive(recipientAccountId, recipientDeviceId)) continue;
        localCount++;
        final eventId = 'grp_epoch_${groupId}_${epoch}_$recipientDeviceId';
        final deviceSeq = db.writeDeviceEvent(
          eventId: eventId,
          recipientDeviceId: recipientDeviceId,
          eventType: 'group_epoch_key',
          payload: jsonEncode({
            'group_id': groupId,
            'epoch': epoch,
            'key_id': keyId,
            'sender_account_id': _qualify(accountId),
            'wrapped_key': wrappedKey,
          }),
        );
        wsRelay.sendToDevice(recipientDeviceId, {
          'event_id': eventId,
          'schema_version': 1,
          'timestamp': now,
          'type': 'group_epoch_key',
          'payload': {
            'group_id': groupId,
            'epoch': epoch,
            'key_id': keyId,
            'sender_account_id': _qualify(accountId),
            'wrapped_key': wrappedKey,
          },
          'server_sequence': deviceSeq,
        });
      }

      var federatedDomainCount = 0;
      if (byDomain.isNotEmpty) {
        if (federationClient == null) {
          return Response(
            503,
            body: jsonEncode({'error': 'Federation is not configured'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
        federatedDomainCount = byDomain.length;
        await Future.wait(
          byDomain.entries.map((entry) async {
            try {
              await federationClient!.deliverEpochKeyBatch(
                domain: entry.key,
                deliveries: entry.value,
              );
            } catch (_) {
              db.enqueueOutbox(
                's2s_epochkey_${groupId}_${epoch}_${entry.key}_${DateTime.now().millisecondsSinceEpoch}',
                'S2S_EPOCH_KEY',
                jsonEncode({'domain': entry.key, 'deliveries': entry.value}),
              );
            }
          }),
        );
      }

      return Response.ok(
        jsonEncode({
          'group_id': groupId,
          'epoch': epoch,
          'local_deliveries': localCount,
          'federated_domains': federatedDomainCount,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------
}
