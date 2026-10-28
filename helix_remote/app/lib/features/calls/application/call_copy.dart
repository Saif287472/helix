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
    CallEnd.callTimeOver => 'Call time ran out',
  };

  /// How a group call ended, from this device's point of view.
  static String groupEnded(GroupCallEnd? end) => switch (end) {
    GroupCallEnd.hungUp || null => 'Call ended',
    GroupCallEnd.declinedByMe => 'Call declined',
    GroupCallEnd.unanswered => 'No one joined',
    GroupCallEnd.everyoneLeft => 'Everyone left',
    GroupCallEnd.failed => 'Call failed',
    GroupCallEnd.callTimeOver => 'Call time ran out',
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
    // No name: this lands in a snackbar (people_rules_test).
    CallFailure.blockedByPeer =>
      "This person has blocked you. You can't message or call them.",
    CallFailure.unavailable =>
      'The call could not be placed. Check your connection and try again.',
    CallFailure.rateLimited =>
      'Too many calls in a short time. Try again in a little while.',
    CallFailure.noCall => 'There is no call to answer any more.',
    CallFailure.noMedia =>
      'The microphone or camera could not be started for this call.',
    CallFailure.noCallTime => noCallTime(video: false),
  };

  /// A Free caller whose minutes for this kind of call are used up: said
  /// before anything rings, with the two ways out (ADR-036).
  static String noCallTime({required bool video}) =>
      'You have no free ${video ? 'video' : 'voice'} minutes left. Claim '
      "today's minutes in You > Orbit Premium, or get Premium for calls "
      'without limits.';

  /// The line while a voice/video switch is under way.
  static String switching(CallSwitchStage stage, {required bool toVideo}) =>
      switch (stage) {
        CallSwitchStage.asking =>
          toVideo
              ? 'Waiting for them to agree to video…'
              : 'Switching to voice…',
        CallSwitchStage.working =>
          toVideo ? 'Switching to video…' : 'Switching to voice…',
        _ => '',
      };

  /// Why a switch did not happen.
  static String switchFailed(CallSwitchOutcome outcome) => switch (outcome) {
    CallSwitchOutcome.declined => 'They did not switch the call.',
    CallSwitchOutcome.noCallTime =>
      'No free video minutes left, so the call stays as it is.',
    CallSwitchOutcome.failed =>
      'The call could not be switched. It goes on as before.',
  };

  /// The question when the other person asks for video.
  static const switchAskTitle = 'Switch to video?';
  static String switchAskText(String name) =>
      '$name would like to turn this call into a video call.';

  /// The warning on the call screen shortly before a Free caller's time ends.
  static const callTimeEnding =
      'Call time is almost up. This call will end in about two minutes.';

  /// On the call details of someone who blocked this account, in place of
  /// the call buttons (the conversation header's sentence).
  static String blockedYou(String name) =>
      "$name has blocked you. You can't message or call them.";

  /// A refusal of the microphone or camera, with what to do about it.
  static const microphoneDenied =
      'Orbit needs the microphone to make calls. Allow it in your phone\'s '
      'settings, then try again.';
  static const screenShareRefused =
      'Your screen could not be shared. Allow it when your phone asks.';
  static const cameraDenied =
      'Orbit needs the camera for video calls. Allow it in your phone\'s '
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
