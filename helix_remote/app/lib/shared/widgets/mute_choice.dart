import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

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

/// "Mute notifications": 8 hours, 1 week, always; and "Unmute" when
/// [offerUnmute] (some chosen chat is muted already). Shared by the chat list
/// and the conversation settings.
Future<MuteChoice?> showMuteSheet(
  BuildContext context, {
  required bool offerUnmute,
}) => showHelixBottomSheet<MuteChoice>(
  context,
  title: 'Mute notifications',
  builder: (sheetContext) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final length in MuteFor.values)
        ListTile(
          leading: const Icon(Icons.volume_off_outlined),
          title: Text(length.label),
          onTap: () => Navigator.pop(sheetContext, MuteLengthChoice(length)),
        ),
      if (offerUnmute)
        ListTile(
          leading: const Icon(Icons.volume_up_outlined),
          title: const Text('Unmute'),
          onTap: () => Navigator.pop(sheetContext, const UnmuteChoice()),
        ),
    ],
  ),
);
