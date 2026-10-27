import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/calls/application/call_controller.dart';
import 'package:helix_remote/features/calls/application/call_copy.dart';
import 'package:helix_remote/features/calls/application/call_screen_state.dart';
import 'package:helix_remote/features/calls/application/media/call_media_hub.dart';
import 'package:helix_remote/features/calls/application/platform/call_platform.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: the full-screen call, ringing here, dialing, connecting, live,
/// and the moment after it ends, drawn by `orbit_ui`'s call screen
/// (`contracts/calls.md`).
///
/// It draws [callScreenStateProvider] and nothing else, and closes itself
/// when the call is gone (the state holds an ended call for a moment first,
/// so "Answered on another device" is readable). The back gesture is ignored
/// while the call is live: leaving a call is hanging up, and an incoming one
/// is answered or declined, never dismissed by accident.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  late final CallScreenOpen _open;
  bool _closing = false;

  /// The last call drawn, kept for the frame before the screen closes.
  orbit.CallModel? _last;

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

  void _closeIfOver(CallScreenState? state) {
    if (state != null || _closing || !mounted) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  static orbit.CallStage _stageOf(CallStage s) => switch (s) {
    CallStage.dialing => orbit.CallStage.dialing,
    CallStage.incoming => orbit.CallStage.incoming,
    CallStage.connecting => orbit.CallStage.connecting,
    CallStage.active => orbit.CallStage.active,
    CallStage.ended => orbit.CallStage.ended,
  };

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

  orbit.CallModel _model(CallScreenState s, Duration? elapsed) {
    final live = s.isLive;
    return orbit.CallModel(
      callId: s.callId,
      title: s.title,
      subtitle: s.subtitle?.trim(),
      avatar: s.avatar,
      video: s.video,
      stage: _stageOf(s.stage),
      statusText: s.statusText,
      // The clock runs while the call is live and not reconnecting; until
      // its first tick the line says "Connected".
      elapsedLabel:
          elapsed != null &&
              s.stage == CallStage.active &&
              s.quality != CallQuality.reconnecting
          ? formatCallDuration(elapsed)
          : null,
      talkTimeLabel: s.stage == CallStage.ended && s.talkTime != null
          ? formatCallDuration(s.talkTime!)
          : null,
      endDetail: s.endDetail,
      endIsProblem: s.endIsProblem,
      quality: switch (s.quality) {
        CallQuality.good => orbit.CallQuality.good,
        CallQuality.weak => orbit.CallQuality.weak,
        CallQuality.reconnecting => orbit.CallQuality.reconnecting,
      },
      muted: s.muted,
      cameraOn: s.cameraOn,
      screenSharing: s.screenSharing,
      peerScreenSharing: s.peerScreenSharing,
      // Android and Windows can capture their screen; the control shows on a
      // live video call.
      canShareScreen:
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows,
      audioRoute: _routeOf(s.audio.route),
      audioRoutes: [for (final r in s.audio.available) _routeOf(r)],
      notice: s.notice,
      busy: s.busy,
      videoLayout: s.showsVideo && live,
      hasLocalVideo: s.cameraOn && s.local != null,
      hasRemoteVideo: s.stage == CallStage.active && s.remote != null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(callScreenStateProvider);
    ref.listen(callScreenStateProvider, (_, next) => _closeIfOver(next));
    if (state == null) {
      _closeIfOver(null);
      final last = _last;
      return last == null
          ? const ColoredBox(color: orbit.OrbitNight.night)
          : orbit.CallScreen(model: last);
    }
    final actions = ref.read(callActionsProvider);
    final elapsed = ref.watch(callElapsedProvider).value;
    final model = _last = _model(state, elapsed);
    final remote = state.remote;
    final local = state.local;
    return PopScope(
      canPop: !state.isLive,
      child: orbit.CallScreen(
        model: model,
        actions: orbit.CallActions(
          answer: () => unawaited(actions.accept()),
          decline: () => unawaited(actions.decline()),
          hangUp: () => unawaited(actions.hangUp()),
          setMuted: (muted) => unawaited(actions.setMuted(muted: muted)),
          setCamera: (on) => unawaited(actions.setCameraEnabled(enabled: on)),
          flipCamera: () => unawaited(actions.switchCamera()),
          setScreenSharing: (on) =>
              unawaited(actions.setScreenSharing(enabled: on)),
          selectAudioRoute: (route) =>
              unawaited(actions.selectRoute(_appRouteOf(route))),
          dismissNotice: actions.dismissNotice,
        ),
        // Their video once frames arrive; their picture until then (the
        // camera is off, or the first frame has not landed).
        remoteVideo: (context, placeholder, {required screen}) => remote == null
            ? placeholder
            : _Frames(surface: remote, placeholder: placeholder, fit: screen),
        localVideo: (context, placeholder) => local == null
            ? placeholder
            : local.build(mirror: state.frontCamera),
      ),
    );
  }
}

/// [surface] while it has frames, else [placeholder].
class _Frames extends StatelessWidget {
  const _Frames({
    required this.surface,
    required this.placeholder,
    this.fit = false,
  });

  final CallVideoSurface surface;
  final Widget placeholder;

  /// A shared screen: the whole picture, not cropped.
  final bool fit;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: surface.changes,
    builder: (context, _) =>
        surface.hasFrames ? surface.build(fit: fit) : placeholder,
  );
}
