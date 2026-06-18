// lib/providers/controllers/wakelock_controller.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:helix_domain/domain/call/call_state.dart';
import 'package:helix/providers/app_providers.dart';

/// Keeps the screen on during active video calls. Without a wake lock the
/// system screen-timeout fires even while the camera feed is live, turning
/// the display off mid-call.
///
/// Audio calls are intentionally excluded — the proximity sensor (see
/// proximity_screen_controller.dart) already handles those, and draining the
/// battery to keep the screen on while the phone is at someone's ear is
/// pointless.
final wakelockControllerProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<CallState?>>(currentCallProvider, (previous, next) {
    final call = next.value;
    final videoCallActive =
        call != null && call.status == CallStatus.active && call.isVideoEnabled;
    WakelockPlus.toggle(enable: videoCallActive).catchError((_) {});
  });

  ref.onDispose(() => WakelockPlus.disable().catchError((_) {}));
});
