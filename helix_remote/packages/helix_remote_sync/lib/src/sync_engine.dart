import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:helix_remote_api/api/realtime_envelope.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';

enum RemoteSyncChangeArea {
  conversations,
  contacts,
  messages,
  groups,
  devices,
  outbox,
  runtime,
}

class RemoteSyncChange {
  const RemoteSyncChange({
    required this.areas,
    this.conversationId,
    this.messageId,
    this.contactAccountId,
    this.deviceId,
  });

  final Set<RemoteSyncChangeArea> areas;
  final String? conversationId;

  /// The affected message when a change is scoped to one message.
  ///
  /// Consumers can use this to update a rendered message in place rather
  /// than re-reading and decrypting the whole conversation window.
  final String? messageId;

  /// Present for contact/profile updates so presentation layers can refresh
  /// only the affected peer instead of rebuilding every open conversation.
  final String? contactAccountId;

  /// The affected device for device-lifecycle events. A presentation layer
  /// needs this to tell "a sibling device was revoked" (refresh the list)
  /// from "this device was revoked" (tear the session down).
  final String? deviceId;

  bool affects(RemoteSyncChangeArea area) => areas.contains(area);

  bool affectsConversation(String id) =>
      conversationId == null || conversationId == id;
}

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
  RemoteSyncEngine(
    this.db, {
    this.diagnostics,
    this.onCallSignal,
    this.onTrace,
    this.onLocalDeviceRevoked,
  });

  final HelixRemoteDatabase db;
  final void Function(String message)? diagnostics;

  /// Called when a `call_signal` event arrives on the inbound stream.
  /// The payload map is forwarded as-is; no DB write is performed because
  /// call signals are ephemeral and must not persist media or content.
  final void Function(Map<String, dynamic> payload)? onCallSignal;

  /// Latency tracing hook. Called with (messageId, stageName) at key pipeline
  /// points. The app layer injects a closure that routes to MessageLatencyRegistry
  /// without creating a package dependency on the app.
  final void Function(String messageId, String stage)? onTrace;

  /// Called when the server reports that **the device this client is running
  /// on** has been revoked - by the user from another device, by an operator,
  /// or after a lost-device sweep.
  ///
  /// This is deliberately a hard callback rather than a row update: the local
  /// device's credentials are now dead server-side, and the only correct
  /// response is to drop the session and send the user back through pairing.
  /// The app layer injects that teardown.
  final void Function(String deviceId, String reason)? onLocalDeviceRevoked;

  static const String _globalSyncCursorId = '__remote_global_stream__';
  final _changeController = StreamController<RemoteSyncChange>.broadcast(
    sync: true,
  );
  Future<int>? _outboundDrain;
  // Set to true while a drain is running whenever processOutboundQueue is
  // called again, so the loop re-checks after the current pass rather than
  // exiting and missing the newly enqueued operation.
  bool _outboundDirty = false;
  final _outOfOrderBuffer = <int, RemoteRealtimeEnvelope>{};

  /// The highest inbound sequence number successfully applied via HTTP or WebSocket.
  /// Pass this to the WebSocket connection so the server only replays new events.
  int get inboundSequence => db.getSyncCursor(_globalSyncCursorId);

  Stream<RemoteSyncChange> get changes => _changeController.stream;

  /// Synchronises incoming events from the server since the last stored cursor.
  ///
  /// P4-04: Events that fail parsing or application are quarantined rather than
  /// blocking subsequent events or poisoning the cursor. The cursor advances
  /// past quarantined sequences so they are not replayed on the next fetch.
  Future<int> syncInbound(SyncGateway gateway) async {
    final lastSeq = db.getSyncCursor(_globalSyncCursorId);
    final envelopes = await gateway.fetchInboundEvents(sinceSequence: lastSeq);

    final sortedEnvelopes = List<RemoteRealtimeEnvelope>.from(
      envelopes,
    )..sort((a, b) => (a.serverSequence ?? 0).compareTo(b.serverSequence ?? 0));

    int appliedCount = 0;
    int highestSeq = lastSeq;
    var expectedSeq = lastSeq + 1;
    final appliedChanges = <RemoteSyncChange>[];

    db.rawExecute('BEGIN TRANSACTION;');
    try {
      for (final env in sortedEnvelopes) {
        final seq = env.serverSequence ?? 0;
        if (db.hasProcessedEventId(env.eventId) ||
            db.isQuarantinedEventId(env.eventId)) {
          continue;
        }

        if (seq <= lastSeq) {
          throw StateError(
            'Remote sync sequence regression for unseen event type=${env.type}',
          );
        }
        if (seq > expectedSeq) {
          // Sequence gap encountered in batch: record diagnostic, advance expectedSeq
          // to continue processing valid remaining events rather than stalling indefinitely.
          diagnostics?.call(
            'Remote sync sequence gap in batch: expected $expectedSeq, jumped to $seq',
          );
          expectedSeq = seq;
        }

        // Call signals are ephemeral: deliver via callback, never write to DB.
        if (env.type == 'call_signal' && onCallSignal != null) {
          onCallSignal!(env.payload);
        }

        // P4-04: attempt to parse and apply; on any failure, quarantine this
        // event, advance cursor past it, and continue with subsequent events.
        try {
          final event = _InboundSyncEvent.tryParse(env);
          if (event == null) {
            _recordUnknownEvent(env);
            _recordProcessedEvent(env, seq);
            highestSeq = seq;
            expectedSeq = seq + 1;
            continue;
          }

          if (event is _SyncMarkerEvent) {
            _recordProcessedEvent(env, seq);
            highestSeq = seq;
            expectedSeq = seq + 1;
            appliedCount++;
            continue;
          }

          final applied = event.apply(db, env);
          _recordProcessedEvent(env, seq);
          highestSeq = seq;
          expectedSeq = seq + 1;
          if (applied) {
            appliedCount++;
            appliedChanges.add(_changeFor(env));
          }
        } catch (e) {
          // P4-04: quarantine the malformed event; advance cursor so it does
          // not block future syncs. The quarantine table is inspectable by
          // operators and does not surface user-visible content.
          _quarantineEvent(env, seq, e.toString());
          _recordProcessedEvent(env, seq);
          highestSeq = seq;
          expectedSeq = seq + 1;
          diagnostics?.call(
            'Remote sync event quarantined '
            'type=${_redactDiagnosticField(env.type)} '
            'sequence=$seq '
            'reason=${_redactDiagnosticField(e.toString())}',
          );
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

    for (final change in appliedChanges) {
      _emitChange(change);
    }

    return appliedCount;
  }

  /// Handles a single incoming envelope from WebSocket push.
  /// Returns true if the event was applied, false if already processed or unknown.
  /// P4-04: malformed events are quarantined and do not advance the cursor.
  bool handleIncomingEnvelope(RemoteRealtimeEnvelope env) {
    final seq = env.serverSequence ?? 0;
    final lastSeq = db.getSyncCursor(_globalSyncCursorId);

    if (db.hasProcessedEventId(env.eventId) ||
        db.isQuarantinedEventId(env.eventId)) {
      return false;
    }

    if (seq <= lastSeq) {
      return false;
    }
    if (seq != lastSeq + 1) {
      diagnostics?.call(
        'Remote realtime sequence gap: expected ${lastSeq + 1} '
        'but received $seq',
      );
      _outOfOrderBuffer[seq] = env;
      if (_outOfOrderBuffer.length > 200) {
        final lowest = _outOfOrderBuffer.keys.reduce((a, b) => a < b ? a : b);
        _outOfOrderBuffer.remove(lowest);
      }
      return false;
    }

    try {
      if (env.type == 'call_signal' && onCallSignal != null) {
        onCallSignal!(env.payload);
        _recordProcessedEvent(env, seq);
        if (seq > lastSeq) {
          db.updateSyncCursor(_globalSyncCursorId, seq);
        }
        _drainBufferedEnvelopes(seq);
        return true;
      }

      final event = _InboundSyncEvent.tryParse(env);
      if (event == null) {
        _recordUnknownEvent(env);
        _recordProcessedEvent(env, seq);
        if (seq > lastSeq) {
          db.updateSyncCursor(_globalSyncCursorId, seq);
        }
        _drainBufferedEnvelopes(seq);
        return false;
      }

      if (event is _SyncMarkerEvent) {
        _recordProcessedEvent(env, seq);
        if (seq > lastSeq) {
          db.updateSyncCursor(_globalSyncCursorId, seq);
        }
        _drainBufferedEnvelopes(seq);
        return true;
      }

      final applied = event.apply(db, env);
      _recordProcessedEvent(env, seq);
      if (seq > lastSeq) {
        db.updateSyncCursor(_globalSyncCursorId, seq);
      }
      if (applied) {
        if (env.type == 'chat_message') {
          final traceMsgId = env.payload['message_id'] as String?;
          if (traceMsgId != null) {
            onTrace?.call(traceMsgId, 'receiver_db_save');
          }
        }
        _maybeNotifyLocalDeviceRevoked(env);
        _emitChange(_changeFor(env));
        if (env.type == 'chat_message') {
          final traceMsgId = env.payload['message_id'] as String?;
          if (traceMsgId != null) {
            onTrace?.call(traceMsgId, 'state_update');
          }
        }
      }
      _drainBufferedEnvelopes(seq);
      return applied;
    } catch (e) {
      // P4-04: quarantine the envelope; advance cursor past it to avoid
      // permanently blocking realtime delivery.
      _quarantineEvent(env, seq, e.toString());
      _recordProcessedEvent(env, seq);
      if (seq > lastSeq) {
        db.updateSyncCursor(_globalSyncCursorId, seq);
      }
      diagnostics?.call(
        'Remote realtime event quarantined '
        'type=${_redactDiagnosticField(env.type)} '
        'sequence=$seq',
      );
      return false;
    }
  }

  void _drainBufferedEnvelopes(int seq) {
    if (_outOfOrderBuffer.isEmpty) return;
    var nextExpected = seq + 1;
    while (_outOfOrderBuffer.containsKey(nextExpected)) {
      final bufferedEnv = _outOfOrderBuffer.remove(nextExpected)!;
      handleIncomingEnvelope(bufferedEnv);
      nextExpected++;
    }
  }

  void _quarantineEvent(
    RemoteRealtimeEnvelope env,
    int seq,
    String failureReason,
  ) {
    try {
      db.saveQuarantinedEvent(
        eventId: env.eventId,
        serverSequence: seq,
        eventType: env.type,
        rawPayload: jsonEncode(env.payload),
        failureReason: failureReason.length > 512
            ? '${failureReason.substring(0, 512)}…'
            : failureReason,
      );
    } catch (_) {
      // Quarantine write failures are best-effort; the processed-event record
      // still prevents replay.
    }
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
  ///
  /// Loops until no due operations remain so that messages enqueued while a
  /// send is in-flight (e.g. concurrent X3DH completions) are picked up in
  /// the same drain cycle rather than waiting for the next trigger.
  Future<int> processOutboundQueue(SyncGateway gateway) async {
    final existingDrain = _outboundDrain;
    if (existingDrain != null) {
      // Signal the active drain to run at least one more pass after its
      // current getPendingOperations() call returns, so this new op is
      // not missed between the final empty-check and the drain teardown.
      _outboundDirty = true;
      return existingDrain;
    }
    _outboundDirty = false;
    final drain = _drainUntilEmpty(gateway);
    _outboundDrain = drain;
    try {
      return await drain;
    } finally {
      if (identical(_outboundDrain, drain)) {
        _outboundDrain = null;
      }
    }
  }

  Future<int> _drainUntilEmpty(SyncGateway gateway) async {
    int total = 0;
    int count;
    do {
      // Clear the dirty flag before each pass so any enqueue that races the
      // getPendingOperations() call sets it again and triggers another pass.
      _outboundDirty = false;
      count = await _processOutboundQueueOnce(gateway);
      total += count;
    } while (count > 0 || _outboundDirty);
    return total;
  }

  // Send up to this many outbound operations concurrently. Raising this reduces
  // burst latency (N msgs take ≈ ceil(N/limit) × RTT instead of N × RTT) at the
  // cost of more simultaneous connections to the server.
  static const int _maxConcurrentSends = 4;

  Future<int> _processOutboundQueueOnce(SyncGateway gateway) async {
    final pendingOps = db.getPendingOperations();
    if (pendingOps.isEmpty) return 0;

    // Dispatch in batches of _maxConcurrentSends so that operations within
    // each batch race in parallel, while batches themselves are ordered.
    // This keeps burst latency at ceil(N/4)×RTT instead of N×RTT.
    int processedCount = 0;
    for (var i = 0; i < pendingOps.length; i += _maxConcurrentSends) {
      final end = math.min(i + _maxConcurrentSends, pendingOps.length);
      final batch = pendingOps.sublist(i, end);
      final results = await Future.wait(
        batch.map((op) => _sendOneOperation(gateway, op)),
      );
      processedCount += results.fold<int>(0, (s, ok) => s + (ok ? 1 : 0));
    }
    return processedCount;
  }

  Future<bool> _sendOneOperation(
    SyncGateway gateway,
    Map<String, dynamic> op,
  ) async {
    final opId = op['op_id'] as String;
    final type = op['type'] as String;
    final payloadStr = op['payload'] as String;
    final retries = op['retries'] as int;
    final createdAt = op['created_at'] as int? ?? 0;

    try {
      final payload = jsonDecode(payloadStr) as Map<String, dynamic>;

      final traceMsgId = type == 'SEND_MESSAGE'
          ? payload['message_id'] as String?
          : null;
      if (traceMsgId != null) onTrace?.call(traceMsgId, 'send_attempt');

      await gateway.sendOutboundOperation(
        opId: opId,
        type: type,
        payload: payload,
      );

      if (traceMsgId != null) onTrace?.call(traceMsgId, 'server_ack');

      db.updateOperationStatus(opId, 'COMPLETED', retries);
      if (type == 'SEND_MESSAGE') {
        final messageId = payload['message_id'] as String?;
        final convId = payload['conversation_id'] as String?;
        if (messageId != null) db.updateMessageStatus(messageId, 'SENT');
        _emitChange(
          RemoteSyncChange(
            areas: const {
              RemoteSyncChangeArea.messages,
              RemoteSyncChangeArea.conversations,
              RemoteSyncChangeArea.outbox,
            },
            conversationId: convId,
            messageId: messageId,
          ),
        );
      } else {
        _emitChange(
          const RemoteSyncChange(areas: {RemoteSyncChangeArea.outbox}),
        );
      }

      final ageMs = DateTime.now().millisecondsSinceEpoch - createdAt;
      diagnostics?.call(
        'Remote outbound op completed type=$type age=${ageMs}ms',
      );
      return true;
    } catch (e) {
      final nextRetries = retries + 1;
      final permanent = _isPermanentOutboundFailure(e);
      final nextStatus = permanent || nextRetries >= 5 ? 'FAILED' : 'PENDING';
      db.updateOperationStatus(opId, nextStatus, nextRetries);
      _emitChange(const RemoteSyncChange(areas: {RemoteSyncChangeArea.outbox}));
      if (!permanent && nextRetries < 5) {
        final backoffMs = 1000 * (1 << nextRetries);
        final jitterMs = math.Random().nextInt(500);
        final nextAttempt =
            DateTime.now().millisecondsSinceEpoch + backoffMs + jitterMs;
        db.scheduleNextOperationAttempt(opId, nextAttempt);
      }
      return false;
    }
  }

  bool _isPermanentOutboundFailure(Object error) => error is StateError;

  RemoteSyncChange _changeFor(RemoteRealtimeEnvelope env) {
    switch (env.type) {
      case 'chat_message':
      case 'message_deleted':
      case 'message_tombstoned':
      case 'message_edited':
      case 'reaction_added':
      case 'reaction_removed':
      case 'read_receipt':
      case 'delivery_receipt':
        return RemoteSyncChange(
          areas: const {
            RemoteSyncChangeArea.messages,
            RemoteSyncChangeArea.conversations,
          },
          conversationId: env.payload['conversation_id'] as String?,
          messageId: env.payload['message_id'] as String?,
        );
      case 'conversation_created':
      case 'membership_changed':
        return RemoteSyncChange(
          areas: const {RemoteSyncChangeArea.conversations},
          conversationId: env.payload['conversation_id'] as String?,
        );
      case 'contact_updated':
      case 'contact_removed':
      case 'profile_updated':
      case 'privacy_updated':
      case 'presence_updated':
      case 'safety_notice':
        return RemoteSyncChange(
          areas: const {RemoteSyncChangeArea.contacts},
          contactAccountId:
              env.payload['peer_account_id'] as String? ??
              env.payload['account_id'] as String?,
        );
      case 'group_created':
      case 'group_invite':
      case 'group_deleted':
      case 'group_admin_event':
      case 'group_key_updated':
      case 'group_join_requested':
        return RemoteSyncChange(
          areas: const {
            RemoteSyncChangeArea.groups,
            RemoteSyncChangeArea.conversations,
          },
          conversationId:
              (env.payload['group_id'] ?? env.payload['conversation_id'])
                  as String?,
        );
      // Device lifecycle. These were emitted by the server all along and
      // matched no case here, so they fell through to `default` and were
      // dropped - which is why a new-device pairing request never appeared
      // and a revoked device kept a live session. `_changeFor` also never
      // returned `RemoteSyncChangeArea.devices`, so no listener could fire.
      case 'pending_device_link':
      case 'device_linked':
      case 'device_revoked':
      case 'DEVICE_REVOKED':
        return RemoteSyncChange(
          areas: const {
            RemoteSyncChangeArea.devices,
            RemoteSyncChangeArea.runtime,
          },
          deviceId: env.payload['device_id'] as String?,
        );
      case 'sync_marker':
        return const RemoteSyncChange(areas: {RemoteSyncChangeArea.runtime});
      default:
        return const RemoteSyncChange(areas: {RemoteSyncChangeArea.runtime});
    }
  }

  void _emitChange(RemoteSyncChange change) {
    if (!_changeController.isClosed) {
      _changeController.add(change);
    }
  }

  /// Fires [onLocalDeviceRevoked] when a revocation event names the device
  /// this client is running on.
  ///
  /// The relay scopes the event to our own account but does not say *which*
  /// of our devices it names, so the comparison has to happen here against
  /// the locally stored device id. Getting this wrong in the optimistic
  /// direction would sign the user out of a session that is still perfectly
  /// valid, so an unknown local device id is treated as "not me".
  void _maybeNotifyLocalDeviceRevoked(RemoteRealtimeEnvelope env) {
    if (onLocalDeviceRevoked == null) return;
    if (env.type != 'device_revoked' && env.type != 'DEVICE_REVOKED') return;

    final revokedId = env.payload['device_id'] as String?;
    if (revokedId == null || revokedId.isEmpty) return;

    final localDeviceId = db.getLocalDeviceId();
    if (localDeviceId == null || localDeviceId != revokedId) return;

    onLocalDeviceRevoked!(
      revokedId,
      env.payload['reason'] as String? ?? 'DEVICE_REVOKED',
    );
  }

  Future<void> dispose() async {
    await _changeController.close();
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
        return const _SyncMarkerEvent();
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
      case 'call_signal':
        return const _CallSignalEvent();
      case 'group_created':
        return const _GroupCreatedEvent();
      case 'group_invite':
        return const _GroupInviteEvent();
      case 'group_deleted':
        return const _GroupDeletedEvent();
      case 'group_admin_event':
        return const _GroupAdminEvent();
      case 'group_join_requested':
        return const _GroupJoinRequestedEvent();
      case 'group_key_updated':
        // Marker only: actual key material is distributed at the app layer.
        return const _SyncMarkerEvent();
      case 'pending_device_link':
        return const _PendingDeviceLinkEvent();
      case 'device_linked':
        return const _DeviceLinkedEvent();
      case 'device_revoked':
      case 'DEVICE_REVOKED':
        return const _DeviceRevokedEvent();
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

  static String? optionalString(RemoteRealtimeEnvelope env, String key) {
    final value = env.payload[key];
    return value is String && value.isNotEmpty ? value : null;
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
      senderDeviceId:
          env.payload['sender_device_id'] as String? ?? 'unknown_device',
      ciphertext: env.payload['ciphertext'] as String? ?? '',
    );

    // Guarantee the conversation row exists before writing the message so the
    // FK constraint is satisfied even when conversation_created arrives late.
    db.ensureConversationExists(
      conversationId: conversationId,
      senderAccountId: message.senderAccountId,
      serverSequence: env.serverSequence ?? 0,
      timestamp: env.timestamp,
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
    // P4-05: persist server_sequence so conflict resolution (sort) prefers
    // server ordering over wall-clock when two edits race.
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
      serverSequence: env.serverSequence ?? 0,
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
      serverSequence: env.serverSequence ?? 0,
    );
    return true;
  }
}

class _ReceiptEvent extends _InboundSyncEvent {
  const _ReceiptEvent(this.receiptType);

  final String receiptType;

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    final messageId = _InboundSyncEvent.requireString(env, 'message_id');
    db.saveMessageReceipt(
      receiptId: env.eventId,
      messageId: messageId,
      conversationId: _InboundSyncEvent.requireString(env, 'conversation_id'),
      accountId: _InboundSyncEvent.requireString(env, 'account_id'),
      deviceId: _InboundSyncEvent.optionalString(env, 'device_id'),
      receiptType: receiptType,
      timestamp: env.payload['timestamp'] as int? ?? env.timestamp,
    );
    // Upgrade the message status on the sender's side so the UI reflects
    // delivery and read state without requiring a full re-fetch.
    db.updateMessageStatus(
      messageId,
      receiptType == 'READ' ? 'READ' : 'DELIVERED',
    );
    return true;
  }
}

class _ContactUpdatedEvent extends _InboundSyncEvent {
  const _ContactUpdatedEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    final peerAccountId = _InboundSyncEvent.requireString(
      env,
      'peer_account_id',
    );
    final status = env.payload['status'] as String? ?? 'Accepted';
    // Prefer the peer's real display name over any caller-assigned nickname.
    final nickname =
        env.payload['peer_display_name'] as String? ??
        env.payload['nickname'] as String? ??
        '';
    // Only update nickname if the contact doesn't already have one stored.
    final existing = db.getContacts().cast<RemoteContact?>().firstWhere(
      (c) => c?.peerAccountId == peerAccountId,
      orElse: () => null,
    );
    final effectiveNickname = (existing?.nickname.isNotEmpty ?? false)
        ? existing!.nickname
        : nickname;
    db.upsertContact(
      RemoteContact(
        peerAccountId: peerAccountId,
        nickname: effectiveNickname,
        status: status,
      ),
    );
    final requestId = env.payload['request_id'] as String?;
    if (requestId != null) {
      db.upsertContactRequest(
        RemoteContactRequest(
          requestId: requestId,
          peerAccountId: peerAccountId,
          direction: env.payload['direction'] as String? ?? 'received',
          status: status == 'Accepted' ? 'Accepted' : 'Pending',
          updatedAt: env.payload['updated_at'] as int? ?? env.timestamp,
          nickname: effectiveNickname,
        ),
      );
    }
    return true;
  }
}

class _ContactRemovedEvent extends _InboundSyncEvent {
  const _ContactRemovedEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    final peerAccountId = _InboundSyncEvent.requireString(
      env,
      'peer_account_id',
    );
    db.deleteContact(peerAccountId);
    final requestId = env.payload['request_id'] as String?;
    if (requestId != null) {
      db.updateContactRequestStatus(
        requestId,
        env.payload['status'] as String? ?? 'Cancelled',
        env.payload['updated_at'] as int? ?? env.timestamp,
      );
    }
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
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (env.timestamp < now - 15000) {
      return false;
    }
    return true;
  }
}

