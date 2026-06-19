import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:helix_remote_backend/src/database.dart';

abstract class MessageRelay {
  void sendToDevice(String deviceId, Map<String, dynamic> payload);
}

class MessagingModule {
  final BackendDatabase db;
  final MessageRelay relay;
  final void Function(String messageId)? onMessageDeleted;

  MessagingModule(this.db, this.relay, {this.onMessageDeleted});

  Router get router {
    final router = Router();
    router.post('/conversations/create', _createConversationHandler);
    router.post('/send', _sendMessageHandler);
    router.get('/sync', _syncMessagesHandler);
    router.post('/cursor', _updateCursorHandler);
    router.post('/delete', _deleteMessageHandler);
    return router;
  }

  Future<Response> _createConversationHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final conversationId = body['conversation_id'] as String?;
      final type = body['type'] as String?; // 'DIRECT' or 'GROUP'
      final title = body['title'] as String?;
      final membersList = body['members'] as List?;

      if (conversationId == null || type == null || membersList == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing conversation fields'}),
        );
      }

      final senderAccountId = auth['account_id'] as String;
      final members = membersList.map((m) => m as String).toList();

      // Ensure sender is included in the conversation
      if (!members.contains(senderAccountId)) {
        members.add(senderAccountId);
      }

      db.createConversation(conversationId, type, title, members);
      db.logAudit(
        senderAccountId,
        auth['device_id'] as String?,
        'CONVERSATION_CREATED',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(
        jsonEncode({
          'message': 'Conversation created successfully',
          'conversation_id': conversationId,
        }),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  Future<Response> _sendMessageHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final messageId = body['message_id'] as String?;
      final conversationId = body['conversation_id'] as String?;
      final envelopes = body['envelopes'] as List?;

      if (messageId == null ||
          conversationId == null ||
          envelopes == null ||
          envelopes.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing message sending fields'}),
        );
      }

      final senderAccountId = auth['account_id'] as String;
      final senderDeviceId = auth['device_id'] as String;

      // Verify sender is a member of the conversation
      if (!db.isConversationMember(conversationId, senderAccountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'You are not a member of this conversation'}),
        );
      }

      final conversationMembers = db.getConversationMembers(conversationId);
      final requiredRecipientDeviceIds = <String>{};
      final allowedRecipientDeviceIds = <String>{};
      for (final memberId in conversationMembers) {
        for (final device in db.getDevices(memberId)) {
          final deviceId = device['device_id'] as String;
          allowedRecipientDeviceIds.add(deviceId);
          if (deviceId == senderDeviceId) {
            continue;
          }
          if (db.isBlocked(memberId, senderAccountId)) {
            continue;
          }
          requiredRecipientDeviceIds.add(deviceId);
        }
      }

      final envelopeByDeviceId = <String, Map<String, dynamic>>{};
      for (final env in envelopes) {
        final envMap = env as Map<String, dynamic>;
        if (envMap.containsKey('plaintext') ||
            envMap.containsKey('message_text') ||
            envMap.containsKey('body')) {
          return Response.badRequest(
            body: jsonEncode({
              'error': 'Message envelopes must be ciphertext-only',
            }),
          );
        }
        final recipientDeviceId = envMap['recipient_device_id'] as String?;
        final ciphertext = envMap['ciphertext'] as String?;
        if (recipientDeviceId == null ||
            ciphertext == null ||
            ciphertext.isEmpty) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Invalid per-device envelope'}),
          );
        }
        if (!allowedRecipientDeviceIds.contains(recipientDeviceId)) {
          return Response.forbidden(
            jsonEncode({'error': 'Envelope targets a non-member device'}),
          );
        }
        envelopeByDeviceId[recipientDeviceId] = envMap;
      }

      final missingTargets = requiredRecipientDeviceIds
          .where((deviceId) => !envelopeByDeviceId.containsKey(deviceId))
          .toList();
      if (missingTargets.isNotEmpty) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'Missing per-device encrypted envelopes',
            'missing_device_count': missingTargets.length,
          }),
        );
      }

      int allocatedSeq = 0;
      final processedEnvelopes = <Map<String, dynamic>>[];

      for (final entry in envelopeByDeviceId.entries) {
        final recipientDeviceId = entry.key;
        final ciphertext = entry.value['ciphertext'] as String;

        // We'll query devices table for the owner of recipientDeviceId
        final ownerRows = db.getDevicesOfDevice(recipientDeviceId);
        if (ownerRows.isEmpty) {
          continue; // Device not found
        }
        final recipientAccountId = ownerRows.first['account_id'] as String;

        // Check blocking enforcement
        if (db.isBlocked(recipientAccountId, senderAccountId)) {
          // Sender is blocked by recipient, ignore/silent drop this envelope for security/privacy
          continue;
        }

        // Check mailbox quotas (P10-021)
        final outstandingCount = db.getMessageCountForDevice(recipientDeviceId);
        if (outstandingCount >= 5000) {
          return Response.forbidden(
            jsonEncode({
              'error':
                  'Recipient device mailbox quota exceeded. Try again later.',
            }),
          );
        }

        // Save envelope
        allocatedSeq = db.saveMessage(
          messageId: messageId,
          conversationId: conversationId,
          senderAccountId: senderAccountId,
          senderDeviceId: senderDeviceId,
          recipientDeviceId: recipientDeviceId,
          ciphertext: ciphertext,
        );

        final envelopePayload = {
          'type': 'message',
          'message_id': messageId,
          'conversation_id': conversationId,
          'sender_account_id': senderAccountId,
          'sender_device_id': senderDeviceId,
          'recipient_device_id': recipientDeviceId,
          'ciphertext': ciphertext,
          'server_sequence': allocatedSeq,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };

        // Enqueue transaction outbox for push notification worker
        db.enqueueOutbox(
          'outbox_${messageId}_$recipientDeviceId',
          'PUSH_NOTIFICATION',
          jsonEncode({
            'recipient_account_id': recipientAccountId,
            'recipient_device_id': recipientDeviceId,
            'message_id': messageId,
            'conversation_id': conversationId,
          }),
        );

        // Relay ciphertext message over WebSocket immediately if online
        relay.sendToDevice(recipientDeviceId, envelopePayload);
        processedEnvelopes.add(envelopePayload);
      }

      db.logAudit(
        senderAccountId,
        senderDeviceId,
        'MESSAGE_SENT',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(
        jsonEncode({
          'message': 'Message processed',
          'sequence': allocatedSeq,
          'envelopes_count': processedEnvelopes.length,
        }),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  Future<Response> _syncMessagesHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    final params = request.url.queryParameters;
    final conversationId = params['conversation_id'];
    final sinceSeqStr = params['since_sequence'];

    final accountId = auth['account_id'] as String;
    final deviceId = auth['device_id'] as String;

    try {
      List<Map<String, dynamic>> messages;

      if (conversationId != null) {
        if (!db.isConversationMember(conversationId, accountId)) {
          return Response.forbidden(
            jsonEncode({'error': 'You are not a member of this conversation'}),
          );
        }
        final sinceSeq = sinceSeqStr != null ? int.parse(sinceSeqStr) : 0;
        messages = db.getMessagesForDevice(deviceId, conversationId, sinceSeq);
      } else {
        // Fetch all offline/catchup messages
        messages = db.getOfflineMessagesForDevice(deviceId);
      }

      return Response.ok(jsonEncode({'messages': messages}));
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  Future<Response> _updateCursorHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final conversationId = body['conversation_id'] as String?;
      final sequence = body['sequence'] as int?;

      if (conversationId == null || sequence == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing cursor update fields'}),
        );
      }

      final accountId = auth['account_id'] as String;
      final deviceId = auth['device_id'] as String;

      db.updateSyncCursor(accountId, deviceId, conversationId, sequence);

      return Response.ok(jsonEncode({'message': 'Sync cursor updated'}));
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  Future<Response> _deleteMessageHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final messageId = body['message_id'] as String?;

      if (messageId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing message_id'}),
        );
      }

      final accountId = auth['account_id'] as String;
      final deviceId = auth['device_id'] as String;

      // Fetch message from DB to verify owner
      final msg = db.getMessage(messageId);
      if (msg == null) {
        return Response.notFound(jsonEncode({'error': 'Message not found'}));
      }

      if (msg['sender_account_id'] != accountId) {
        return Response.forbidden(
          jsonEncode({'error': 'You can only delete your own messages'}),
        );
      }

      final conversationId = msg['conversation_id'] as String;

      // Clean up any referenced attachments if count drops to 0
      onMessageDeleted?.call(messageId);

      // Delete message from messages table
      db.deleteMessage(messageId);

      // Save tombstone in database (P10-018)
      db.saveTombstone(messageId, 'MESSAGE');
      db.markBackupNeedsReupload(
        accountId,
        DateTime.now().millisecondsSinceEpoch,
      );

      // Relay tombstone event via WebSocket to other active devices of the conversation
      final conversationMembers = db.getConversationMembers(conversationId);
      for (final memberId in conversationMembers) {
        // Query active devices of this member and send delete event
        final memberDevices = db.getDevices(memberId);
        for (final dev in memberDevices) {
          final targetDeviceId = dev['device_id'] as String;
          if (targetDeviceId != deviceId) {
            final deletePayload = {
              'type': 'message_deleted',
              'message_id': messageId,
              'conversation_id': conversationId,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            };
            relay.sendToDevice(targetDeviceId, deletePayload);
          }
        }
      }

      db.logAudit(
        accountId,
        deviceId,
        'MESSAGE_DELETED',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(
        jsonEncode({
          'message': 'Message deleted successfully',
          'message_id': messageId,
        }),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }
}
