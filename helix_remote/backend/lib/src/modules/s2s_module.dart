import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:helix_remote_backend/src/app_error.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/federation.dart';
import 'package:helix_remote_backend/src/modules/calls.dart';
import 'package:helix_remote_backend/src/modules/groups.dart';
import 'package:helix_remote_backend/src/modules/messaging.dart';
import 'package:helix_remote_backend/src/server_log.dart';

class S2SModule {
  final BackendDatabase db;
  final MessageRelay relay;
  final String? localDomain;
  final GroupsModule? groupsModule;
  final CallsModule? callsModule;

  S2SModule(
    this.db,
    this.relay, {
    this.localDomain,
    this.groupsModule,
    this.callsModule,
  });

  Handler get router {
    final router = Router();
    router.get('/prekeys/bundle', _prekeysBundleHandler);
    router.post('/messages/proxy', _messagesProxyHandler);
    router.post('/messages/proxy-batch', _messagesProxyBatchHandler);
    router.post('/conversations/event-relay-batch', _eventRelayBatchHandler);
    router.post('/groups/sync', _groupsSyncHandler);
    router.get('/groups/state', _groupsStateHandler);
    router.post('/groups/action', _groupsActionHandler);
    router.post(
      '/groups/epoch-key/deliver-batch',
      _groupsEpochKeyDeliverBatchHandler,
    );
    router.post('/calls/signal', _callsSignalHandler);
    return withAppErrorHandling(router.call);
  }

