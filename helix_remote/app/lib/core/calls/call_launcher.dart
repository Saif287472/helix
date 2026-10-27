import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/calls/place_call.dart';
import 'package:helix_remote/core/calls/place_group_call.dart';

/// Starts a call to a person from a chat. **The conversation header's call
/// buttons read this**; it resolves to the calls feature's `placeCallProvider`
/// (the one seam every call button uses), so the header, a person's info page
/// and a call-log row all place calls the same way.
abstract interface class CallLauncher {
  /// Whether a call can be started from a chat at all.
  bool get isAvailable;

  /// Calls [peerAccount]; [video] chooses a video call. Null when the call
  /// started (the full-screen call opens by itself); otherwise one plain
  /// sentence to show the person.
  Future<String?> start({required String peerAccount, required bool video});

  /// Starts a group call in [conversation] (`group:<id>`) and rings
  /// [invite], one to three members. Null when it started, else a sentence.
  Future<String?> startGroup(
    String conversation, {
    required List<String> invite,
    required bool video,
  });
}

/// The launcher over [PlaceCall].
final class PlaceCallLauncher implements CallLauncher {
  const PlaceCallLauncher(this._place, this._placeGroup);

  final PlaceCall _place;
  final PlaceGroupCall _placeGroup;

  /// Calls can run wherever the app does: a missing relay, a network that is
  /// down or a refused microphone come back as a sentence from [start], not as
  /// a button that is missing.
  @override
  bool get isAvailable => true;

  @override
  Future<String?> start({
    required String peerAccount,
    required bool video,
  }) async {
    final outcome = await _place(peerAccount, video: video);
    if (outcome.started) return null;
    return outcome.message ?? 'The call could not be placed.';
  }

  @override
  Future<String?> startGroup(
    String conversation, {
    required List<String> invite,
    required bool video,
  }) async {
    final outcome = await _placeGroup(
      conversation,
      invite: invite,
      video: video,
    );
    if (outcome.started) return null;
    return outcome.message ?? 'The call could not be placed.';
  }
}

final callLauncherProvider = Provider<CallLauncher>(
  (ref) => PlaceCallLauncher(
    ref.watch(placeCallProvider),
    ref.watch(placeGroupCallProvider),
  ),
);
