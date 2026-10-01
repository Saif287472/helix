import 'dart:typed_data';

import 'package:helix_remote_protocol/src/envelope.dart';
import 'package:helix_remote_protocol/src/json.dart';
import 'package:helix_remote_protocol/src/modules/messaging.dart';

/// `GET /v1/calls/turn`. Time-limited TURN REST credentials.
final class TurnCredentials {
  const TurnCredentials({
    required this.urls,
    required this.username,
    required this.credential,
    required this.expiresAt,
  });

  final List<String> urls;
  final String username;
  final String credential;
  final DateTime expiresAt;

  JsonMap toJson() => {
    'urls': urls,
    'username': username,
    'credential': credential,
    'expires_at': toWireTime(expiresAt),
  };

  factory TurnCredentials.fromJson(JsonReader json) => TurnCredentials(
    urls: json.strings('urls'),
    username: json.nonEmpty('username'),
    credential: json.nonEmpty('credential'),
    expiresAt: json.time('expires_at'),
  );

  @override
  String toString() => 'TurnCredentials(${urls.length} urls, redacted)';
}

/// The only thing the server knows about a call signal. SDP, ICE candidates,
/// caller name and audio/video choice are inside the sealed payloads
/// (v1 sent all of them in the clear).
enum CallSignalKind implements WireEnum {
  /// Starts a call: offline target devices get a pending call and a push.
  offer('offer'),

  /// Answer, ICE, renegotiation, ringing: delivered live only.
  update('update'),

  /// Hang-up, decline, busy, cancel: clears pending calls.
  end('end'),
  unknown('unknown');

  const CallSignalKind(this.wire);

  @override
  final String wire;
}

/// `POST /v1/calls/{call_id}/signals`.
final class CallSignalRequest {
  const CallSignalRequest({
    required this.kind,
    required this.recipients,
    this.ttl = const Duration(seconds: 60),
  });

  final CallSignalKind kind;

  /// Usually one account (the callee, all devices) plus the caller's own
  /// other devices for `end`.
  final List<Recipient> recipients;

  /// How long an [CallSignalKind.offer] stays pending (max 120 s).
  final Duration ttl;

  JsonMap toJson() => {
    'kind': kind.wire,
    'recipients': [for (final r in recipients) r.toJson()],
    'ttl_s': ttl.inSeconds,
  };

  factory CallSignalRequest.fromJson(JsonReader json) => CallSignalRequest(
    kind: json.enumValue(
      'kind',
      CallSignalKind.values,
      orElse: CallSignalKind.unknown,
    ),
    recipients: json.objects('recipients', Recipient.fromJson),
    ttl: Duration(seconds: json.optInt('ttl_s') ?? 60),
  );
}

final class CallSignalResponse {
  const CallSignalResponse({required this.delivered, required this.pending});

  /// Devices that were online and received it now.
  final List<String> delivered;

  /// Devices that were offline: the offer is pending and a push was sent.
  final List<String> pending;

  JsonMap toJson() => {'delivered': delivered, 'pending': pending};

  factory CallSignalResponse.fromJson(JsonReader json) => CallSignalResponse(
    delivered: json.strings('delivered'),
    pending: json.strings('pending'),
  );
}

enum CallState implements WireEnum {
  answered('answered'),
  declined('declined'),
  cancelled('cancelled'),
  ended('ended');

  const CallState(this.wire);

  @override
  final String wire;
}

/// `PUT /v1/calls/{call_id}/state`: tells the server to stop ringing other
/// devices of this account (answered or declined elsewhere) and to drop
/// pending offers.
final class CallStateRequest {
  const CallStateRequest({required this.state});

  final CallState state;

  JsonMap toJson() => {'state': state.wire};

  factory CallStateRequest.fromJson(JsonReader json) =>
      CallStateRequest(state: json.enumValue('state', CallState.values));
}

/// One entry of `GET /v1/calls/pending`.
final class PendingCall {
  const PendingCall({
    required this.callId,
    required this.from,
    required this.createdAt,
    required this.expiresAt,
    required this.payload,
  });

  final String callId;
  final EnvelopeSender from;
  final DateTime createdAt;
  final DateTime expiresAt;

  /// The sealed offer for this device.
  final Uint8List payload;

  JsonMap toJson() => {
    'call_id': callId,
    'from': from.toJson(),
    'created_at': toWireTime(createdAt),
    'expires_at': toWireTime(expiresAt),
    'payload': encodeBytes(payload),
  };

  factory PendingCall.fromJson(JsonReader json) => PendingCall(
    callId: json.nonEmpty('call_id'),
    from: EnvelopeSender.fromJson(json.object('from')),
    createdAt: json.time('created_at'),
    expiresAt: json.time('expires_at'),
    payload: json.bytes('payload'),
  );
}

final class PendingCallList {
  const PendingCallList({required this.calls});

  final List<PendingCall> calls;

  JsonMap toJson() => {
    'calls': [for (final c in calls) c.toJson()],
  };

  factory PendingCallList.fromJson(JsonReader json) =>
      PendingCallList(calls: json.objects('calls', PendingCall.fromJson));
}

/// `POST /v1/calls/metrics`: anonymous quality numbers, no participants.
final class CallMetricsRequest {
  const CallMetricsRequest({
    required this.callId,
    this.setupMs,
    this.durationS,
    this.reconnects,
    this.packetLossPercent,
    this.rttMs,
    this.relayed,
    this.outcome,
  });

  final String callId;
  final int? setupMs;
  final int? durationS;
  final int? reconnects;
  final double? packetLossPercent;
  final int? rttMs;
  final bool? relayed;
  final String? outcome;

  JsonMap toJson() => compact({
    'call_id': callId,
    'setup_ms': setupMs,
    'duration_s': durationS,
    'reconnects': reconnects,
    'packet_loss_pct': packetLossPercent,
    'rtt_ms': rttMs,
    'relayed': relayed,
    'outcome': outcome,
  });

  factory CallMetricsRequest.fromJson(JsonReader json) {
    final loss = json.raw('packet_loss_pct');
    return CallMetricsRequest(
      callId: json.nonEmpty('call_id'),
      setupMs: json.optInt('setup_ms'),
      durationS: json.optInt('duration_s'),
      reconnects: json.optInt('reconnects'),
      packetLossPercent: loss is num ? loss.toDouble() : null,
      rttMs: json.optInt('rtt_ms'),
      relayed: json.has('relayed') ? json.boolean('relayed') : null,
      outcome: json.optString('outcome'),
    );
  }
}
