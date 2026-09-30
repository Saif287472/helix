import 'package:flutter/widgets.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';

/// Pure presentation helpers for the 1:1 call screen: labels, the duration
/// format and the error filter. Kept free of layout so they are trivially
/// testable and shared by every call layout.

bool isIncomingRinging(RemoteCallStatus status) =>
    status.state == RemoteCallState.ringing &&
    status.direction == kCallDirectionIncoming;

bool isTerminalCallState(RemoteCallState state) => switch (state) {
  RemoteCallState.declined ||
  RemoteCallState.busy ||
  RemoteCallState.failed ||
  RemoteCallState.ended => true,
  _ => false,
};

/// Media is flowing (or is being recovered) — the timer runs.
bool isConnectedCallState(RemoteCallState state) =>
    state == RemoteCallState.active || state == RemoteCallState.reconnecting;

/// The status line shown under the peer's name.
String callStateLabel(RemoteCallState state) => switch (state) {
  RemoteCallState.preparing || RemoteCallState.dialing => 'Calling…',
  RemoteCallState.ringing => 'Ringing…',
  RemoteCallState.connecting => 'Connecting…',
  RemoteCallState.active => 'Connected',
  RemoteCallState.reconnecting => 'Reconnecting…',
  RemoteCallState.declined => 'Declined',
  RemoteCallState.busy => 'Busy',
  RemoteCallState.failed => 'Call failed',
  RemoteCallState.ended => 'Call ended',
};

/// `m:ss` under an hour, `h:mm:ss` after.
String formatCallDuration(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = safe.inHours;
  if (hours > 0) {
    final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
  return '${safe.inMinutes.toString().padLeft(2, '0')}:$seconds';
}

/// Up to two initials for the avatar, or null when the peer has no name
/// worth abbreviating (the avatar then shows a person glyph instead of
/// the "UC" of "Unknown caller").
String? callInitials(RemoteCallStatus status) {
  final name = status.peerDisplayName?.trim() ?? '';
  if (name.isEmpty) return null;
  final words = name
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  final letters = StringBuffer(words.first.characters.first);
  if (words.length > 1) letters.write(words.last.characters.first);
  return letters.toString().toUpperCase();
}

const kGenericCallError = 'The call could not be completed.';

final _exceptionShape = RegExp(
  r'(Exception|Error)\b|^Instance of|\.dart\b|#\d+\s|\bnull\b|[{}<>\[\]]|'
  r'\b(errno|stack ?trace|socket|platform|timeout ?exception)\b',
  caseSensitive: false,
);

/// A message the user can read, or null when there is nothing to say.
///
/// The service sets plain sentences, but a setup failure can still carry an
/// exception's `toString()`; that never reaches the screen verbatim.
String? friendlyCallError(String? raw) {
  final message = raw?.trim() ?? '';
  if (message.isEmpty) return null;
  if (message.length > 180 || _exceptionShape.hasMatch(message)) {
    return kGenericCallError;
  }
  return message;
}
