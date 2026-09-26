import 'package:helix_remote_domain/models.dart';

class RemoteRealtimeEnvelope {
  const RemoteRealtimeEnvelope({
    required this.eventId,
    this.requestId,
    this.idempotencyKey,
    this.correlationId,
    this.serverSequence,
    required this.schemaVersion,
    required this.timestamp,
    required this.type,
    required this.payload,
    this.isUnrecognized = false,
  });

  final String eventId;
  final String? requestId;
  final String? idempotencyKey;
  final String? correlationId;
  final int? serverSequence;
  final int schemaVersion;
  final int timestamp;
  final String type;
  final Map<String, dynamic> payload;

  /// Indicates if this event was not recognized by the current client version.
  /// Used for graceful degradation (P8-042).
  final bool isUnrecognized;

  Map<String, dynamic> toJson() => {
    'event_id': eventId,
    if (requestId != null) 'request_id': requestId,
    if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
    if (correlationId != null) 'correlation_id': correlationId,
    if (serverSequence != null) 'server_sequence': serverSequence,
    'schema_version': schemaVersion,
    'timestamp': timestamp,
    'type': type,
    'payload': payload,
  };

  factory RemoteRealtimeEnvelope.fromJson(Map<String, dynamic> json) {
    final eventId = json['event_id'] as String?;
    final schemaVersion = json['schema_version'] as int?;
    final timestamp = json['timestamp'] as int?;
    final type = json['type'] as String?;
    final payloadObj = json['payload'];

    if (eventId == null ||
        schemaVersion == null ||
        timestamp == null ||
        type == null) {
      throw const FormatException(
        'Missing required envelope fields: event_id, schema_version, timestamp, or type',
      );
    }

    final Map<String, dynamic> parsedPayload =
        payloadObj is Map<String, dynamic> ? payloadObj : <String, dynamic>{};

    // Supported types advertised through RemoteCapability.realtimeEnvelopeV1.
    //
    // This list is a gate, not documentation. A type missing from it is
    // flagged [isUnrecognized], and that flag makes the sync engine's
    // `tryParse` return null *before* it reaches the case written for that
    // type. The event then looks wired - there is a case for it in
    // `_changeFor` and in `tryParse` - but is dropped at runtime, with no
    // test failing, because the sync tests build envelopes directly and so
    // never pass through this gate. That is how the device-pairing prompt and
    // the group epoch key were both "handled" and unreachable.
    //
    // So: every type the backend puts on the wire belongs here, and when a
    // server-side event type is added, it gets added here in the same change.
    const supportedTypes = {
      // Messaging.
      'chat_message',
      'message_deleted',
      'message_edited',
      'reaction_added',
      'reaction_removed',
      'read_receipt',
      'delivery_receipt',
      'typing',
      // Conversations and contacts.
      'conversation_created',
      'membership_changed',
      'membership_changed_admin',
      'contact_updated',
      'contact_removed',
      'profile_updated',
      // Groups.
      'group_created',
      'group_invite',
      'group_deleted',
      'group_admin_event',
      'group_key_updated',
      'group_join_requested',
      'group_join_request_resolved',
      'group_add_policy_changed',
      'group_epoch_key',
      // Device lifecycle. The backend spells revocation one of two ways
      // depending on the code path (`devices.dart` and the accounts
      // repository), so both are listed and both are handled.
      'pending_device_link',
      'device_linked',
      'device_revoked',
      'DEVICE_REVOKED',
      // Group calls and scheduled calls.
      'scheduled_call_invite',
      'scheduled_call_cancelled',
      // Lifecycle.
      'sync_marker',

      // Types the server does not currently push, but which the client knows
      // how to apply and which a later server version may start sending.
      // Privacy and presence have REST endpoints today and are polled; if
      // either becomes a push, it is already handled rather than silently
      // dropped. `message_tombstoned` is the client-side name for a deletion
      // the server reports as `message_deleted`.
      'message_tombstoned',
      'privacy_updated',
      'presence_updated',
      'safety_notice',
    };

    // Room-level group-call frames (`participant_joined` and friends) are
    // deliberately absent, and are dispatched raw by the WebSocket client
    // rather than through the sync engine: they carry no `server_sequence`,
    // are never written to the offline event log, and describe state the
    // server owns. `RemoteGroupCallService.processRoomEvent` consumes them
    // directly, the same way `call_signal` is consumed by the signalling
    // gateway. Listing them here would imply the sync engine can replay them
    // after a reconnect, which it cannot.

    final capabilities = RemoteCapabilityRegistry.current();
    final isUnrecognized =
        !capabilities.supports(RemoteCapability.realtimeEnvelopeV1) ||
        !supportedTypes.contains(type) ||
        schemaVersion > 1;

    return RemoteRealtimeEnvelope(
      eventId: eventId,
      requestId: json['request_id'] as String?,
      idempotencyKey: json['idempotency_key'] as String?,
      correlationId: json['correlation_id'] as String?,
      serverSequence: json['server_sequence'] as int?,
      schemaVersion: schemaVersion,
      timestamp: timestamp,
      type: type,
      payload: parsedPayload,
      isUnrecognized: isUnrecognized,
    );
  }
}
