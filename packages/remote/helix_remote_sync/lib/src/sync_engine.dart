import 'dart:convert';
import 'dart:math' as math;

import 'package:helix_remote_api/api/realtime_envelope.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';

abstract class SyncGateway {
  Future<List<RemoteRealtimeEnvelope>> fetchInboundEvents({
    required int sinceSequence,
  });

  Future<void> sendOutboundOperation({
    required String opId,
    required String type,
    required Map<String, dynamic> payload,
  });
}

class RemoteSyncEngine {
  RemoteSyncEngine(this.db, {this.diagnostics});

  final HelixRemoteDatabase db;
  final void Function(String message)? diagnostics;

  static const String _globalSyncCursorId = '__remote_global_stream__';

  /// Synchronises incoming events from the server since the last stored cursor.
  ///
  /// The inbound stream is account/device scoped. Individual events carry their
  /// own authoritative entity IDs, such as conversation_id.
  Future<int> syncInbound(SyncGateway gateway) async {
    final lastSeq = db.getSyncCursor(_globalSyncCursorId);
    final envelopes = await gateway.fetchInboundEvents(sinceSequence: lastSeq);

    final sortedEnvelopes = List<RemoteRealtimeEnvelope>.from(
      envelopes,
    )..sort((a, b) => (a.serverSequence ?? 0).compareTo(b.serverSequence ?? 0));

    int appliedCount = 0;
    int highestSeq = lastSeq;

    db.rawExecute('BEGIN TRANSACTION;');
    try {
      for (final env in sortedEnvelopes) {
        final seq = env.serverSequence ?? 0;
        if (db.hasProcessedEventId(env.eventId)) {
          continue;
        }

        if (seq <= lastSeq) {
          throw StateError(
            'Remote sync sequence regression for unseen event type=${env.type}',
          );
        }

        final event = _InboundSyncEvent.tryParse(env);
        if (event == null) {
          _recordUnknownEvent(env);
          _recordProcessedEvent(env, seq);
          highestSeq = seq;
          continue;
        }

        if (event is _SyncMarkerEvent) {
          _recordProcessedEvent(env, seq);
          highestSeq = seq;
          appliedCount++;
          continue;
        }

        final applied = event.apply(db, env);
        _recordProcessedEvent(env, seq);
        highestSeq = seq;
        if (applied) {
          appliedCount++;
        }
      }

      if (highestSeq > lastSeq) {
        db.updateSyncCursor(_globalSyncCursorId, highestSeq);
      }

      db.rawExecute('COMMIT;');
    } catch (_) {
      db.rawExecute('ROLLBACK;');
      rethrow;
    }

    return appliedCount;
  }

  void _recordUnknownEvent(RemoteRealtimeEnvelope env) {
    diagnostics?.call(
      'Unknown Remote sync event skipped '
      'type=${_redactDiagnosticField(env.type)} '
      'schema=${env.schemaVersion} '
      'sequence=${env.serverSequence ?? 0}',
    );
  }

  String _redactDiagnosticField(String value) {
    if (value.length <= 32) return value;
    return '${value.substring(0, 32)}...';
  }

  void _recordProcessedEvent(RemoteRealtimeEnvelope env, int sequence) {
    db.saveProcessedEvent(
      eventId: env.eventId,
      serverSequence: sequence,
      eventType: env.type,
      contentFingerprint: _eventFingerprint(env),
    );
  }

  String _eventFingerprint(RemoteRealtimeEnvelope env) {
    final payloadKeys = env.payload.keys.toList()..sort();
    return jsonEncode({
      'type': env.type,
      'schema_version': env.schemaVersion,
      'server_sequence': env.serverSequence,
      'payload_keys': payloadKeys,
    });
  }

