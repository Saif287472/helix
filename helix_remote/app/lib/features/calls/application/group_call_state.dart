import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/chat/chat_naming.dart';
import 'package:helix_remote/core/engine/clock.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/features/calls/application/call_audio.dart';
import 'package:helix_remote/features/calls/application/call_controller.dart';
import 'package:helix_remote/features/calls/application/call_copy.dart';
import 'package:helix_remote/features/calls/application/call_screen_state.dart';
import 'package:helix_remote/features/calls/application/group_calls_port.dart';
import 'package:helix_remote/features/calls/application/media/call_media_hub.dart';
import 'package:helix_remote/features/calls/application/media/call_media_providers.dart';
import 'package:helix_remote/features/calls/application/platform/call_platform.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:orbit_ui/models.dart';

// The participant states the screen draws, for presentation to name.
export 'package:helix_remote_engine/helix_remote_engine.dart'
    show GroupParticipantState;

/// One other person's tile.
@immutable
final class GroupTileInfo {
  const GroupTileInfo({
    required this.account,
    required this.name,
    required this.avatar,
    required this.state,
  });

  final String account;
  final String name;
  final HelixAvatarModel avatar;
  final GroupParticipantState state;

  @override
  bool operator ==(Object other) =>
      other is GroupTileInfo &&
      other.account == account &&
      other.name == name &&
      other.state == state;

  @override
  int get hashCode => Object.hash(account, name, state);
}

/// Everything the group call screen draws, in plain values.
@immutable
final class GroupCallScreenState {
  const GroupCallScreenState({
    required this.roomId,
    required this.group,
    required this.title,
    required this.starterName,
    required this.stage,
    required this.video,
    required this.tiles,
    this.statusText = '',
    this.endDetail,
    this.answeredAt,
    this.talkTime,
    this.muted = false,
    this.cameraOn = false,
    this.local,
    this.remotes = const {},
    this.audio = const CallAudioState(),
    this.notice,
    this.busy = false,
  });

  final String roomId;

  /// The group conversation (`group:<id>`).
  final String group;
  final String title;
  final String starterName;
  final CallStage stage;
  final bool video;
  final List<GroupTileInfo> tiles;
  final String statusText;
  final String? endDetail;
  final DateTime? answeredAt;
  final Duration? talkTime;
  final bool muted;
  final bool cameraOn;
  final CallVideoSurface? local;
  final Map<String, CallVideoSurface> remotes;
  final CallAudioState audio;
  final String? notice;
  final bool busy;

  bool get isLive => stage != CallStage.ended;

  /// The microphone is open (the shared capture has published its picture).
  bool get mediaOpen => local != null;

  /// This room as the phone's side effects see a call (ring, foreground
  /// service, lock screen, audio): the same effects serve 1:1 and group calls.
  CallScreenState asCall() => CallScreenState(
    callId: roomId,
    peer: group,
    title: title,
    avatar: HelixAvatarModel(name: title),
    incoming: stage == CallStage.incoming,
    video: video,
    stage: stage,
    statusText: statusText,
    answeredAt: answeredAt,
    muted: muted,
    cameraOn: cameraOn,
    audio: audio,
    local: local,
  );

  GroupCallScreenState copyWith({String? notice, bool? busy}) =>
      GroupCallScreenState(
        roomId: roomId,
        group: group,
        title: title,
        starterName: starterName,
        stage: stage,
        video: video,
        tiles: tiles,
        statusText: statusText,
        endDetail: endDetail,
        answeredAt: answeredAt,
        talkTime: talkTime,
        muted: muted,
        cameraOn: cameraOn,
        local: local,
        remotes: remotes,
        audio: audio,
        notice: notice ?? this.notice,
        busy: busy ?? this.busy,
      );

  @override
  bool operator ==(Object other) =>
      other is GroupCallScreenState &&
      other.roomId == roomId &&
      other.title == title &&
      other.stage == stage &&
      other.video == video &&
      listEquals(other.tiles, tiles) &&
      other.statusText == statusText &&
      other.endDetail == endDetail &&
      other.answeredAt == answeredAt &&
      other.muted == muted &&
      other.cameraOn == cameraOn &&
      other.local == local &&
      mapEquals(other.remotes, remotes) &&
      other.audio.route == audio.route &&
      listEquals(other.audio.available, audio.available) &&
      other.notice == notice &&
      other.busy == busy;

