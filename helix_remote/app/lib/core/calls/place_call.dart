import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/calls/application/start_call.dart';

export 'package:helix_remote/features/calls/application/start_call.dart'
    show PlaceCall, PlaceCallOutcome, PlaceCallStatus;

/// Places a 1:1 call. The seam every call button reads.
///
/// A feature that offers a call (the conversation header, a person's info
/// page) must not import `features/calls`, but it may import this from its own
/// `application/` layer: it resolves to the calls feature's implementation
/// (`startCallProvider`) and tests override it.
///
/// ```dart
/// final outcome = await ref.read(placeCallProvider)(peer, video: true);
/// if (!outcome.started) { /* show outcome.message */ }
/// ```
final placeCallProvider = Provider<PlaceCall>(
  (ref) => ref.watch(startCallProvider),
);
