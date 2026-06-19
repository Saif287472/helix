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
      throw FormatException(
        'Missing required envelope fields: event_id, schema_version, timestamp, or type',
      );
    }

    final Map<String, dynamic> parsedPayload =
        payloadObj is Map<String, dynamic> ? payloadObj : <String, dynamic>{};

    // Supported types as of Phase 8
    const supportedTypes = {
      'chat_message',
      'conversation_created',
      'message_deleted',
      'message_tombstoned',
      'read_receipt',
      'delivery_receipt',
      'membership_changed',
      'receipt',
      'typing',
      'group_membership',
      'call_signal',
      'device_revocation',
      'sync_marker',
    };

    final isUnrecognized = !supportedTypes.contains(type) || schemaVersion > 1;

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
