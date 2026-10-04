import 'package:helix_remote_engine/helix_remote_engine.dart';

/// Every sentence a call screen or a call row says, in one place.
///
/// Plain English, no exception text: the engine reports a reason code and this
/// turns it into something a person can act on.
abstract final class CallCopy {
  /// The line under the name while a call is not yet live.
  static String status(CallSnapshot call, {required bool reconnecting}) {
    if (reconnecting) return 'Reconnecting…';
    return switch (call.phase) {
      CallPhase.calling => 'Calling…',
      CallPhase.ringing =>
        call.isIncoming
            ? (call.video ? 'Incoming video call' : 'Incoming voice call')
            : 'Ringing…',
      CallPhase.connecting => 'Connecting…',
      CallPhase.active => 'Connected',
      CallPhase.ended => ended(call.end, incoming: call.isIncoming),
    };
  }

  /// Why a call ended, from this device's point of view.
  static String ended(CallEnd? end, {required bool incoming}) => switch (end) {
    CallEnd.hungUp || CallEnd.remoteHungUp || null => 'Call ended',
    CallEnd.declinedByMe => 'Call declined',
    CallEnd.declinedByPeer => 'Call declined',
    CallEnd.cancelledByMe => 'Call cancelled',
    CallEnd.cancelledByPeer => 'Missed call',
    CallEnd.unanswered => incoming ? 'Missed call' : 'No answer',
    CallEnd.busy => 'Busy: on another call',
    CallEnd.answeredElsewhere => 'Answered on another device',
    CallEnd.declinedElsewhere => 'Declined on another device',
    CallEnd.failed => 'Call failed',
    CallEnd.glare => 'Call ended',
  };

  /// A longer line for an ended call whose cause deserves explaining; null
  /// when [ended] says it all.
  static String? endedDetail(CallEnd? end) => switch (end) {
    CallEnd.failed =>
      'The call could not connect. Check your connection and try again.',
    CallEnd.busy => 'They are in another call right now.',
    CallEnd.unanswered => null,
    _ => null,
  };

  /// What went wrong starting or answering a call.
  static String failure(CallFailure failure) => switch (failure) {
    CallFailure.busy => 'You are already in a call.',
    CallFailure.blocked => 'You blocked this person. Unblock them to call.',
    CallFailure.unavailable =>
      'The call could not be placed. Check your connection and try again.',
    CallFailure.rateLimited =>
      'Too many calls in a short time. Try again in a little while.',
    CallFailure.noCall => 'There is no call to answer any more.',
    CallFailure.noMedia =>
      'The microphone or camera could not be started for this call.',
  };

  /// A refusal of the microphone or camera, with what to do about it.
  static const microphoneDenied =
      'Helix needs the microphone to make calls. Allow it in your phone\'s '
      'settings, then try again.';
  static const cameraDenied =
      'Helix needs the camera for video calls. Allow it in your phone\'s '
      'settings, or make a voice call instead.';

  /// The server has no relay, so no call can connect (never a reason to blame
  /// the person's own connection).
  static const noRelay =
      'This server has no call relay set up, so calls cannot connect. Ask the '
      'server\'s operator to set one up.';

  static const poorConnection = 'Poor connection';
  static const encrypted = 'End-to-end encrypted';

  /// The log row's direction word, for a screen reader and the detail page.
  static String directionWord(CallLogDirection direction) =>
      switch (direction) {
        CallLogDirection.incoming => 'Incoming',
        CallLogDirection.outgoing => 'Outgoing',
        CallLogDirection.missed => 'Missed',
        CallLogDirection.declined => 'Declined',
        CallLogDirection.failed => 'Failed',
        CallLogDirection.cancelled => 'Cancelled',
        CallLogDirection.noAnswer => 'No answer',
      };
}

/// How one logged call went, finer than the three words the table stores.
///
/// The list collapses these to the five the UI package draws; the detail
/// screen keeps the difference.
enum CallLogDirection {
  incoming,
  outgoing,
  missed,
  declined,
  failed,
  cancelled,
  noAnswer,
}

/// `m:ss` under an hour, `h:mm:ss` after.
String formatCallDuration(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (safe.inHours > 0) {
    final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '${safe.inHours}:$minutes:$seconds';
  }
  return '${safe.inMinutes.toString().padLeft(2, '0')}:$seconds';
}

/// A spoken form of a duration for the detail page: "1 hr 4 min 9 sec".
String spokenCallDuration(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final parts = <String>[
    if (safe.inHours > 0) '${safe.inHours} hr',
    if (safe.inMinutes.remainder(60) > 0) '${safe.inMinutes.remainder(60)} min',
    if (safe.inSeconds.remainder(60) > 0 || safe.inSeconds == 0)
      '${safe.inSeconds.remainder(60)} sec',
  ];
  return parts.join(' ');
}
