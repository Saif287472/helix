import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/calls/application/start_group_call.dart';

export 'package:helix_remote/features/calls/application/start_call.dart'
    show PlaceCallOutcome, PlaceCallStatus;
export 'package:helix_remote/features/calls/application/start_group_call.dart'
    show PlaceGroupCall;

/// Starts a group call: the seam the group chat's call button reads, as
/// `placeCallProvider` is for 1:1 calls. Tests override it.
final placeGroupCallProvider = Provider<PlaceGroupCall>(
  (ref) => ref.watch(startGroupCallProvider),
);
