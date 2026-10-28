import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/src/content/bodies.dart';
import 'package:helix_remote_protocol/src/envelope.dart';
import 'package:helix_remote_protocol/src/ids.dart';
import 'package:helix_remote_protocol/src/json.dart';
import 'package:helix_remote_protocol/src/modules/messaging.dart';

/// What a call carries, and which pool of call time it spends (ADR-036). A
/// voice call spends voice minutes on the voice relay, whose bandwidth is
/// capped at voice quality; a video call (and a shared screen) spends video
/// minutes.
enum CallPool implements WireEnum {
  voice('voice'),
  video('video'),
  unknown('unknown');

  const CallPool(this.wire);

  @override
  final String wire;
}

/// Which end of a call asks for relay credentials.
enum CallRole implements WireEnum {
  /// The person who starts the call, or in a group call the one who joins and
  /// offers to the others. The starter's call time pays.
  caller('caller'),

  /// The person who answers.
  callee('callee'),
  unknown('unknown');

  const CallRole(this.wire);

  @override
  final String wire;
}

/// `POST /v1/calls/turn`: relay credentials for one call (ADR-036). A device
/// gets credentials only for a call, so no one can use the relay without one.
final class TurnRequest {
  const TurnRequest({
    required this.callId,
    required this.role,
    required this.media,
    this.roomId,
    this.groupId,
  });

  final String callId;
  final CallRole role;
  final CallPool media;

  /// A group call's room: the legs of one room share one reservation, paid by
  /// whoever made it first. A client-made random id that only the people in
  /// the room know (it travels in the sealed call signal).
  final String? roomId;

  /// The group a [roomId] belongs to. Required with a room: the server lets
  /// only a member of that group start or join the room's call time, and a
  /// room is bound to its group, so a room id alone opens nothing.
  final String? groupId;

  /// A call id and a room id are 8 to 128 characters of `A-Za-z0-9._:-`.
  static final RegExp idPattern = RegExp(r'^[A-Za-z0-9._:-]{8,128}$');

  JsonMap toJson() => compact({
    'call_id': callId,
    'role': role.wire,
    'media': media.wire,
    'room_id': roomId,
    'group_id': groupId,
  });

  factory TurnRequest.fromJson(JsonReader json) {
    final callId = json.nonEmpty('call_id', maxLength: 128);
    final roomId = json.optString('room_id', maxLength: 128);
    final groupId = json.optString('group_id', maxLength: 36);
    if (!idPattern.hasMatch(callId) ||
        (roomId != null && !idPattern.hasMatch(roomId))) {
      throw ProtocolFormatException(
        'a call or room id is 8 to 128 letters, digits and . _ : -',
      );
    }
    if ((roomId == null) != (groupId == null) ||
        (groupId != null && !Uuid.isValid(groupId))) {
      throw ProtocolFormatException(
        'a room needs the group it belongs to, and only a room does',
      );
    }
    return TurnRequest(
      callId: callId,
      role: json.enumValue('role', CallRole.values, orElse: CallRole.unknown),
      media: json.enumValue('media', CallPool.values, orElse: CallPool.unknown),
      roomId: roomId,
      groupId: groupId,
    );
  }
}

/// `POST /v1/calls/turn`. Time-limited TURN REST credentials for one call.
final class TurnCredentials {
  const TurnCredentials({
    required this.urls,
    required this.username,
    required this.credential,
    required this.expiresAt,
    this.metered = false,
  });

  final List<String> urls;
  final String username;
  final String credential;

  /// When the relay stops carrying this call. For a [metered] call this is the
  /// end of the call time reserved for it: the call ends then, so the apps warn
  /// shortly before.
  final DateTime expiresAt;

  /// The call spends call time (the starter is on the Free plan).
  final bool metered;

  JsonMap toJson() => {
    'urls': urls,
    'username': username,
    'credential': credential,
    'expires_at': toWireTime(expiresAt),
    if (metered) 'metered': true,
  };

  factory TurnCredentials.fromJson(JsonReader json) => TurnCredentials(
    urls: json.strings('urls'),
    username: json.nonEmpty('username'),
    credential: json.nonEmpty('credential'),
    expiresAt: json.time('expires_at'),
    metered: json.flag('metered'),
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

  /// What this side's video now is, mid-call (live only): [CallSignalPayload.screen]
  /// says whether it is a shared screen rather than the camera. Peers that do
  /// not know it decode it as [unknown] and ignore it.
  media('media'),

  /// Mid-call, between voice and video (ADR-036): one side asks the other to
  /// change the call to [CallSignalPayload.media]. Live only; a peer that does
  /// not know it ignores it, and the ask times out.
  switchAsk('switch_ask'),

  /// The callee agrees to a switch the caller asked for. The caller then
  /// makes the new media connection.
  switchAccept('switch_accept'),

  /// The other side declines a switch, or the caller could not make it
  /// (no call time left).
  switchDecline('switch_decline'),

  /// The caller's session description for the new media connection of a
  /// switch ([CallSignalPayload.segment]).
  switchOffer('switch_offer'),

  /// The callee's answer to [switchOffer].
  switchAnswer('switch_answer'),
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

  /// A group call that already has [CallRoom.maxParticipants] people.
  full('full'),
  unknown('unknown');

  const CallEndReason(this.wire);

  @override
  final String wire;
}

/// The room a pairwise call belongs to, when it is one link of a group call
/// (ADR-034). Sealed inside the call signal like everything else: the server
/// never sees a room.
final class CallRoom {
  const CallRoom({
    required this.id,
    required this.group,
    this.participants = const [],
  });

  /// The most people in one room.
  static const maxParticipants = 4;

  /// Chosen by whoever started the room; the same on every link.
  final String id;

  /// The group conversation the call was started in (`group:<id>`).
  final String group;

  /// The accounts in the room when this offer was made, the sender included.
  /// A person who accepts offers to every other one of them.
  final List<String> participants;

  JsonMap toJson() => {'id': id, 'group': group, 'participants': participants};

  factory CallRoom.fromJson(JsonReader json) {
    final people = json.strings('participants');
    if (people.length > maxParticipants) {
      throw ProtocolFormatException('too many', path: 'participants');
    }
    return CallRoom(
      id: json.nonEmpty('id'),
      group: json.nonEmpty('group'),
      participants: people,
    );
  }
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
    this.screen,
    this.room,
    this.segment,
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

  /// `media`: the sender's video is a shared screen (true), or the camera
  /// again (false). A viewer fits a screen inside its window instead of
  /// cropping it.
  final bool? screen;

  /// `offer`: this call is one link of a group call (ADR-034). Peers that do
  /// not know it ring a plain call.
  final CallRoom? room;

  /// Which media connection of the call a `switch_offer`, `switch_answer` or
  /// `ice` belongs to: 0 (omitted) is the one the call started with, and each
  /// switch makes the next number.
  final int? segment;

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
    'screen': screen,
    'room': room?.toJson(),
    'segment': segment,
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
      screen: json.has('screen') ? json.boolean('screen') : null,
      room: json.has('room') ? CallRoom.fromJson(json.object('room')) : null,
      segment: json.has('segment') ? json.integer('segment') : null,
    );
  }

  @override
  String toString() => 'CallSignalPayload(${type.wire}, redacted)';
}
