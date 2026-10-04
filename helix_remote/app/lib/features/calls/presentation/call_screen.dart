import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/calls/application/call_audio.dart';
import 'package:helix_remote/features/calls/application/call_controller.dart';
import 'package:helix_remote/features/calls/application/call_screen_state.dart';
import 'package:helix_remote/features/calls/application/platform/call_platform.dart';
import 'package:helix_remote/features/calls/presentation/in_call_view.dart';
import 'package:helix_remote/features/calls/presentation/incoming_call_view.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The full-screen call: ringing here, dialing, connecting, live, and the
/// moment after it ends.
///
/// It draws [callScreenStateProvider] and nothing else, and closes itself when
/// the call is gone (the state holds an ended call for a moment first, so
/// "Answered on another device" is readable). The back gesture is ignored
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

  Future<void> _chooseRoute(CallAudioState audio) async {
    final route = await showHelixBottomSheet<CallAudioRoute>(
      context,
      title: 'Audio output',
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in audio.available)
            ListTile(
              leading: Icon(_iconOf(option)),
              title: Text(option.label),
              trailing: option == audio.route ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(option),
            ),
        ],
      ),
    );
    if (route != null) {
      await ref.read(callActionsProvider).selectRoute(route);
    }
  }

  static IconData _iconOf(CallAudioRoute route) => switch (route) {
    CallAudioRoute.earpiece => Icons.phone_in_talk,
    CallAudioRoute.speaker => Icons.volume_up,
    CallAudioRoute.bluetooth => Icons.bluetooth_audio,
    CallAudioRoute.wiredHeadset => Icons.headset,
  };

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(callScreenStateProvider);
    ref.listen(callScreenStateProvider, (_, next) => _closeIfOver(next));
    if (state == null) {
      _closeIfOver(null);
      return const Scaffold(backgroundColor: HelixScrimColors.backdrop);
    }
    final actions = ref.read(callActionsProvider);
    final elapsed = ref.watch(callElapsedProvider).value;
    return PopScope(
      canPop: !state.isLive,
      child: Scaffold(
        backgroundColor: HelixScrimColors.backdrop,
        body: state.stage == CallStage.incoming
            ? IncomingCallView(
                state: state,
                onAccept: state.busy ? null : actions.accept,
                onDecline: state.busy ? null : actions.decline,
                onDismissNotice: actions.dismissNotice,
              )
            : InCallView(
                state: state,
                elapsed: elapsed,
                callbacks: CallCallbacks(
                  onHangUp: actions.hangUp,
                  onMute: ({required muted}) => actions.setMuted(muted: muted),
                  onCamera: ({required enabled}) =>
                      actions.setCameraEnabled(enabled: enabled),
                  onFlipCamera: actions.switchCamera,
                  onRoute: () {
                    final audio = state.audio;
                    if (audio.available.length > 2) {
                      _chooseRoute(audio);
                    } else {
                      // Two outputs: the control is a toggle.
                      final next = audio.available.firstWhere(
                        (route) => route != audio.route,
                        orElse: () => audio.route,
                      );
                      actions.selectRoute(next);
                    }
                  },
                  onDismissNotice: actions.dismissNotice,
                ),
              ),
      ),
    );
  }
}
