import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';

/// Where a call's sound comes out.
enum CallAudioRoute {
  earpiece('Phone'),
  speaker('Speaker'),
  bluetooth('Bluetooth'),
  wiredHeadset('Headset');

  const CallAudioRoute(this.label);

  /// Plain English, for the route control and its menu.
  final String label;
}

/// The Android window and service integration a call needs: shown over the
/// lock screen, kept awake, running as a foreground service so the OS lets the
/// microphone and camera carry on with the app in the background, and the
/// screen switched off against the face.
///
/// An interface so widget tests run with a fake; [NoCallPlatform] on a host
/// that has none (Windows). Every method is best effort: window flags and the
/// service are conveniences of a call, never a reason for it to fail.
abstract interface class CallPlatform {
  /// Sets the window flags that show the app over the lock screen and turn the
  /// screen on ([active]) and, for a connected call, keep it on.
  Future<void> setCallActive({
    required bool active,
    required bool keepScreenOn,
  });

  /// Whether an incoming call should take the whole screen: the phone is
  /// locked or idle, or nothing could be asked (a push woke the app).
  Future<bool> shouldUseFullScreenIncomingCall();

  /// Starts the foreground service for a call that is connecting or live.
  Future<void> startForegroundService({
    required String callId,
    required String callerName,
    required bool video,
  });

  Future<void> stopForegroundService();

  /// Turns the screen off while the phone is against the face (a voice call
  /// on the earpiece).
  Future<void> setProximityScreenOff(bool enabled);
}

/// Does nothing: the host has no such integration.
final class NoCallPlatform implements CallPlatform {
  const NoCallPlatform();

  @override
  Future<void> setCallActive({
    required bool active,
    required bool keepScreenOn,
  }) async {}

  @override
  Future<bool> shouldUseFullScreenIncomingCall() async => false;

  @override
  Future<void> startForegroundService({
    required String callId,
    required String callerName,
    required bool video,
  }) async {}

  @override
  Future<void> stopForegroundService() async {}

  @override
  Future<void> setProximityScreenOff(bool enabled) async {}
}

/// `MainActivity`'s `com.helix.remote/calls` channel.
final class AndroidCallPlatform implements CallPlatform {
  const AndroidCallPlatform();

  static const _channel = MethodChannel('com.helix.remote/calls');

  Future<T?> _call<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on Object {
      // No activity to ask, or the platform refused: the call carries on.
      return null;
    }
  }

  @override
  Future<void> setCallActive({
    required bool active,
    required bool keepScreenOn,
  }) => _call<void>('setCallActive', {
    'active': active,
    'keepScreenOn': keepScreenOn,
  });

  @override
  Future<bool> shouldUseFullScreenIncomingCall() async {
    // No answer means no activity (a push woke the process): the phone is
    // then almost always locked or idle, where a call takes the whole screen.
    return await _call<bool>('shouldUseFullScreenIncomingCall') ?? true;
  }

  @override
  Future<void> startForegroundService({
    required String callId,
    required String callerName,
    required bool video,
  }) => _call<void>('startForegroundCall', {
    'callId': callId,
    'callerDisplayName': callerName,
    'isVideo': video,
  });

  @override
  Future<void> stopForegroundService() => _call<void>('stopForegroundCall');

  @override
  Future<void> setProximityScreenOff(bool enabled) =>
      _call<void>('setProximityScreenOff', {'enabled': enabled});
}

/// The platform integration for this host.
final callPlatformProvider = Provider<CallPlatform>(
  (ref) =>
      Platform.isAndroid ? const AndroidCallPlatform() : const NoCallPlatform(),
);

/// What a permission request ended with.
enum CallPermissionResult { granted, microphoneDenied, cameraDenied }

/// The microphone and camera permission flow.
abstract interface class CallPermissions {
  /// Asks for the microphone, and the camera for a video call. Returns what
  /// was refused, if anything; a refusal is an answer, never an exception.
  Future<CallPermissionResult> ensure({required bool video});
}