  @override
  int get hashCode => Object.hash(
    roomId,
    stage,
    muted,
    cameraOn,
    notice,
    busy,
    Object.hashAll(tiles),
  );
}

/// The group's name for a call screen ("Friday crew"); a plain label while it
/// loads.
final groupCallTitleProvider = FutureProvider.family<String, String>((
  ref,
  conversation,
) async {
  final gateway = await ref.watch(chatGatewayProvider.future);
  final people = await ref.watch(peopleDirectoryProvider.future);
  final chat = await gateway.chat(conversation);
  return chat == null ? 'Group call' : chatTitleOf(chat, people);
});

/// The pictures of the live room: yours, and each person's.
final groupMediaProvider = StreamProvider<void>(
  (ref) => ref.watch(callMediaHubProvider).watchGroup(),
);

/// What the group call screen draws, or null when there is no room.
final groupCallScreenStateProvider = Provider<GroupCallScreenState?>((ref) {
  final room = ref.watch(currentGroupCallProvider).value;
  if (room == null) return null;
  ref.watch(groupMediaProvider);
  final hub = ref.watch(callMediaHubProvider);
  final people =
      ref.watch(peopleDirectoryProvider).value ?? PeopleDirectory.empty;
  final title = ref.watch(groupCallTitleProvider(room.group)).value;
  final audio = ref.watch(callAudioProvider);
  final notice = ref.watch(callNoticeProvider);
  final busy = ref.watch(callBusyProvider);
  final stage = switch (room.phase) {
    GroupCallPhase.ringing => CallStage.incoming,
    GroupCallPhase.active =>
      room.answeredAt == null ? CallStage.connecting : CallStage.active,
    GroupCallPhase.ended => CallStage.ended,
  };
  return GroupCallScreenState(
    roomId: room.roomId,
    group: room.group,
    title: title ?? 'Group call',
    starterName: people.displayOf(room.starter),
    stage: stage,
    video: room.video,
    statusText: switch (stage) {
      CallStage.incoming => 'Incoming group call',
      CallStage.connecting => 'Connecting…',
      CallStage.ended => CallCopy.groupEnded(room.end),
      _ => '',
    },
    endDetail: stage == CallStage.ended ? CallCopy.groupEnded(room.end) : null,
    answeredAt: room.answeredAt,
    talkTime: room.answeredAt != null && room.endedAt != null
        ? room.endedAt!.difference(room.answeredAt!)
        : null,
    muted: room.muted,
    cameraOn: room.cameraOn,
    local: hub.groupLocal,
    remotes: hub.groupRemotes,
    audio: audio,
    notice: notice != null && notice.$1 == room.roomId
        ? notice.$2
        : (room.endingSoon ? CallCopy.callTimeEnding : null),
    busy: busy == room.roomId,
    tiles: [
      for (final p in room.participants)
        GroupTileInfo(
          account: p.account,
          name: people.nameOf(p.account).tileNames.display,
          avatar: HelixAvatarModel(
            name: people.nameOf(p.account).tileNames.display,
            colorIndex: HelixAvatarModel.colorIndexFor(p.account),
          ),
          state: p.state,
        ),
    ],
  );
});

/// The group call as the phone's side effects (ringing, foreground service,
/// lock screen, audio) see a call: a 1:1 call if there is one, else the room.
final callEffectsStateProvider = Provider<CallScreenState?>((ref) {
  final single = ref.watch(callScreenStateProvider);
  if (single != null) return single;
  final room = ref.watch(groupCallScreenStateProvider);
  if (room == null) return null;
  // The ring and the service name the group: wait for its (local) name
  // rather than announcing a generic one.
  if (ref.watch(groupCallTitleProvider(room.group)).isLoading) return null;
  return room.asCall();
});

