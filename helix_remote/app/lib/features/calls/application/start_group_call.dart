import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/calls/application/call_copy.dart';
import 'package:helix_remote/features/calls/application/group_calls_port.dart';
import 'package:helix_remote/features/calls/application/media/call_media_hub.dart';
import 'package:helix_remote/features/calls/application/media/call_media_providers.dart';
import 'package:helix_remote/features/calls/application/platform/call_platform.dart';
import 'package:helix_remote/features/calls/application/start_call.dart'
    show PlaceCallOutcome, PlaceCallStatus;
import 'package:helix_remote_engine/helix_remote_engine.dart';

/// Starts a group call in [conversation] (`group:<id>`) and invites [invite]
/// (one to three other members of the group).
typedef PlaceGroupCall =
    Future<PlaceCallOutcome> Function(
      String conversation, {
      required List<String> invite,
      required bool video,
    });

/// **The seam for the group call button**, as `startCallProvider` is for the
/// 1:1 ones: asks for the microphone (and the camera for video), then
/// `engine.groupCalls.start`. The full-screen call opens by itself.
final startGroupCallProvider = Provider<PlaceGroupCall>((ref) {
  return (
    String conversation, {
    required List<String> invite,
    required bool video,
  }) async {
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
    final GroupCallsPort port;
    try {
      port = await ref.read(groupCallsPortProvider.future);
    } on Object {
      return PlaceCallOutcome(
        PlaceCallStatus.unavailable,
        CallCopy.failure(CallFailure.unavailable),
      );
    }
    try {
      await port.start(conversation, invite: invite, video: video);
      return const PlaceCallOutcome(PlaceCallStatus.started);
    } on ArgumentError {
      return const PlaceCallOutcome(
        PlaceCallStatus.unavailable,
        'A group call needs two to four people from this group.',
      );
    } on CallFailedException catch (e) {
      final noRelay =
          e.reason == CallFailure.noMedia &&
          ref.read(callMediaHubProvider).lastProblem ==
              CallMediaProblem.noRelay;
      if (noRelay) {
        return const PlaceCallOutcome(
          PlaceCallStatus.noRelay,
          CallCopy.noRelay,
        );
      }
      final status = switch (e.reason) {
        CallFailure.busy => PlaceCallStatus.busy,
        CallFailure.blocked => PlaceCallStatus.blocked,
        CallFailure.blockedByPeer => PlaceCallStatus.blockedByPeer,
        CallFailure.rateLimited => PlaceCallStatus.rateLimited,
        _ => PlaceCallStatus.unavailable,
      };
      return PlaceCallOutcome(status, CallCopy.failure(e.reason));
    }
  };
});