class _SyncMarkerEvent extends _InboundSyncEvent {
  const _SyncMarkerEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) => true;
}

/// A user asked to join a group through a link that requires approval.
///
/// The server relays this to the group's admins and persists the request
/// server-side, but the client dropped the event, so `getPendingJoinRequests`
/// was always empty and the "Join Requests" section could never render -
/// there was no path for an admin to approve a request from the app.
class _GroupJoinRequestedEvent extends _InboundSyncEvent {
  const _GroupJoinRequestedEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    final groupId = _InboundSyncEvent.requireString(
      env,
      'group_id',
      eventType: 'group_join_requested',
    );
    final requestId = _InboundSyncEvent.requireString(
      env,
      'request_id',
      eventType: 'group_join_requested',
    );
    final requesterId = _InboundSyncEvent.requireString(
      env,
      'requester_id',
      eventType: 'group_join_requested',
    );

    db.upsertGroupJoinRequest(
      requestId: requestId,
      groupId: groupId,
      requesterId: requesterId,
      // The relay does not include the link id. Recording '' is the
      // repository's own "unknown link" representation; the row is keyed by
      // request_id, so nothing downstream depends on it.
      linkId: env.payload['link_id'] as String? ?? '',
      status: 'PENDING',
    );
    return true;
  }
}

