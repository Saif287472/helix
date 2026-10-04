import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/people/name_lookup.dart';
import 'package:helix_remote/features/calls/application/call_audio.dart';
import 'package:helix_remote/features/calls/application/call_copy.dart';
import 'package:helix_remote/features/calls/application/call_screen_state.dart';
import 'package:helix_remote/features/calls/application/calls_port.dart';
import 'package:helix_remote/features/calls/application/media/call_media_hub.dart';
import 'package:helix_remote/features/calls/application/media/call_media_providers.dart';
import 'package:helix_remote/features/calls/application/platform/call_platform.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';

/// The wall clock the call screens read (the timer, the log's day labels).
/// Overridden in tests.
final callClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// A one-line message for the call on screen: a permission refused, an answer
/// that failed. Keyed by call id so one call's notice never shows on the next.
final callNoticeProvider = NotifierProvider<CallNotice, (String, String)?>(
  CallNotice.new,
);

final class CallNotice extends Notifier<(String, String)?> {
  @override
  (String, String)? build() => null;

  void show(String callId, String text) => state = (callId, text);

  void clear() => state = null;
}

/// An answer or hang-up that is in flight, by call id.
final callBusyProvider = NotifierProvider<CallBusy, String?>(CallBusy.new);

final class CallBusy extends Notifier<String?> {
  @override
  String? build() => null;

  // ignore: use_setters_to_change_properties
  void set(String? callId) => state = callId;
}

/// Whether the call screen is on the navigation stack, so the call host does
/// not push a second one.
final callScreenOpenProvider = NotifierProvider<CallScreenOpen, bool>(
  CallScreenOpen.new,
);

final class CallScreenOpen extends Notifier<bool> {
  @override
  bool build() => false;

  void set({required bool open}) {
    // The screen can outlive the scope at shutdown.
    if (ref.mounted) state = open;
  }
}

/// What the call screen draws, or null when there is no call.
final callScreenStateProvider = Provider<CallScreenState?>((ref) {
  final call = ref.watch(currentCallProvider).value;
  if (call == null) return null;
  final names = ref.watch(peopleNamesProvider).value ?? PeopleNames.empty;
  final media = ref.watch(callMediaInfoProvider).value;
  final audio = ref.watch(callAudioProvider);
  final notice = ref.watch(callNoticeProvider);
  final busy = ref.watch(callBusyProvider);
  return CallScreenState.from(
    call: call,
    names: names.of(call.peer),
    media: media,
    audio: audio,
    notice: notice != null && notice.$1 == call.callId ? notice.$2 : null,
    busy: busy == call.callId,
  );
});

/// How long the connected call has run, ticking once a second; frozen on an
/// ended call; null before it connected.
final callElapsedProvider = StreamProvider<Duration?>((ref) {
  // Everything is read before the first value: a generator body would run
  // after the provider could already have been rebuilt.
  final answeredAt = ref.watch(
    callScreenStateProvider.select((state) => state?.answeredAt),
  );
  final frozen = ref.watch(
    callScreenStateProvider.select((state) => state?.talkTime),
  );
  final clock = ref.watch(callClockProvider);
  final live = ref.watch(
    callScreenStateProvider.select((state) => state?.isLive ?? false),
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

/// The things a person does on the call screen.
final callActionsProvider = Provider<CallActions>(CallActions.new);

final class CallActions {
  CallActions(this._ref);

  final Ref _ref;

  CallScreenState? get _state => _ref.read(callScreenStateProvider);

  Future<CallsPort> get _port => _ref.read(callsPortProvider.future);

  /// Answers the ringing call: asks for the microphone (and the camera for a
  /// video call) first, and keeps ringing if it is refused, with a line that
  /// says what to do.
  Future<void> accept() async {
    final call = _state;
    if (call == null || call.stage != CallStage.incoming || call.busy) return;
    final notice = _ref.read(callNoticeProvider.notifier);
    final busy = _ref.read(callBusyProvider.notifier);
    notice.clear();
    busy.set(call.callId);
    try {
      final result = await _ref
          .read(callPermissionsProvider)
          .ensure(video: call.video);
      if (result != CallPermissionResult.granted) {
        notice.show(call.callId, _permissionText(result));
        return;
      }
      await (await _port).accept();
    } on CallFailedException catch (e) {
      notice.show(call.callId, _failureText(e.reason));
    } finally {
      busy.set(null);
    }
  }

  /// Declines the ringing call.
  Future<void> decline() async {
    final call = _state;
    if (call == null || call.stage != CallStage.incoming) return;
    await _guard(call, (port) => port.decline());
  }

  /// Ends the call: cancels one nobody answered, hangs up a live one.
  Future<void> hangUp() async {
    final call = _state;
    if (call == null || !call.isLive) return;
    await _guard(call, (port) => port.hangUp());
  }

  Future<void> setMuted({required bool muted}) async {
    if (_state?.hasControls != true) return;
    await _guard(_state!, (port) => port.setMuted(muted: muted), busy: false);
  }

  Future<void> setCameraEnabled({required bool enabled}) async {
    final call = _state;
    if (call == null || !call.video || !call.hasControls) return;
    await _guard(
      call,
      (port) => port.setCameraEnabled(enabled: enabled),
      busy: false,
    );
  }

  Future<void> switchCamera() async {
    final call = _state;
    if (call == null || !call.video || !call.cameraOn) return;
    await _ref.read(callMediaHubProvider).switchCamera();
  }

  Future<void> selectRoute(CallAudioRoute route) =>
      _ref.read(callAudioProvider.notifier).select(route);

  /// Hides the notice (the person read it).
  void dismissNotice() => _ref.read(callNoticeProvider.notifier).clear();

  Future<void> _guard(
    CallScreenState call,
    Future<void> Function(CallsPort port) action, {
    bool busy = true,
  }) async {
    final flag = _ref.read(callBusyProvider.notifier);
    if (busy) flag.set(call.callId);
    try {
      await action(await _port);
    } on CallFailedException catch (e) {
      _ref
          .read(callNoticeProvider.notifier)
          .show(call.callId, _failureText(e.reason));
    } finally {
      if (busy) flag.set(null);
    }
  }

  String _failureText(CallFailure reason) {
    if (reason == CallFailure.noMedia &&
        _ref.read(callMediaHubProvider).lastProblem ==
            CallMediaProblem.noRelay) {
      return CallCopy.noRelay;
    }
    return CallCopy.failure(reason);
  }

  static String _permissionText(CallPermissionResult result) =>
      result == CallPermissionResult.cameraDenied
      ? CallCopy.cameraDenied
      : CallCopy.microphoneDenied;
}