  /// Processes the outbound pending-operations queue with exponential backoff.
  Future<int> processOutboundQueue(SyncGateway gateway) async {
    final pendingOps = db.getPendingOperations();
    int processedCount = 0;

    for (final op in pendingOps) {
      final opId = op['op_id'] as String;
      final type = op['type'] as String;
      final payloadStr = op['payload'] as String;
      final retries = op['retries'] as int;

      try {
        final payload = jsonDecode(payloadStr) as Map<String, dynamic>;

        await gateway.sendOutboundOperation(
          opId: opId,
          type: type,
          payload: payload,
        );

        db.updateOperationStatus(opId, 'COMPLETED', retries);
        processedCount++;
      } catch (_) {
        final nextRetries = retries + 1;
        final nextStatus = nextRetries >= 5 ? 'FAILED' : 'PENDING';
        db.updateOperationStatus(opId, nextStatus, nextRetries);

        if (nextRetries < 5) {
          final backoffMs = 1000 * (1 << nextRetries);
          final jitterMs = math.Random().nextInt(500);
          final nextAttempt =
              DateTime.now().millisecondsSinceEpoch + backoffMs + jitterMs;
          db.scheduleNextOperationAttempt(opId, nextAttempt);
        }
      }
    }

    return processedCount;
  }
}

abstract class _InboundSyncEvent {
  const _InboundSyncEvent();

  static _InboundSyncEvent? tryParse(RemoteRealtimeEnvelope env) {
    if (env.isUnrecognized) return null;

    switch (env.type) {
      case 'chat_message':
        return const _MessageCreatedEvent();
      case 'message_deleted':
      case 'message_tombstoned':
        return const _MessageDeletedEvent();
      case 'message_edited':
        return const _MessageEditedEvent();
      case 'reaction_added':
      case 'reaction_removed':
        return const _ReactionEvent();
      case 'contact_updated':
        return const _ContactUpdatedEvent();
      case 'contact_removed':
        return const _ContactRemovedEvent();
      case 'profile_updated':
        return const _ProfileUpdatedEvent();
      case 'privacy_updated':
      case 'presence_updated':
      case 'safety_notice':
        return const _SyncMarkerEvent();
      case 'read_receipt':
        return const _ReceiptEvent('READ');
      case 'delivery_receipt':
        return const _ReceiptEvent('DELIVERY');
      case 'membership_changed':
        return const _MembershipChangedEvent();
      case 'conversation_created':
        return const _ConversationCreatedEvent();
      case 'typing':
        return const _TypingEvent();
      case 'sync_marker':
        return const _SyncMarkerEvent();
      default:
        return null;
    }
  }

  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env);

  static String requireString(
    RemoteRealtimeEnvelope env,
    String key, {
    String? eventType,
  }) {
    final value = env.payload[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException(
      '${eventType ?? env.type} event is missing authoritative $key',
    );
  }

  static int? optionalInt(RemoteRealtimeEnvelope env, String key) {
    final value = env.payload[key];
    return value is int ? value : null;
  }
}

class _MessageCreatedEvent extends _InboundSyncEvent {
  const _MessageCreatedEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    final messageId = env.payload['message_id'] as String? ?? env.eventId;
    final conversationId = _InboundSyncEvent.requireString(
      env,
      'conversation_id',
      eventType: 'chat_message',
    );

    if (db.isTombstoned(messageId, 'MESSAGE')) {
      return false;
    }

    final message = RemoteMessage(
      messageId: messageId,
      conversationId: conversationId,
      senderAccountId: env.payload['sender_account_id'] as String? ?? 'unknown',
      senderDeviceId: env.payload['sender_device_id'] as int? ?? 0,
      ciphertext: env.payload['ciphertext'] as String? ?? '',
    );

    db.saveMessage(
      message,
      env.serverSequence ?? 0,
      env.timestamp,
      'DELIVERED',
    );
    return true;
  }
}

class _MessageDeletedEvent extends _InboundSyncEvent {
  const _MessageDeletedEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    final messageId = _InboundSyncEvent.requireString(env, 'message_id');
    db.saveTombstone(messageId, 'MESSAGE');
    db.deleteMessage(messageId);
    return true;
  }
}

class _MessageEditedEvent extends _InboundSyncEvent {
  const _MessageEditedEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    final messageId = _InboundSyncEvent.requireString(env, 'message_id');
    db.saveMessageRevision(
      revisionId: env.eventId,
      messageId: messageId,
      type: 'EDIT',
      authorId:
          env.payload['author_id'] as String? ??
          env.payload['sender_account_id'] as String? ??
          'unknown',
      payload: jsonEncode({
        'ciphertext': _InboundSyncEvent.requireString(env, 'ciphertext'),
      }),
      timestamp: env.payload['timestamp'] as int? ?? env.timestamp,
    );
    return true;
  }
}

