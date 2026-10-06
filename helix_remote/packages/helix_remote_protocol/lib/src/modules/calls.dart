import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/src/content/bodies.dart';
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

// ------------------------------------------------- the sealed signal itself

/// What a sealed call signal says. The server's [CallSignalKind] only sees
/// `offer`, `update` (everything but offer and end) and `end`.
enum CallSignalType implements WireEnum {
  /// The caller's session description; rings the callee's devices.
  offer('offer'),

  /// A callee device took the call: its session description.
  answer('answer'),

  /// Trickled ICE candidates, either direction.
  ice('ice'),

  /// A callee device is ringing (live only; the caller shows "ringing").
  ringing('ringing'),

  /// Hang-up, decline, busy, cancel: [CallSignalPayload.reason] says which.
  end('end'),
  unknown('unknown');

  const CallSignalType(this.wire);

  @override
  final String wire;

  /// The kind the server routes it as.
  CallSignalKind get routedAs => switch (this) {
    offer => CallSignalKind.offer,
    end => CallSignalKind.end,
    _ => CallSignalKind.update,
  };
}

/// Why a call ended, for [CallSignalType.end].
enum CallEndReason implements WireEnum {
  /// The other side hung up an answered call.
  hangup('hangup'),

  /// The callee declined.
  declined('declined'),

  /// The callee is in another call.
  busy('busy'),

  /// The caller gave up before an answer (or the offer timed out).
  cancelled('cancelled'),

  /// Another device of the callee took the call.
  answeredElsewhere('answered_elsewhere'),

  /// Media never connected or broke for good.
  failed('failed'),

  /// Both sides called each other at once and this call lost (the smaller
  /// call id wins on both ends).
  glare('glare'),
  unknown('unknown');

  const CallEndReason(this.wire);

  @override
  final String wire;
}

/// One ICE candidate, as the platform's WebRTC reports it.
final class IceCandidatePayload {
  const IceCandidatePayload({
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });

  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  JsonMap toJson() =>
      compact({'candidate': candidate, 'mid': sdpMid, 'index': sdpMLineIndex});

  factory IceCandidatePayload.fromJson(JsonReader json) {
    final candidate = json.nonEmpty('candidate');
    if (candidate.length > CallSignalPayload.maxCandidateLength) {
      throw ProtocolFormatException('too long', path: 'candidate');
    }
    return IceCandidatePayload(
      candidate: candidate,
      sdpMid: json.optString('mid'),
      sdpMLineIndex: json.optInt('index'),
    );
  }

  @override
  String toString() => 'IceCandidatePayload(redacted)';
}

/// The plaintext of a call signal: JSON, padded and sealed pairwise per
/// device (CRYPTO_V2.md §5-7) exactly like a content message, so the server
/// sees only the call id, the parties and the routed kind. SDP, ICE
/// candidates and the audio/video choice never reach it, and none of it is
/// ever stored locally either (`call_log` keeps the fact and the timings).
final class CallSignalPayload {
  const CallSignalPayload({
    required this.type,
    required this.callId,
    this.media,
    this.sdp,
    this.candidates = const [],
    this.reason,
    this.version = currentVersion,
  });

  static const currentVersion = 1;
  static const maxSdpLength = 32 * 1024;
  static const maxCandidateLength = 1024;
  static const maxCandidates = 32;

  final int version;
  final CallSignalType type;

  /// Repeats the id the server routes by; a signal whose inner id differs
  /// from the one it arrived under is dropped.
  final String callId;

  /// `offer` only.
  final CallMedia? media;

  /// `offer` and `answer`.
  final String? sdp;

  /// `ice`.
  final List<IceCandidatePayload> candidates;

  /// `end`.
  final CallEndReason? reason;

  JsonMap toJson() => compact({
    'v': version,
    'type': type.wire,
    'call_id': callId,
    'media': media?.wire,
    'sdp': sdp,
    'candidates': candidates.isEmpty
        ? null
        : [for (final c in candidates) c.toJson()],
    'reason': reason?.wire,
  });

  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  factory CallSignalPayload.decode(Uint8List bytes) =>
      CallSignalPayload.fromJson(JsonReader.decode(utf8.decode(bytes)));

  factory CallSignalPayload.fromJson(JsonReader json) {
    final sdp = json.optString('sdp');
    if (sdp != null && sdp.length > maxSdpLength) {
      throw ProtocolFormatException('too long', path: 'sdp');
    }
    final candidates = json.optObjects(
      'candidates',
      IceCandidatePayload.fromJson,
    );
    if (candidates.length > maxCandidates) {
      throw ProtocolFormatException('too many', path: 'candidates');
    }
    return CallSignalPayload(
      version: json.has('v') ? json.integer('v') : currentVersion,
      type: json.enumValue(
        'type',
        CallSignalType.values,
        orElse: CallSignalType.unknown,
      ),
      callId: json.nonEmpty('call_id'),
      media: json.optEnum('media', CallMedia.values),
      sdp: sdp,
      candidates: candidates,
      reason: json.optEnum(
        'reason',
        CallEndReason.values,
        orElse: CallEndReason.unknown,
      ),
    );
  }

  @override
  String toString() => 'CallSignalPayload(${type.wire}, redacted)';
}
