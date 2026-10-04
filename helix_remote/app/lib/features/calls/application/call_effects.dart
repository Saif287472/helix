import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/notifications/call_notifications.dart';
import 'package:helix_remote/core/people/name_lookup.dart';
import 'package:helix_remote/core/security/app_lock.dart';
import 'package:helix_remote/features/calls/application/call_audio.dart';
import 'package:helix_remote/features/calls/application/call_controller.dart';
import 'package:helix_remote/features/calls/application/call_screen_state.dart';
import 'package:helix_remote/features/calls/application/calls_port.dart';
import 'package:helix_remote/features/calls/application/platform/call_platform.dart';
import 'package:helix_remote/features/calls/application/platform/notification_call_ringer.dart';

/// What the phone does around a call, apart from drawing it: rings, takes the
/// screen over the lock screen, runs the foreground service, routes the sound,
/// switches the screen off against the face, and keeps the app lock out of the
/// way of a live call.
///
/// One class driven by the call screen state's changes, so every side effect
/// is a function of "which stage did the call move to", and tests assert them
/// with fakes for the platform and the ringer.
final class CallEffects {
  CallEffects({
    required this.platform,
    required this.ringer,
    required this.audio,
    required this.setLockBypass,
  });

  final CallPlatform platform;
  final CallRinger ringer;
  final CallAudioController audio;

  /// Lets a live call through the app lock (`AppLock.callInProgress`).
  final void Function({required bool value}) setLockBypass;

  String? _ringingFor;
  String? _serviceFor;
  bool _proximity = false;

  /// Runs the effects of the call moving from [previous] to [next].
  Future<void> onChange(
    CallScreenState? previous,
    CallScreenState? next,
  ) async {
    if (next == null) {
      await _finish(previous);
      return;
    }
    final isNew = previous == null || previous.callId != next.callId;
    if (isNew) {
      if (previous != null) await _finish(previous);
      setLockBypass(value: true);
      await platform.setCallActive(active: true, keepScreenOn: false);
    }
    switch (next.stage) {
      case CallStage.incoming:
        if (_ringingFor != next.callId) {
          _ringingFor = next.callId;
          await ringer.startIncoming(
            callId: next.callId,
            callerName: next.title,
            video: next.video,
            fullScreen: await platform.shouldUseFullScreenIncomingCall(),
          );
        }
      case CallStage.dialing:
      case CallStage.connecting:
      case CallStage.active:
        await _stopRinging(next.callId);
        await _startService(next);
        if (next.stage != CallStage.dialing) {
          await audio.begin(video: next.video);
        }
        if (next.stage == CallStage.active &&
            (previous == null || previous.stage != CallStage.active)) {
          await platform.setCallActive(active: true, keepScreenOn: next.video);
        }
        await _syncProximity(next);
      case CallStage.ended:
        await _stopRinging(next.callId);
        await _stopService();
        await _setProximity(false);
        audio.end();
    }
  }

  Future<void> _finish(CallScreenState? previous) async {
    if (previous != null) await _stopRinging(previous.callId);
    _ringingFor = null;
    await _stopService();
    await _setProximity(false);
    audio.end();
    await platform.setCallActive(active: false, keepScreenOn: false);
    setLockBypass(value: false);
  }

  Future<void> _stopRinging(String callId) async {
    if (_ringingFor != callId) return;
    _ringingFor = null;
    await ringer.stop(callId);
  }

  Future<void> _startService(CallScreenState call) async {
    if (_serviceFor == call.callId) return;
    _serviceFor = call.callId;
    await platform.startForegroundService(
      callId: call.callId,
      callerName: call.title,
      video: call.video,
    );
  }

  Future<void> _stopService() async {
    if (_serviceFor == null) return;
    _serviceFor = null;
    await platform.stopForegroundService();
  }

  /// A voice call held to the ear turns the screen off.
  Future<void> _syncProximity(CallScreenState call) => _setProximity(
    call.stage == CallStage.active &&
        !call.video &&
        call.audio.route == CallAudioRoute.earpiece,
  );

  /// Called when only the audio route changed.
  Future<void> onRouteChanged(CallScreenState? call) async {
    if (call == null || !call.isLive) return;
    await _syncProximity(call);
  }

  Future<void> _setProximity(bool enabled) async {
    if (_proximity == enabled) return;
    _proximity = enabled;
    await platform.setProximityScreenOff(enabled);
  }
}

