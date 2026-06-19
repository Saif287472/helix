// lib/providers/controllers/incoming_call_alert_controller.dart

import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/domain/call/call_state.dart';
import 'package:helix/providers/app_providers.dart';

const _vibrationPattern = [0, 1000, 1000];

/// Plays a looping ringtone and vibration pattern while a call is
/// incoming+ringing, and raises a full-screen system notification if the
/// app is backgrounded at the time. Android-only — Helix also targets
/// Windows desktop, where the in-app full-screen [CallScreen] is the only
/// alert.
final incomingCallAlertControllerProvider = Provider<void>((ref) {
  if (!Platform.isAndroid) return;

  final player = AudioPlayer();
  unawaited(player.setReleaseMode(ReleaseMode.loop));
  String? alertingCallId;
  var generation = 0;
  var operation = Future<void>.value();

  Future<void> stopAlert() async {
    final callId = alertingCallId;
    if (callId == null) return;
    alertingCallId = null;
    await player.stop();
    await Vibration.cancel();
    await ref.read(notificationServiceProvider).cancelIncomingCall(callId);
  }

  Future<void> startAlert(CallState call, int token) async {
    alertingCallId = call.callId;
    final ringtoneAsset =
        ref.read(profileServiceProvider).profile?.ringtoneAsset ??
        kDefaultRingtoneAsset;

    if (token != generation) return;
    await player.play(AssetSource('sounds/$ringtoneAsset'));

    if (token != generation) {
      await player.stop();
      return;
    }
    if (await Vibration.hasVibrator()) {
      if (token != generation) return;
      await Vibration.vibrate(pattern: _vibrationPattern, repeat: 0);
    }
    if (token != generation) {
      await Vibration.cancel();
      return;
    }
    if (ref.read(appLifecycleStateProvider) != AppLifecycleState.resumed) {
      if (token != generation) return;
      await ref
          .read(notificationServiceProvider)
          .showIncomingCall(call.callId, call.peerDisplayName);
    }
  }

  void syncAlert(CallState? call) {
    final token = ++generation;
    final isIncomingRinging =
        call != null &&
        call.direction == CallDirection.incoming &&
        call.status == CallStatus.ringing;

    operation = operation
        .then((_) async {
          if (isIncomingRinging) {
            if (alertingCallId == call.callId) return;
            await stopAlert();
            if (token != generation) return;
            await startAlert(call, token);
          } else {
            if (alertingCallId == null) return;
            await stopAlert();
          }
        })
        .catchError((_) {});
  }

  ref.listen<AsyncValue<CallState?>>(currentCallProvider, (previous, next) {
    syncAlert(next.value);
  });

  ref.onDispose(() {
    generation++;
    unawaited(stopAlert());
    unawaited(player.dispose());
  });
});
