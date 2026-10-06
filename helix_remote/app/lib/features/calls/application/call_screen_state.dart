import 'package:flutter/foundation.dart';
import 'package:helix_remote/features/calls/application/call_audio.dart';
import 'package:helix_remote/features/calls/application/call_copy.dart';
import 'package:helix_remote/features/calls/application/media/call_media_hub.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Which screen a call is on.
enum CallStage {
  /// Outgoing: the offer is going out or a device is ringing.
  dialing,

  /// Incoming: ringing here, waiting for Answer or Decline.
  incoming,

  /// Answered; media is being set up.
  connecting,

  /// Media flows.
  active,

  /// Over; the screen shows how it ended for a moment.
  ended,
}

/// How good the live connection is.
enum CallQuality { good, weak, reconnecting }

/// Everything the call screen draws, in plain values.
///
/// Derived (see `callScreenStateProvider`) from the engine's call snapshot, the
/// media's video surfaces and quality, the audio route, the people names and
/// the one-line notice; the screen holds no rules of its own, so the incoming,
/// outgoing and in-call layouts cannot drift apart.
@immutable
final class CallScreenState {
  const CallScreenState({
    required this.callId,
    required this.peer,
    required this.title,
    required this.avatar,
    required this.incoming,
    required this.video,
    required this.stage,
    required this.statusText,
    this.subtitle,
    this.end,
    this.endDetail,
    this.answeredAt,
    this.talkTime,
    this.muted = false,
    this.cameraOn = false,
    this.frontCamera = true,
    this.audio = const CallAudioState(),
    this.quality = CallQuality.good,
    this.local,
    this.remote,
    this.notice,
    this.busy = false,
  });

  final String callId;

  /// The other party's account id.
  final String peer;

  /// The name to show, by the people-naming order.
  final String title;

  /// The line under the name (the number or `~Helix name`), if any.
  final String? subtitle;
  final HelixAvatarModel avatar;
  final bool incoming;

  /// The call was offered with video.
  final bool video;
  final CallStage stage;

  /// "Calling…", "Ringing…", "Connecting…", "Reconnecting…", "Incoming video
  /// call", "Answered on another device" and the like.
  final String statusText;

  /// Set when [stage] is [CallStage.ended].
  final CallEnd? end;
  final String? endDetail;

  /// When media connected, for the timer; null before.
  final DateTime? answeredAt;

  /// How long an ended call that was answered lasted; null otherwise.
  final Duration? talkTime;
  final bool muted;
  final bool cameraOn;
  final bool frontCamera;
  final CallAudioState audio;
  final CallQuality quality;
  final CallVideoSurface? local;
  final CallVideoSurface? remote;

  /// A one-line message the screen shows (permission refused, answer failed),
  /// null when there is none.
  final String? notice;

  /// An answer or hang-up is in flight: its button waits.
  final bool busy;

  bool get isLive => stage != CallStage.ended;

  /// Both sides can see each other's video.
  bool get showsVideo => video && stage != CallStage.incoming;

  /// The mute, camera and audio controls apply: media is up or coming.
  bool get hasControls =>
      stage == CallStage.active ||
      stage == CallStage.connecting ||
      stage == CallStage.dialing;

  CallScreenState copyWith({String? notice, bool? busy}) => CallScreenState(
    callId: callId,
    peer: peer,
    title: title,
    subtitle: subtitle,
    avatar: avatar,
    incoming: incoming,
    video: video,
    stage: stage,
    statusText: statusText,
    end: end,
    endDetail: endDetail,
    answeredAt: answeredAt,
    talkTime: talkTime,
    muted: muted,
    cameraOn: cameraOn,
    frontCamera: frontCamera,
    audio: audio,
    quality: quality,
    local: local,
    remote: remote,
    notice: notice ?? this.notice,
    busy: busy ?? this.busy,
  );

  /// Builds the state from the engine's [call] and what surrounds it.
  static CallScreenState from({
    required CallSnapshot call,
    required HelixPersonNames names,
    CallMediaInfo? media,
    CallAudioState audio = const CallAudioState(),
    String? notice,
    bool busy = false,
  }) {
    final reconnecting =
        call.phase == CallPhase.active &&
        media != null &&
        media.state == CallMediaState.disconnected;
    final stage = switch (call.phase) {
      CallPhase.calling || CallPhase.ringing =>
        call.isIncoming ? CallStage.incoming : CallStage.dialing,
      CallPhase.connecting => CallStage.connecting,
      CallPhase.active => CallStage.active,
      CallPhase.ended => CallStage.ended,
    };
    final title = names.display;
    return CallScreenState(
      callId: call.callId,
      peer: call.peer,
      title: title,
      subtitle: names.secondary,
      avatar: HelixAvatarModel(
        name: title,
        colorIndex: HelixAvatarModel.colorIndexFor(call.peer),
      ),
      incoming: call.isIncoming,
      video: call.video,
      stage: stage,
      statusText: CallCopy.status(call, reconnecting: reconnecting),
      end: call.end,
      endDetail: call.phase == CallPhase.ended
          ? CallCopy.endedDetail(call.end)
          : null,
      answeredAt: call.answeredAt,
      talkTime: call.answeredAt != null && call.endedAt != null
          ? call.endedAt!.difference(call.answeredAt!)
          : null,
      muted: call.muted,
      cameraOn: call.cameraOn,
      frontCamera: media?.frontCamera ?? true,
      audio: audio,
      quality: reconnecting
          ? CallQuality.reconnecting
          : (media?.weak ?? false)
          ? CallQuality.weak
          : CallQuality.good,
      local: media?.local,
      remote: media?.remote,
      notice: notice,
      busy: busy,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CallScreenState &&
      other.callId == callId &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.stage == stage &&
      other.statusText == statusText &&
      other.end == end &&
      other.answeredAt == answeredAt &&
      other.talkTime == talkTime &&
      other.muted == muted &&
      other.cameraOn == cameraOn &&
      other.frontCamera == frontCamera &&
      other.audio.route == audio.route &&
      listEquals(other.audio.available, audio.available) &&
      other.quality == quality &&
      other.local == local &&
      other.remote == remote &&
      other.notice == notice &&
      other.busy == busy;

  @override
  int get hashCode => Object.hash(
    callId,
    title,
    stage,
    statusText,
    muted,
    cameraOn,
    notice,
    busy,
  );
}