class _ReactionEvent extends _InboundSyncEvent {
  const _ReactionEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    final messageId = _InboundSyncEvent.requireString(env, 'message_id');
    db.saveMessageRevision(
      revisionId: env.eventId,
      messageId: messageId,
      type: env.type == 'reaction_removed' ? 'REACTION_REMOVED' : 'REACTION',
      authorId:
          env.payload['author_id'] as String? ??
          env.payload['account_id'] as String? ??
          'unknown',
      payload: jsonEncode({
        'reaction': _InboundSyncEvent.requireString(env, 'reaction'),
      }),
      timestamp: env.payload['timestamp'] as int? ?? env.timestamp,
    );
    return true;
  }
}

class _ReceiptEvent extends _InboundSyncEvent {
  const _ReceiptEvent(this.receiptType);

  final String receiptType;

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    db.saveMessageReceipt(
      receiptId: env.eventId,
      messageId: _InboundSyncEvent.requireString(env, 'message_id'),
      conversationId: _InboundSyncEvent.requireString(env, 'conversation_id'),
      accountId: _InboundSyncEvent.requireString(env, 'account_id'),
      deviceId: _InboundSyncEvent.optionalInt(env, 'device_id'),
      receiptType: receiptType,
      timestamp: env.payload['timestamp'] as int? ?? env.timestamp,
    );
    return true;
  }
}

class _ContactUpdatedEvent extends _InboundSyncEvent {
  const _ContactUpdatedEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    db.upsertContact(
      RemoteContact(
        peerAccountId: _InboundSyncEvent.requireString(env, 'peer_account_id'),
        nickname: env.payload['nickname'] as String? ?? '',
        status: env.payload['status'] as String? ?? 'Accepted',
      ),
    );
    return true;
  }
}

class _ContactRemovedEvent extends _InboundSyncEvent {
  const _ContactRemovedEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    db.deleteContact(_InboundSyncEvent.requireString(env, 'peer_account_id'));
    return true;
  }
}

class _ProfileUpdatedEvent extends _InboundSyncEvent {
  const _ProfileUpdatedEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    final accountId = _InboundSyncEvent.requireString(env, 'account_id');
    final existing = db.getAccount(accountId);
    if (existing == null) return false;
    db.upsertAccount(
      RemoteAccount(
        accountId: existing.accountId,
        username: env.payload['username'] as String? ?? existing.username,
        identityPublicKey: existing.identityPublicKey,
        createdAt: existing.createdAt,
        status: existing.status,
      ),
    );
    return true;
  }
}

class _MembershipChangedEvent extends _InboundSyncEvent {
  const _MembershipChangedEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    final conversationId = _InboundSyncEvent.requireString(
      env,
      'conversation_id',
    );
    final accountId = _InboundSyncEvent.requireString(env, 'account_id');
    final action = env.payload['action'] as String? ?? 'added';

    if (action == 'removed') {
      db.removeConversationMember(conversationId, accountId);
      return true;
    }

    db.upsertConversationMember(
      conversationId,
      accountId,
      role: env.payload['role'] as String? ?? 'MEMBER',
    );
    return true;
  }
}

class _ConversationCreatedEvent extends _InboundSyncEvent {
  const _ConversationCreatedEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    final conversationId = _InboundSyncEvent.requireString(
      env,
      'conversation_id',
    );
    final members = env.payload['member_ids'];

    db.upsertConversation(
      RemoteConversation(
        conversationId: conversationId,
        title: env.payload['title'] as String? ?? '',
        type: env.payload['conversation_type'] as String? ?? 'DIRECT',
        lastActivitySequence: env.serverSequence ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          env.payload['created_at'] as int? ?? env.timestamp,
        ),
      ),
      members is List ? members.whereType<String>().toList() : const [],
    );
    return true;
  }
}

class _TypingEvent extends _InboundSyncEvent {
  const _TypingEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) => false;
}

class _SyncMarkerEvent extends _InboundSyncEvent {
  const _SyncMarkerEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) => true;
}