  Future<Response> _prekeysBundleHandler(Request request) async {
    final requestedAccountId = request.url.queryParameters['account_id'];
    final targetAccountId = _localAccountId(requestedAccountId);
    if (targetAccountId == null) {
      throw AppError.badRequest('Missing account_id parameter');
    }

    try {
      final devices = db.getDevices(targetAccountId);
      if (devices.isEmpty) {
        throw AppError.notFound('No active devices found for this account');
      }

      final deviceBundles = <Map<String, dynamic>>[];
      for (final device in devices) {
        final deviceId = device['device_id'] as String;
        final bundle = db.getPrekeyBundleForDevice(targetAccountId, deviceId);
        if (bundle != null) {
          deviceBundles.add(bundle);
        }
      }

      final account = db.getAccount(targetAccountId);
      final accountIdentityKey = account?['identity_public_key'] as String?;

      return Response.ok(
        jsonEncode({
          'account_id': targetAccountId,
          'qualified_account_id': requestedAccountId ?? targetAccountId,
          'account_identity_key': accountIdentityKey,
          'devices': deviceBundles,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } on AppError {
      rethrow;
    } catch (e, stack) {
      // A federated peer gets the generic body the middleware produces; the
      // detail this used to interpolate into the response stays here, where
      // it belongs.
      logServerError('S2S handler failed: $e\n$stack');
      throw AppError.internal();
    }
  }

  Future<Response> _messagesProxyHandler(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final result = _applyProxiedMessage(body);
      if (result['ok'] != true) {
        throw AppError(
          result['error'] as String,
          statusCode: result['status'] as int,
        );
      }
      return Response.ok(
        jsonEncode({
          'message': 'Message proxied successfully',
          'sequence': result['sequence'],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } on AppError {
      rethrow;
    } catch (e, stack) {
      // A federated peer gets the generic body the middleware produces; the
      // detail this used to interpolate into the response stays here, where
      // it belongs.
      logServerError('S2S handler failed: $e\n$stack');
      throw AppError.internal();
    }
  }

  /// Batched variant of `/messages/proxy` (Milestone 4.3): delivers every
  /// envelope destined for this server in one signed request instead of one
  /// HTTP round-trip per recipient device, which matters once a group
  /// message fans out to many federated devices on the same remote server.
  /// A single bad envelope doesn't fail the whole batch.
  Future<Response> _messagesProxyBatchHandler(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final envelopes = body['envelopes'] as List?;
      if (envelopes == null) {
        throw AppError.badRequest('Missing envelopes');
      }
      final results = <Map<String, dynamic>>[];
      for (final raw in envelopes) {
        results.add(_applyProxiedMessage(raw as Map<String, dynamic>));
      }
      return Response.ok(
        jsonEncode({'results': results}),
        headers: {'Content-Type': 'application/json'},
      );
    } on AppError {
      rethrow;
    } catch (e, stack) {
      // A federated peer gets the generic body the middleware produces; the
      // detail this used to interpolate into the response stays here, where
      // it belongs.
      logServerError('S2S handler failed: $e\n$stack');
      throw AppError.internal();
    }
  }

  Map<String, dynamic> _applyProxiedMessage(Map<String, dynamic> body) {
    final messageId = body['message_id'] as String?;
    final conversationId = body['conversation_id'] as String?;
    final senderAccountId = body['sender_account_id'] as String?;
    final senderDeviceId = body['sender_device_id'] as String?;
    final recipientAccountId = _localAccountId(
      body['recipient_account_id'] as String?,
    );
    final recipientDeviceId = body['recipient_device_id'] as String?;
    final ciphertext = body['ciphertext'] as String?;

    if (messageId == null ||
        conversationId == null ||
        senderAccountId == null ||
        senderDeviceId == null ||
        recipientAccountId == null ||
        recipientDeviceId == null ||
        ciphertext == null) {
      return {
        'ok': false,
        'status': 400,
        'error': 'Missing proxy message fields',
        'recipient_device_id': recipientDeviceId,
      };
    }

    if (!db.isDeviceActive(recipientAccountId, recipientDeviceId)) {
      return {
        'ok': false,
        'status': 404,
        'error': 'Recipient device not found',
        'recipient_device_id': recipientDeviceId,
      };
    }

    final outstandingCount = db.getMessageCountForDevice(recipientDeviceId);
    if (outstandingCount >= 5000) {
      return {
        'ok': false,
        'status': 403,
        'error': 'Recipient device mailbox quota exceeded.',
        'recipient_device_id': recipientDeviceId,
      };
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final eventId = 'evt_${messageId}_$recipientDeviceId';
    final deviceSeq = db.writeDeviceEvent(
      eventId: eventId,
      recipientDeviceId: recipientDeviceId,
      eventType: 'chat_message',
      payload: jsonEncode({
        'message_id': messageId,
        'conversation_id': conversationId,
        'sender_account_id': senderAccountId,
        'sender_device_id': senderDeviceId,
        'recipient_account_id': recipientAccountId,
        'federated': true,
        'ciphertext': ciphertext,
      }),
    );

    relay.sendToDevice(recipientDeviceId, {
      'event_id': eventId,
      'schema_version': 1,
      'timestamp': now,
      'type': 'chat_message',
      'payload': {
        'message_id': messageId,
        'conversation_id': conversationId,
        'sender_account_id': senderAccountId,
        'sender_device_id': senderDeviceId,
        'recipient_account_id': recipientAccountId,
        'federated': true,
        'ciphertext': ciphertext,
      },
      'server_sequence': deviceSeq,
    });

    return {
      'ok': true,
      'sequence': deviceSeq,
      'recipient_device_id': recipientDeviceId,
    };
  }

  /// Milestone 4.3: federation-aware counterpart of
  /// `MessagingModule._fanOutConversationEvent` — relays a batch of
  /// edits/reactions/receipts (durable) or typing indicators (best-effort)
  /// to this server's local devices on behalf of a remote sender.
  Future<Response> _eventRelayBatchHandler(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final events = body['events'] as List?;
      if (events == null) {
        throw AppError.badRequest('Missing events');
      }
      var delivered = 0;
      for (final raw in events) {
        final event = raw as Map<String, dynamic>;
        // Unlike chat messages (client-encrypted per device via a known
        // prekey bundle), these events carry no per-device envelope — the
        // sending server only knows the recipient *account*; we fan out to
        // every one of that account's devices ourselves, mirroring
        // MessagingModule._fanOutConversationEvent's local loop.
        final recipientAccountId = _localAccountId(
          event['recipient_account_id'] as String?,
        );
        final eventType = event['event_type'] as String?;
        final eventKey = event['event_key'] as String?;
        final payload = event['payload'] as Map<String, dynamic>?;
        final persist = event['persist'] as bool? ?? true;
        if (recipientAccountId == null ||
            eventType == null ||
            payload == null) {
          continue;
        }
        for (final dev in db.getDevices(recipientAccountId)) {
          final targetDeviceId = dev['device_id'] as String;
          int? deviceSeq;
          final eventId =
              'evt_${eventType}_${eventKey ?? DateTime.now().microsecondsSinceEpoch}_$targetDeviceId';
          if (persist) {
            deviceSeq = db.writeDeviceEvent(
              eventId: eventId,
              recipientDeviceId: targetDeviceId,
              eventType: eventType,
              payload: jsonEncode(payload),
            );
          }
          relay.sendToDevice(targetDeviceId, {
            'event_id': eventId,
            'schema_version': 1,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'type': eventType,
            'payload': payload,
            'server_sequence': deviceSeq,
          });
          delivered++;
        }
      }
      return Response.ok(
        jsonEncode({'delivered': delivered}),
        headers: {'Content-Type': 'application/json'},
      );
    } on AppError {
      rethrow;
    } catch (e, stack) {
      // A federated peer gets the generic body the middleware produces; the
      // detail this used to interpolate into the response stays here, where
      // it belongs.
      logServerError('S2S handler failed: $e\n$stack');
      throw AppError.internal();
    }
  }

  // ---------------------------------------------------------------------
  // Milestone 4.1: group membership sync/action + Milestone 4.2: epoch keys
  // ---------------------------------------------------------------------

  Future<Response> _groupsSyncHandler(Request request) async {
    try {
      final senderId = request.context['s2s_sender_id'] as String?;
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final groupId = body['group_id'] as String?;
      final homeServerId = body['home_server_id'] as String?;
      final homeDomain = body['home_domain'] as String?;
      if (groupId == null || homeServerId == null || homeDomain == null) {
        throw AppError.badRequest(
          'Missing group_id, home_server_id, or home_domain',
        );
      }
      if (homeServerId != senderId) {
        throw AppError.unauthorized(
          'Only a group\'s home server may push sync for it',
        );
      }
      final existing = db.getFederatedGroup(groupId);
      if (existing != null && existing['home_server_id'] != homeServerId) {
        throw AppError.unauthorized('Group home server mismatch');
      }

      if (body.containsKey('members')) {
        final createdAt =
            body['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch;
        db.ensureConversationShell(groupId, body['name'] as String?, createdAt);
        db.upsertFederatedGroup(
          groupId: groupId,
          homeServerId: homeServerId,
          homeDomain: homeDomain,
          creatorId: body['creator_id'] as String? ?? '',
          name: body['name'] as String?,
          encryptionKeyId: body['encryption_key_id'] as String? ?? '',
          status: body['status'] as String? ?? 'ACTIVE',
          addPolicy: body['add_policy'] as String? ?? 'EVERYONE',
          createdAt: createdAt,
        );
        final rawMembers = (body['members'] as List)
            .cast<Map<String, dynamic>>();
        db.applyFederatedGroupRoster(
          groupId: groupId,
          members: rawMembers,
          localDomain: localDomain,
        );
        final after = db.getConversationMembers(groupId).toSet();
        final event = body['event'] as Map<String, dynamic>?;
        _notifyLocalRosterChange(groupId, after, event);
      }

      if (body.containsKey('pending_invites')) {
        for (final raw in (body['pending_invites'] as List)) {
          final invite = raw as Map<String, dynamic>;
          final inviteId = invite['invite_id'] as String?;
          // Home only knows the invitee's qualified id; this server must
          // resolve it to the bare local account id it actually owns
          // (mirrors _localAccountId's role for chat-message proxying).
          final inviteeId = _localAccountId(invite['invitee_id'] as String?);
          if (inviteId == null || inviteeId == null) continue;
          db.upsertFederatedGroupInvite(
            inviteId: inviteId,
            groupId: groupId,
            homeServerId: homeServerId,
            homeDomain: homeDomain,
            inviterId: invite['inviter_id'] as String? ?? '',
            inviteeId: inviteeId,
            status: invite['status'] as String? ?? 'PENDING',
            createdAt:
                invite['created_at'] as int? ??
                DateTime.now().millisecondsSinceEpoch,
          );
          if (db.accountExists(inviteeId)) {
            final invitePayload = {
              'invite_id': inviteId,
              'group_id': groupId,
              'inviter_id': invite['inviter_id'],
              'created_at': invite['created_at'],
            };
            // Durable (unlike the local same-server invite path): a
            // cross-server push can land while the invitee's device isn't
            // connected, and there's no "reconnect and refetch" fallback
            // for it the way a local device implicitly has.
            for (final dev in db.getDevices(inviteeId)) {
              final devId = dev['device_id'] as String;
              final eventId = 'group_invite_${inviteId}_$devId';
              final deviceSeq = db.writeDeviceEvent(
                eventId: eventId,
                recipientDeviceId: devId,
                eventType: 'group_invite',
                payload: jsonEncode(invitePayload),
              );
              relay.sendToDevice(devId, {
                'event_id': eventId,
                'schema_version': 1,
                'timestamp': DateTime.now().millisecondsSinceEpoch,
                'type': 'group_invite',
                'payload': invitePayload,
                'server_sequence': deviceSeq,
              });
            }
          }
        }
      }

      return Response.ok(
        jsonEncode({'status': 'synced', 'group_id': groupId}),
        headers: {'Content-Type': 'application/json'},
      );
    } on AppError {
      rethrow;
    } catch (e, stack) {
      // A federated peer gets the generic body the middleware produces; the
      // detail this used to interpolate into the response stays here, where
      // it belongs.
      logServerError('S2S handler failed: $e\n$stack');
      throw AppError.internal();
    }
  }

  void _notifyLocalRosterChange(
    String groupId,
    Set<String> after,
    Map<String, dynamic>? event,
  ) {
    final eventType = event?['type'] as String? ?? 'membership_changed';
    final payload = event != null
        ? (Map<String, dynamic>.from(event)..remove('type'))
        : {'group_id': groupId, 'action': 'synced'};
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final memberId in after) {
      for (final dev in db.getDevices(memberId)) {
        final devId = dev['device_id'] as String;
        final eventId = '${eventType}_${groupId}_${now}_$devId';
        final deviceSeq = db.writeDeviceEvent(
          eventId: eventId,
          recipientDeviceId: devId,
          eventType: eventType,
          payload: jsonEncode(payload),
        );
        relay.sendToDevice(devId, {
          'event_id': eventId,
          'schema_version': 1,
          'timestamp': now,
          'type': eventType,
          'payload': payload,
          'server_sequence': deviceSeq,
        });
      }
    }
  }

  Future<Response> _groupsStateHandler(Request request) async {
    final groupId = request.url.queryParameters['group_id'];
    if (groupId == null) {
      throw AppError.badRequest('Missing group_id');
    }
    final group = db.getGroup(groupId);
    if (group == null) {
      throw AppError.notFound('This server is not home for that group');
    }
    final members = <Map<String, dynamic>>[
      for (final id in db.getConversationMembers(groupId))
        {
          'account_id': _qualifyLocal(id),
          'role':
              db.getGroupMemberRoleIncludingFederated(groupId, id) ?? 'MEMBER',
        },
      for (final m in db.getFederatedConversationMembers(groupId))
        {'account_id': m['account_id'], 'role': m['role']},
    ];
    return Response.ok(
      jsonEncode({
        'group_id': groupId,
        'name': group['name'],
        'creator_id': _qualifyLocal(group['creator_id'] as String),
        'encryption_key_id': group['encryption_key_id'],
        'status': group['status'],
        'add_policy': group['add_policy'],
        'created_at': group['created_at'],
        'members': members,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _groupsActionHandler(Request request) async {
    if (groupsModule == null) {
      throw AppError.serviceUnavailable('Group federation is not configured');
    }
    try {
      final senderId = request.context['s2s_sender_id'] as String?;
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final groupId = body['group_id'] as String?;
      final action = body['action'] as String?;
      final actingAccountId = body['acting_account_id'] as String?;
      final payload = body['payload'] as Map<String, dynamic>? ?? {};
      if (groupId == null || action == null || actingAccountId == null) {
        throw AppError.badRequest(
          'Missing group_id, action, or acting_account_id',
        );
      }
      if (db.getGroup(groupId) == null) {
        throw AppError.conflict(
          'This server is not the home server for that group',
        );
      }
      // Defense-in-depth: if we already know the sender's domain, the
      // acting account must belong to it (a server may only proxy actions
      // for its own local users).
      final senderRecord =
          senderId == null ? null : db.getFederationServerById(senderId);
      final senderDomain = senderRecord?['domain'] as String?;
      final actingDomain = FederationClient.domainOf(actingAccountId);

      // S2S actions require an established, verified server domain.
      if (senderDomain == null ||
          actingDomain == null ||
          senderDomain != actingDomain) {
        throw AppError.unauthorized(
          'Acting account domain ($actingDomain) does not match verified sending server domain ($senderDomain)',
        );
      }
      return await groupsModule!.applyRemoteAction(
        action,
        groupId,
        actingAccountId,
        payload,
      );
    } on AppError {
      rethrow;
    } catch (e, stack) {
      // A federated peer gets the generic body the middleware produces; the
      // detail this used to interpolate into the response stays here, where
      // it belongs.
      logServerError('S2S handler failed: $e\n$stack');
      throw AppError.internal();
    }
  }

  Future<Response> _groupsEpochKeyDeliverBatchHandler(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final deliveries = body['deliveries'] as List?;
      if (deliveries == null) {
        throw AppError.badRequest('Missing deliveries');
      }
      var delivered = 0;
      for (final raw in deliveries) {
        final delivery = raw as Map<String, dynamic>;
        final recipientAccountId = _localAccountId(
          delivery['recipient_account_id'] as String?,
        );
        final recipientDeviceId = delivery['recipient_device_id'] as String?;
        final wrappedKey = delivery['wrapped_key'] as String?;
        final groupId = delivery['group_id'] as String?;
        final epoch = delivery['epoch'];
        final keyId = delivery['key_id'] as String?;
        if (recipientAccountId == null ||
            recipientDeviceId == null ||
            wrappedKey == null ||
            groupId == null ||
            keyId == null) {
          continue;
        }
        if (!db.isDeviceActive(recipientAccountId, recipientDeviceId)) continue;
        final eventId = 'grp_epoch_${groupId}_${epoch}_$recipientDeviceId';
        final payload = {
          'group_id': groupId,
          'epoch': epoch,
          'key_id': keyId,
          'sender_account_id': delivery['sender_account_id'],
          'wrapped_key': wrappedKey,
        };
        final deviceSeq = db.writeDeviceEvent(
          eventId: eventId,
          recipientDeviceId: recipientDeviceId,
          eventType: 'group_epoch_key',
          payload: jsonEncode(payload),
        );
        relay.sendToDevice(recipientDeviceId, {
          'event_id': eventId,
          'schema_version': 1,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'type': 'group_epoch_key',
          'payload': payload,
          'server_sequence': deviceSeq,
        });
        delivered++;
      }
      return Response.ok(
        jsonEncode({'delivered': delivered}),
        headers: {'Content-Type': 'application/json'},
      );
    } on AppError {
      rethrow;
    } catch (e, stack) {
      // A federated peer gets the generic body the middleware produces; the
      // detail this used to interpolate into the response stays here, where
      // it belongs.
      logServerError('S2S handler failed: $e\n$stack');
      throw AppError.internal();
    }
  }

  // ---------------------------------------------------------------------
  // Milestone 5.1: federated WebRTC call signaling
  // ---------------------------------------------------------------------

  Future<Response> _callsSignalHandler(Request request) async {
    if (callsModule == null) {
      throw AppError.serviceUnavailable('Call federation is not configured');
    }
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final senderAccountId = body['sender_account_id'] as String?;
      final senderDeviceId = body['sender_device_id'] as String?;
      final signal = body['signal'] as Map<String, dynamic>?;
      if (senderAccountId == null || senderDeviceId == null || signal == null) {
        throw AppError.badRequest(
          'Missing sender_account_id, sender_device_id, or signal',
        );
      }
      final result = await callsModule!.receiveFederatedSignal(
        senderAccountId: senderAccountId,
        senderDeviceId: senderDeviceId,
        signal: signal,
        requestId: body['request_id'] as String?,
      );
      final status = switch (result['status']) {
        'delivered' || 'queued' || 'partial' || 'duplicate' => 200,
        'no_active_devices' || 'answered_elsewhere' => 409,
        'rate_limited' => 429,
        'expired' => 410,
        _ => 400,
      };
      return Response(
        status,
        body: jsonEncode(result),
        headers: {'Content-Type': 'application/json'},
      );
    } on AppError {
      rethrow;
    } catch (e, stack) {
      // A federated peer gets the generic body the middleware produces; the
      // detail this used to interpolate into the response stays here, where
      // it belongs.
      logServerError('S2S handler failed: $e\n$stack');
      throw AppError.internal();
    }
  }

  String _qualifyLocal(String accountId) {
    if (accountId.contains('@') ||
        localDomain == null ||
        localDomain!.isEmpty) {
      return accountId;
    }
    return '$accountId@${localDomain!.toLowerCase()}';
  }

  String? _localAccountId(String? accountId) {
    if (accountId == null || accountId.isEmpty) return null;
    final at = accountId.lastIndexOf('@');
    if (at <= 0 || at == accountId.length - 1) return accountId;
    final domain = accountId.substring(at + 1).toLowerCase();
    if (localDomain != null && domain == localDomain!.toLowerCase()) {
      return accountId.substring(0, at);
    }
    return accountId;
  }
}