/// Wires [CallEffects] to the call state. Read once, high in the tree (the
/// call host), so the effects run for as long as the app does.
final callEffectsProvider = Provider<CallEffects>((ref) {
  final effects = CallEffects(
    platform: ref.watch(callPlatformProvider),
    ringer: ref.watch(callRingerProvider),
    audio: ref.read(callAudioProvider.notifier),
    setLockBypass: ({required value}) => AppLock.callInProgress.value = value,
  );
  ref.listen<CallScreenState?>(callScreenStateProvider, (previous, next) {
    // Only the changes that decide an effect: not every tick of the notice.
    if (previous?.callId == next?.callId &&
        previous?.stage == next?.stage &&
        previous?.video == next?.video) {
      if (previous?.audio.route != next?.audio.route) {
        unawaited(effects.onRouteChanged(next));
      }
      return;
    }
    unawaited(effects.onChange(previous, next));
  }, fireImmediately: true);
  return effects;
});

/// What a person pressed on a call notification, before the call was known.
///
/// A button on the notification opens the app, which may not have the offer
/// yet (a push woke it; the call is opened over REST a moment later). The press
/// is remembered and applied when that call rings, for as long as the call
/// itself could be ringing.
final class PendingCallDecision {
  const PendingCallDecision(this.callId, this.action, this.at);

  final String callId;
  final CallNotificationAction action;
  final DateTime at;
}

/// Presses on call notifications. Overridden in tests.
final callNotificationResponsesProvider =
    Provider<Stream<CallNotificationResponse>>(
      (ref) => CallNotifications.responses,
    );

/// The press that cold-started the app, if a call notification did.
final callLaunchResponseProvider = Provider<Future<CallNotificationResponse?>>(
  (ref) => CallNotifications.launchedBy(),
);

/// Applies Answer and Decline pressed on a notification, and raises "Missed
/// call" for a call that rang while the app was not on screen.
final callNotificationHandlerProvider = Provider<CallNotificationHandler>((
  ref,
) {
  final handler = CallNotificationHandler(ref);
  ref.onDispose(handler.dispose);
  handler.start();
  return handler;
});

final class CallNotificationHandler {
  CallNotificationHandler(this._ref);

  final Ref _ref;
  PendingCallDecision? _pending;
  StreamSubscription<CallNotificationResponse>? _responses;
  StreamSubscription<Object?>? _missed;
  ProviderSubscription<CallScreenState?>? _calls;

  void start() {
    _responses = _ref
        .read(callNotificationResponsesProvider)
        .listen(onResponse);
    unawaited(
      _ref.read(callLaunchResponseProvider).then((response) {
        if (response != null) onResponse(response);
      }),
    );
    _calls = _ref.listen<CallScreenState?>(callScreenStateProvider, (_, next) {
      if (next != null) unawaited(_applyPending(next));
    });
    unawaited(_listenMissed());
  }

  Future<void> _listenMissed() async {
    try {
      final port = await _ref.read(callsPortProvider.future);
      _missed = port.missedCalls.listen((event) {
        final lifecycle = WidgetsBinding.instance.lifecycleState;
        if (lifecycle == AppLifecycleState.resumed) return;
        final names = _ref.read(peopleNamesProvider).value ?? PeopleNames.empty;
        unawaited(
          CallNotifications.showMissed(
            callId: event.notice.messageId,
            callerName: names.displayName(event.notice.sender),
          ),
        );
      });
    } on Object {
      // No runtime (signed out): nothing rings, so nothing is missed.
    }
  }

  void dispose() {
    _responses?.cancel();
    _missed?.cancel();
    _calls?.close();
  }

  /// A press on a call notification.
  void onResponse(CallNotificationResponse response) {
    if (response.action == CallNotificationAction.open) return;
    final now = _ref.read(callClockProvider)();
    _pending = PendingCallDecision(response.callId, response.action, now);
    final state = _ref.read(callScreenStateProvider);
    if (state != null) unawaited(_applyPending(state));
  }

  Future<void> _applyPending(CallScreenState state) async {
    final pending = _pending;
    if (pending == null || pending.callId != state.callId) return;
    if (state.stage != CallStage.incoming) return;
    final age = _ref.read(callClockProvider)().difference(pending.at);
    _pending = null;
    if (age > CallNotifications.ringFor) return;
    final actions = _ref.read(callActionsProvider);
    switch (pending.action) {
      case CallNotificationAction.accept:
        await actions.accept();
      case CallNotificationAction.decline:
        await actions.decline();
      case CallNotificationAction.open:
        break;
    }
  }
}