final class WebRtcCallPermissions implements CallPermissions {
  const WebRtcCallPermissions();

  @override
  Future<CallPermissionResult> ensure({required bool video}) async {
    final result = await const WebRtcMediaPermissions().request(video: video);
    return switch (result) {
      WebRtcMediaPermission.granted => CallPermissionResult.granted,
      WebRtcMediaPermission.microphoneDenied =>
        CallPermissionResult.microphoneDenied,
      WebRtcMediaPermission.cameraDenied => CallPermissionResult.cameraDenied,
    };
  }
}

final callPermissionsProvider = Provider<CallPermissions>(
  (ref) => const WebRtcCallPermissions(),
);

/// Audio output selection for the call in progress.
abstract interface class CallAudioPlatform {
  /// Outputs that exist now (empty where the platform has no choice to make).
  Future<Set<CallAudioRoute>> available();

  Future<void> select(CallAudioRoute route);

  /// Fires when an output appears or goes.
  Stream<void> get changes;
}

final class WebRtcCallAudioPlatform implements CallAudioPlatform {
  const WebRtcCallAudioPlatform();

  static const _outputs = WebRtcAudioOutputs();

  static CallAudioRoute _routeOf(WebRtcAudioOutput output) => switch (output) {
    WebRtcAudioOutput.earpiece => CallAudioRoute.earpiece,
    WebRtcAudioOutput.speaker => CallAudioRoute.speaker,
    WebRtcAudioOutput.bluetooth => CallAudioRoute.bluetooth,
    WebRtcAudioOutput.wiredHeadset => CallAudioRoute.wiredHeadset,
  };

  @override
  Future<Set<CallAudioRoute>> available() async => {
    for (final output in await _outputs.available()) _routeOf(output),
  };

  @override
  Future<void> select(CallAudioRoute route) => _outputs.select(switch (route) {
    CallAudioRoute.earpiece => WebRtcAudioOutput.earpiece,
    CallAudioRoute.speaker => WebRtcAudioOutput.speaker,
    CallAudioRoute.bluetooth => WebRtcAudioOutput.bluetooth,
    CallAudioRoute.wiredHeadset => WebRtcAudioOutput.wiredHeadset,
  });

  @override
  Stream<void> get changes => _outputs.changes;
}

final callAudioPlatformProvider = Provider<CallAudioPlatform>(
  (ref) => const WebRtcCallAudioPlatform(),
);

/// Rings and vibrates for an incoming call, and stops.
///
/// On Android the ring is the incoming-call notification: its channel plays
/// the phone's ringtone and vibrates, and the same notification is what takes
/// the whole screen over a locked phone, so one thing serves the app in the
/// foreground, in the background and woken by a push. Elsewhere it is a
/// periodic system alert.
abstract interface class CallRinger {
  /// Starts ringing for [callId]; [fullScreen] lets it take the screen.
  Future<void> startIncoming({
    required String callId,
    required String callerName,
    required bool video,
    required bool fullScreen,
  });

  /// Stops ringing for [callId] (answered, declined, cancelled, timed out).
  Future<void> stop(String callId);
}

/// Rings with the platform alert, repeating until stopped. The fallback for a
/// host with no ringtone notification.
final class AlertCallRinger implements CallRinger {
  AlertCallRinger({this.interval = const Duration(seconds: 3)});

  final Duration interval;
  Timer? _timer;

  @override
  Future<void> startIncoming({
    required String callId,
    required String callerName,
    required bool video,
    required bool fullScreen,
  }) async {
    _timer?.cancel();
    unawaited(SystemSound.play(SystemSoundType.alert));
    unawaited(HapticFeedback.vibrate());
    _timer = Timer.periodic(interval, (_) {
      unawaited(SystemSound.play(SystemSoundType.alert));
      unawaited(HapticFeedback.vibrate());
    });
  }

  @override
  Future<void> stop(String callId) async {
    _timer?.cancel();
    _timer = null;
  }
}