/// A new device asked to pair with this account.
///
/// The server pushes this to the account's existing devices. It was dropped
/// before, which is why the only way to add a device was to hand-type the
/// Link ID and the 6-digit code. This records the request so the device
/// screen can list it; the code itself never leaves the new device.
class _PendingDeviceLinkEvent extends _InboundSyncEvent {
  const _PendingDeviceLinkEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    final linkId = _InboundSyncEvent.requireString(
      env,
      'link_id',
      eventType: 'pending_device_link',
    );
    final deviceId = _InboundSyncEvent.requireString(
      env,
      'device_id',
      eventType: 'pending_device_link',
    );
    final createdAt = env.payload['timestamp'] as int? ?? env.timestamp;

    // Only store a request the server still considers live; a replayed or
    // late-arriving frame must not put an expired prompt back on screen.
    final expiresAt = env.payload['expires_at'] as int? ?? 0;
    if (expiresAt > 0 && expiresAt <= createdAt) return true;

    db.upsertPendingDeviceLink(
      linkId: linkId,
      deviceId: deviceId,
      deviceName: env.payload['device_name'] as String? ?? 'New device',
      expiresAt: expiresAt,
      createdAt: createdAt,
    );
    return true;
  }
}

/// A pending pairing request completed: the new device is now a full device.
///
/// The event carries no key material, only the device id and name, so this
/// deliberately does *not* synthesize a `devices` row - the local schema
/// requires both public keys, and inventing them would put a half-real device
/// in the user's list. The accompanying `RemoteSyncChangeArea.devices` makes
/// the device screen re-fetch through the API, which returns the real keys.
class _DeviceLinkedEvent extends _InboundSyncEvent {
  const _DeviceLinkedEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    // A link that has now completed is no longer pending.
    final linkId = _InboundSyncEvent.optionalString(env, 'link_id');
    if (linkId != null) {
      db.markPendingDeviceLinkResolved(linkId, status: 'COMPLETED');
    } else {
      // The completion frame omits link_id, so clear out any request that
      // named this device - that is the request this event is about.
      final deviceId = _InboundSyncEvent.optionalString(env, 'device_id');
      if (deviceId != null) {
        db.markPendingDeviceLinksForDeviceCompleted(deviceId);
      }
    }
    return true;
  }
}

