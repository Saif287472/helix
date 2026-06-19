// lib/providers/controllers/proximity_screen_controller.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:helix_local_domain/domain/call/call_state.dart';
import 'package:helix/providers/app_providers.dart';

/// Turns the screen off when the phone is held to the ear during an active
/// call, and back on otherwise. Android-only — Helix also targets
/// Windows desktop, which has no proximity sensor.
final proximityScreenControllerProvider = Provider<void>((ref) {
  if (!Platform.isAndroid) return;

  var enabled = false;
  var pending = Future<void>.value();

  void setEnabled(bool value) {
    pending = pending
        .then((_) async {
          if (enabled == value) return;
          enabled = value;
          await ProximitySensor.setProximityScreenOff(value);
        })
        .catchError((_) {});
  }

  ref.listen<AsyncValue<CallState?>>(currentCallProvider, (previous, next) {
    final call = next.value;
    // During video calls the user looks at the screen — skip the proximity
    // sensor so the display doesn't turn off when they hold the phone up.
    final audioCallActive =
        call != null &&
        call.status == CallStatus.active &&
        !call.isVideoEnabled;
    setEnabled(audioCallActive);
  });

  ref.onDispose(() => setEnabled(false));
});