/// How long the connected room has run, ticking once a second.
final groupCallElapsedProvider = StreamProvider<Duration?>((ref) {
  final answeredAt = ref.watch(
    groupCallScreenStateProvider.select((s) => s?.answeredAt),
  );
  final frozen = ref.watch(
    groupCallScreenStateProvider.select((s) => s?.talkTime),
  );
  final clock = ref.watch(clockProvider);
  final live = ref.watch(
    groupCallScreenStateProvider.select((s) => s?.isLive ?? false),
  );
  if (answeredAt == null) return Stream.value(null);
  if (!live) return Stream.value(frozen);
  Stream<Duration?> ticks() async* {
    yield clock().difference(answeredAt);
    yield* Stream.periodic(
      const Duration(seconds: 1),
      (_) => clock().difference(answeredAt),
    );
  }

  return ticks();
});

/// The things a person does on the group call screen.
final groupCallActionsProvider = Provider<GroupCallActions>(
  GroupCallActions.new,
);

final class GroupCallActions {
  GroupCallActions(this._ref);

  final Ref _ref;

  GroupCallScreenState? get _state => _ref.read(groupCallScreenStateProvider);

  Future<GroupCallsPort> get _port => _ref.read(groupCallsPortProvider.future);

  /// Joins: asks for the microphone (and the camera in a video room) first and
  /// keeps ringing if refused, with a line that says what to do.
  Future<void> accept() async {
    final room = _state;
    if (room == null || room.stage != CallStage.incoming || room.busy) return;
    final notice = _ref.read(callNoticeProvider.notifier);
    final busy = _ref.read(callBusyProvider.notifier);
    notice.clear();
    busy.set(room.roomId);
    try {
      final result = await _ref
          .read(callPermissionsProvider)
          .ensure(video: room.video);
      if (result != CallPermissionResult.granted) {
        notice.show(
          room.roomId,
          result == CallPermissionResult.cameraDenied
              ? CallCopy.cameraDenied
              : CallCopy.microphoneDenied,
        );
        return;
      }
      await (await _port).accept();
    } on CallFailedException catch (e) {
      notice.show(room.roomId, CallCopy.failure(e.reason));
    } finally {
      busy.set(null);
    }
  }

  Future<void> decline() async {
    final room = _state;
    if (room == null || room.stage != CallStage.incoming) return;
    await _guard(room, (port) => port.decline());
  }

  /// Leaves the room, or declines the invitation that still rings.
  Future<void> hangUp() async {
    final room = _state;
    if (room == null || !room.isLive) return;
    await _guard(room, (port) => port.hangUp());
  }

  Future<void> setMuted({required bool muted}) async {
    final room = _state;
    if (room == null || room.stage == CallStage.incoming || !room.isLive) {
      return;
    }
    await _guard(room, (port) => port.setMuted(muted: muted), busy: false);
  }

  Future<void> setCameraEnabled({required bool enabled}) async {
    final room = _state;
    if (room == null || !room.video || room.stage == CallStage.incoming) {
      return;
    }
    await _guard(
      room,
      (port) => port.setCameraEnabled(enabled: enabled),
      busy: false,
    );
  }

  Future<void> switchCamera() async {
    final room = _state;
    if (room == null || !room.video || !room.cameraOn) return;
    await _ref.read(callMediaHubProvider).switchCamera();
  }

  Future<void> selectRoute(CallAudioRoute route) =>
      _ref.read(callAudioProvider.notifier).select(route);

  void dismissNotice() => _ref.read(callNoticeProvider.notifier).clear();

  Future<void> _guard(
    GroupCallScreenState room,
    Future<void> Function(GroupCallsPort port) action, {
    bool busy = true,
  }) async {
    final flag = _ref.read(callBusyProvider.notifier);
    if (busy) flag.set(room.roomId);
    try {
      await action(await _port);
    } on CallFailedException catch (e) {
      _ref
          .read(callNoticeProvider.notifier)
          .show(room.roomId, CallCopy.failure(e.reason));
    } finally {
      if (busy) flag.set(null);
    }
  }
}