/// A device was revoked, here or on another device of the same account.
///
/// The local row is marked revoked so the device list reflects reality, and
/// the engine's `onLocalDeviceRevoked` hook fires when the revoked device is
/// the one this client is running on.
class _DeviceRevokedEvent extends _InboundSyncEvent {
  const _DeviceRevokedEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    final deviceId = _InboundSyncEvent.requireString(
      env,
      'device_id',
      eventType: 'device_revoked',
    );
    db.markDeviceRevokedByDeviceId(deviceId);
    return true;
  }
}

// Ephemeral — payload delivered via RemoteSyncEngine.onCallSignal callback.
// No DB write; call media and content must never be persisted server-side.
class _CallSignalEvent extends _InboundSyncEvent {
  const _CallSignalEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) => false;
}

// P16-001: Server confirms a new group was created; store conversation + metadata.
class _GroupCreatedEvent extends _InboundSyncEvent {
  const _GroupCreatedEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    final groupId = _InboundSyncEvent.requireString(env, 'group_id');
    final name = env.payload['name'] as String? ?? '';
    final creatorId = env.payload['creator_id'] as String? ?? '';
    final members = env.payload['member_ids'];

    db.upsertConversation(
      RemoteConversation(
        conversationId: groupId,
        title: name,
        type: 'GROUP',
        lastActivitySequence: env.serverSequence ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          env.payload['created_at'] as int? ?? env.timestamp,
        ),
      ),
      members is List ? members.whereType<String>().toList() : const [],
    );

    db.upsertGroupMetadata(
      groupId: groupId,
      name: name,
      creatorId: creatorId,
      epoch: 0,
    );

    return true;
  }
}

