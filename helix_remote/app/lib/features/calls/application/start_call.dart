import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/calls/application/call_copy.dart';
import 'package:helix_remote/features/calls/application/calls_port.dart';
import 'package:helix_remote/features/calls/application/media/call_media_hub.dart';
import 'package:helix_remote/features/calls/application/media/call_media_providers.dart';
import 'package:helix_remote/features/calls/application/platform/call_platform.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';

/// How asking for a call turned out.
enum PlaceCallStatus {
  /// The offer went out. The call screen opens by itself (the app's call host
  /// follows the engine's call state), so a caller does nothing more.
  started,
  microphoneDenied,
  cameraDenied,
  busy,
  blocked,
  rateLimited,

  /// The server has no call relay, so no call can connect.
  noRelay,

  /// No network, a server that is down, or no runtime yet.
  unavailable,
}

/// The answer to [PlaceCall]: whether the call started and, if not, one plain
/// sentence a screen can show as is.
final class PlaceCallOutcome {
  const PlaceCallOutcome(this.status, [this.message]);

  final PlaceCallStatus status;

  /// What went wrong, in plain English; null when [started].
  final String? message;

  bool get started => status == PlaceCallStatus.started;
}

/// Places a 1:1 call to [peerAccountId] (an account id, bare uuid or
/// `uuid@domain`): asks for the microphone (and the camera when [video]), then
/// `engine.calls.startCall`.
typedef PlaceCall =
    Future<PlaceCallOutcome> Function(
      String peerAccountId, {
      required bool video,
    });

/// **The seam for every call button.**
///
/// A feature that offers a call - the conversation header (A2a), a person's
/// info page (A2b), a call-log row - must not import `features/calls`
/// (features never import each other). Its `application/` layer reads
/// `placeCallProvider` from `core/calls/place_call.dart`, which resolves to
/// this, and passes the outcome's message to the screen when `!started`:
///
/// ```dart
/// final outcome = await ref.read(placeCallProvider)(peer, video: false);
/// if (!outcome.started) showSnackBar(outcome.message!);
/// ```
///
/// Tests override it with a fake and assert the call.
final startCallProvider = Provider<PlaceCall>((ref) {
  return (String peerAccountId, {required bool video}) async {
    final permission = await ref
        .read(callPermissionsProvider)
        .ensure(video: video);
    switch (permission) {
      case CallPermissionResult.microphoneDenied:
        return const PlaceCallOutcome(
          PlaceCallStatus.microphoneDenied,
          CallCopy.microphoneDenied,
        );
      case CallPermissionResult.cameraDenied:
        return const PlaceCallOutcome(
          PlaceCallStatus.cameraDenied,
          CallCopy.cameraDenied,
        );
      case CallPermissionResult.granted:
        break;
    }
    final CallsPort port;
    try {
      port = await ref.read(callsPortProvider.future);
    } on Object {
      return PlaceCallOutcome(
        PlaceCallStatus.unavailable,
        CallCopy.failure(CallFailure.unavailable),
      );
    }
    try {
      await port.startCall(peerAccountId, video: video);
      return const PlaceCallOutcome(PlaceCallStatus.started);
    } on CallFailedException catch (e) {
      return _outcomeOf(e.reason, ref.read(callMediaHubProvider).lastProblem);
    }
  };
});

PlaceCallOutcome _outcomeOf(CallFailure reason, CallMediaProblem? problem) {
  if (reason == CallFailure.noMedia && problem == CallMediaProblem.noRelay) {
    return const PlaceCallOutcome(PlaceCallStatus.noRelay, CallCopy.noRelay);
  }
  final status = switch (reason) {
    CallFailure.busy => PlaceCallStatus.busy,
    CallFailure.blocked => PlaceCallStatus.blocked,
    CallFailure.rateLimited => PlaceCallStatus.rateLimited,
    CallFailure.noMedia ||
    CallFailure.unavailable ||
    CallFailure.noCall => PlaceCallStatus.unavailable,
  };
  return PlaceCallOutcome(status, CallCopy.failure(reason));
}
