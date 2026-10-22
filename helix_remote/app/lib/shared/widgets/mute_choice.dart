/// The mute lengths the app offers, and what the mute sheet answered. The
/// sheet itself is drawn by the Orbit screens.
library;

/// How long a chat stays muted.
enum MuteFor {
  eightHours('8 hours', Duration(hours: 8)),
  oneWeek('1 week', Duration(days: 7)),
  always('Always', null);

  const MuteFor(this.label, this.duration);

  final String label;

  /// Null means until the person unmutes it.
  final Duration? duration;

  /// The time a chat muted for this long is muted until, from [now]. Muting
  /// is a time in the database, so "always" is a time too (far ahead), rather
  /// than a second flag.
  DateTime until(DateTime now) =>
      duration == null ? mutedForever : now.add(duration!);
}

/// The far future a chat muted "always" is muted until.
final DateTime mutedForever = DateTime.utc(9999);

/// What the mute sheet answered: how long, or "unmute".
sealed class MuteChoice {
  const MuteChoice();
}

final class MuteLengthChoice extends MuteChoice {
  const MuteLengthChoice(this.length);
  final MuteFor length;
}

final class UnmuteChoice extends MuteChoice {
  const UnmuteChoice();
}