// P16-003: Server relays a group invite to the invitee's device(s).
class _GroupInviteEvent extends _InboundSyncEvent {
  const _GroupInviteEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    final inviteId = _InboundSyncEvent.requireString(env, 'invite_id');
    final groupId = _InboundSyncEvent.requireString(env, 'group_id');
    final inviterId = env.payload['inviter_id'] as String? ?? '';

    db.upsertGroupInvite(
      inviteId: inviteId,
      groupId: groupId,
      inviterId: inviterId,
      status: 'PENDING',
      createdAt: env.payload['created_at'] as int? ?? env.timestamp,
    );

    return true;
  }
}

// P16-010: Group has been deleted by an admin; tombstone and remove local state.
class _GroupDeletedEvent extends _InboundSyncEvent {
  const _GroupDeletedEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    final groupId = _InboundSyncEvent.requireString(env, 'group_id');
    db.saveTombstone(groupId, 'GROUP');
    return true;
  }
}

// P16-008: Admin renamed the group or updated avatar — update local metadata.
class _GroupAdminEvent extends _InboundSyncEvent {
  const _GroupAdminEvent();

  @override
  bool apply(HelixRemoteDatabase db, RemoteRealtimeEnvelope env) {
    final groupId = _InboundSyncEvent.requireString(env, 'group_id');
    final newName = env.payload['name'] as String?;
    if (newName != null) {
      final existing = db.getGroupMetadata(groupId);
      if (existing != null) {
        db.upsertGroupMetadata(
          groupId: groupId,
          name: newName,
          creatorId: existing['creator_id'] as String,
          avatarUri: existing['avatar_uri'] as String?,
          epoch: existing['epoch'] as int,
        );
      }
    }
    return true;
  }
}
