import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/calls/application/call_controller.dart';
import 'package:helix_remote/features/calls/application/call_screen_state.dart';
import 'package:helix_remote/features/calls/application/group_call_state.dart';
import 'package:helix_remote/features/calls/application/media/call_media_hub.dart';
import 'package:helix_remote/features/calls/application/platform/call_platform.dart';
import 'package:helix_remote/features/calls/application/call_copy.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: the full-screen group call, ringing and live, drawn by
/// `orbit_ui`'s group call screen from [groupCallScreenStateProvider]. It
/// closes itself when the room is gone; the back gesture is ignored while the
/// room is live (leaving is hanging up).
class GroupCallScreen extends ConsumerStatefulWidget {
  const GroupCallScreen({super.key});

  @override
  ConsumerState<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends ConsumerState<GroupCallScreen> {
  late final CallScreenOpen _open;
  bool _closing = false;
  orbit.GroupCallModel? _last;

  @override
  void initState() {
    super.initState();
    _open = ref.read(callScreenOpenProvider.notifier);
    Future.microtask(() => _open.set(open: true));
  }

  @override
  void dispose() {
    Future.microtask(() => _open.set(open: false));
    super.dispose();
  }

  void _closeIfOver(GroupCallScreenState? state) {
    if (state != null || _closing || !mounted) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  static orbit.CallAudioRoute _routeOf(CallAudioRoute r) => switch (r) {
    CallAudioRoute.earpiece => orbit.CallAudioRoute.earpiece,
    CallAudioRoute.speaker => orbit.CallAudioRoute.speaker,
    CallAudioRoute.bluetooth => orbit.CallAudioRoute.bluetooth,
    CallAudioRoute.wiredHeadset => orbit.CallAudioRoute.wiredHeadset,
  };

  static CallAudioRoute _appRouteOf(orbit.CallAudioRoute r) => switch (r) {
    orbit.CallAudioRoute.earpiece => CallAudioRoute.earpiece,
    orbit.CallAudioRoute.speaker => CallAudioRoute.speaker,
    orbit.CallAudioRoute.bluetooth => CallAudioRoute.bluetooth,
    orbit.CallAudioRoute.wiredHeadset => CallAudioRoute.wiredHeadset,
  };

  static orbit.GroupTileState _tileOf(GroupTileInfo tile) =>
      switch (tile.state) {
        GroupParticipantState.invited => orbit.GroupTileState.ringing,
        GroupParticipantState.connecting => orbit.GroupTileState.connecting,
        GroupParticipantState.connected => orbit.GroupTileState.connected,
        GroupParticipantState.left => orbit.GroupTileState.left,
        GroupParticipantState.failed => orbit.GroupTileState.failed,
      };

  orbit.GroupCallModel _model(GroupCallScreenState s, Duration? elapsed) {
    return orbit.GroupCallModel(
      roomId: s.roomId,
      title: s.title,
      stage: switch (s.stage) {
        CallStage.incoming => orbit.CallStage.incoming,
        CallStage.ended => orbit.CallStage.ended,
        CallStage.connecting => orbit.CallStage.connecting,
        _ => orbit.CallStage.active,
      },
      statusText: s.statusText,
      starterName: s.starterName,
      video: s.video,
      elapsedLabel: elapsed != null && s.stage == CallStage.active
          ? formatCallDuration(elapsed)
          : null,
      endDetail: s.endDetail,
      muted: s.muted,
      cameraOn: s.cameraOn,
      hasLocalVideo: s.cameraOn && s.local != null,
      audioRoute: _routeOf(s.audio.route),
      audioRoutes: [for (final r in s.audio.available) _routeOf(r)],
      notice: s.notice,
      busy: s.busy,
      tiles: [
        for (final t in s.tiles)
          orbit.GroupCallTile(
            id: t.account,
            name: t.name,
            avatar: t.avatar,
            state: _tileOf(t),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(groupCallScreenStateProvider);
    ref.listen(groupCallScreenStateProvider, (_, next) => _closeIfOver(next));
    if (state == null) {
      _closeIfOver(null);
      final last = _last;
      return last == null
          ? const ColoredBox(color: orbit.OrbitNight.night)
          : orbit.GroupCallScreen(model: last);
    }
    final actions = ref.read(groupCallActionsProvider);
    final elapsed = ref.watch(groupCallElapsedProvider).value;
    final model = _last = _model(state, elapsed);
    return PopScope(
      canPop: !state.isLive,
      child: orbit.GroupCallScreen(
        model: model,
        actions: orbit.GroupCallActions(
          answer: () => unawaited(actions.accept()),
          decline: () => unawaited(actions.decline()),
          hangUp: () => unawaited(actions.hangUp()),
          setMuted: (muted) => unawaited(actions.setMuted(muted: muted)),
          setCamera: (on) => unawaited(actions.setCameraEnabled(enabled: on)),
          flipCamera: () => unawaited(actions.switchCamera()),
          selectAudioRoute: (route) =>
              unawaited(actions.selectRoute(_appRouteOf(route))),
          dismissNotice: actions.dismissNotice,
        ),
        tileVideo: (context, id, placeholder) {
          final surface = state.remotes[id];
          return surface == null
              ? placeholder
              : _Frames(surface: surface, placeholder: placeholder);
        },
        localVideo: (context, placeholder) => state.local == null
            ? placeholder
            : state.local!.build(mirror: true),
      ),
    );
  }
}

/// [surface] while it has frames, else [placeholder].
class _Frames extends StatelessWidget {
  const _Frames({required this.surface, required this.placeholder});

  final CallVideoSurface surface;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: surface.changes,
    builder: (context, _) => surface.hasFrames ? surface.build() : placeholder,
  );
}
