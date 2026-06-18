// lib/ui/widgets/call_overlay.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_domain/domain/call/call_state.dart';
import 'package:helix/providers/app_providers.dart';
import 'package:helix/ui/screens/call/call_screen.dart';

/// Wraps [child] and overlays the call UI whenever a call is in progress.
///
/// Presentation rules, mirroring Android's own calling conventions:
///  - An incoming call that starts ringing while Helix is already open
///    and in the foreground is shown as a small dismissible banner, so it
///    doesn't take over whatever the user was doing.
///  - An incoming call that starts ringing while the app is backgrounded
///    (another app in use, screen off, or device locked) is surfaced via
///    the system notification (see `incoming_call_alert_controller.dart`);
///    if the user then opens the app — by tapping that notification, or via
///    the OS unlocking into it for a full-screen-intent call notification —
///    the full-screen [CallScreen] is shown, since the user is explicitly
///    engaging with the call.
///  - Once a call is accepted/outgoing/active, the full-screen [CallScreen]
///    is always used (it can still be minimized to a small bar).
class CallOverlay extends ConsumerStatefulWidget {
  const CallOverlay({super.key, required this.child});

  final Widget? child;

  @override
  ConsumerState<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends ConsumerState<CallOverlay> {
  /// The callId of the most recent incoming-ringing call we've evaluated,
  /// so each new call is only classified once (at the moment it starts
  /// ringing) rather than re-evaluated on every rebuild.
  String? _evaluatedCallId;

  /// Whether the currently-ringing incoming call should present as a
  /// compact banner rather than a full-screen takeover.
  bool _compactIncoming = false;

  @override
  Widget build(BuildContext context) {
    final callAsync = ref.watch(currentCallProvider);
    final call = callAsync.value;
    final base = widget.child ?? const SizedBox.shrink();

    ref.listen<AsyncValue<CallState?>>(currentCallProvider, (previous, next) {
      final nextCall = next.value;

      if (nextCall == null) {
        _evaluatedCallId = null;
        _compactIncoming = false;
        ref.read(callMinimizedProvider.notifier).state = false;
        return;
      }

      final isIncomingRinging =
          nextCall.direction == CallDirection.incoming &&
          nextCall.status == CallStatus.ringing;

      if (isIncomingRinging && _evaluatedCallId != nextCall.callId) {
        _evaluatedCallId = nextCall.callId;
        // If the app was already resumed (foreground) the instant this call
        // started ringing, the user was already using Helix — present
        // a compact banner. Otherwise the app is only foreground now because
        // the user chose to engage with the call (tapped the notification,
        // or the OS brought it up over a locked screen) — go full-screen.
        _compactIncoming =
            ref.read(appLifecycleStateProvider) == AppLifecycleState.resumed;
        ref.read(callMinimizedProvider.notifier).state = false;
      } else if (!isIncomingRinging) {
        _compactIncoming = false;
      }
    });

    if (call == null) return base;

    final isIncomingRinging =
        call.direction == CallDirection.incoming &&
        call.status == CallStatus.ringing;

    Widget overlay;
    if (isIncomingRinging && _compactIncoming) {
      overlay = _IncomingCallBanner(call: call);
    } else if (ref.watch(callMinimizedProvider)) {
      overlay = _MinimizedCallBar(call: call);
    } else {
      // Keyed by callId so a fresh call never inherits stale local state
      // (swapped main/PIP view, drag position, elapsed timer) from a
      // previous one.
      overlay = CallScreen(key: ValueKey(call.callId), call: call);
    }

    return Stack(children: [base, overlay]);
  }
}

// ---------------------------------------------------------------------------

class _MinimizedCallBar extends ConsumerWidget {
  const _MinimizedCallBar({required this.call});

  final CallState call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: GestureDetector(
          onTap: () => ref.read(callMinimizedProvider.notifier).state = false,
          child: Material(
            color: Colors.green.shade800,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              child: Row(
                children: [
                  const Icon(Icons.call, color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      call.peerDisplayName,
                      style: const TextStyle(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Text(
                    'Tap to return',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Compact heads-up-style banner for an incoming call that started ringing
/// while the app was already open, so it doesn't take over the screen.
class _IncomingCallBanner extends ConsumerWidget {
  const _IncomingCallBanner({required this.call});

  final CallState call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initials = call.peerDisplayName.isNotEmpty
        ? call.peerDisplayName[0].toUpperCase()
        : '?';

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(8),
          // clipBehavior omitted (defaults to Clip.none) so that the
          // InkWell tap targets at the right edge are never clipped by the
          // rounded-rectangle border. Clip.antiAlias clips BOTH painting and
          // hit-testing, so taps in the corner gap areas fell through to the
          // Navigator layer behind the banner and were never registered.
          child: Material(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(16),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white24,
                    child: Text(
                      initials,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          call.peerDisplayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          call.isVideoEnabled
                              ? 'Incoming video call'
                              : 'Incoming call',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Read callServiceProvider inside the callback rather than
                  // capturing it at build time: if the provider is invalidated
                  // between build and tap the captured reference would have
                  // _currentCall == null and silently no-op.
                  _BannerButton(
                    icon: Icons.call_end,
                    color: Colors.red,
                    tooltip: 'Decline',
                    onTap: () => ref.read(callServiceProvider).declineIncomingCall(),
                  ),
                  _BannerButton(
                    icon: Icons.call,
                    color: Colors.green,
                    tooltip: 'Accept',
                    onTap: () => ref.read(callServiceProvider).acceptIncomingCall(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A simple circular tap target for the incoming-call banner. Uses
/// [GestureDetector] directly (not [IconButton]/[InkWell]) so that the 48 × 48
/// touch area is unambiguously owned by this widget and cannot be clipped by
/// an ancestor [Material] with rounded corners.
class _BannerButton extends StatelessWidget {
  const _BannerButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: color),
        ),
      ),
    );
  }
}
