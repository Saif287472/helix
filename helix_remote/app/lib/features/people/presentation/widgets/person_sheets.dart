import 'package:flutter/material.dart';
import 'package:helix_remote/features/people/application/contact_info.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// How long to mute a chat for: null when the sheet is dismissed.
Future<MuteFor?> showMuteSheet(BuildContext context) =>
    showHelixBottomSheet<MuteFor>(
      context,
      title: 'Mute notifications',
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in MuteFor.values)
            HelixSettingsTile(
              title: option.label,
              onTap: () => Navigator.pop(context, option),
            ),
        ],
      ),
    );

/// The disappearing-message timers; the current one is ticked. Null when the
/// sheet is dismissed.
Future<DisappearAfter?> showDisappearingSheet(
  BuildContext context, {
  required DisappearAfter selected,
}) => showHelixBottomSheet<DisappearAfter>(
  context,
  title: 'Disappearing messages',
  builder: (context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(
          HelixSpace.md,
          0,
          HelixSpace.md,
          HelixSpace.xs,
        ),
        child: Text(
          'New messages in this chat are deleted from both phones after the '
          'time you choose. Messages already sent are not changed.',
        ),
      ),
      for (final option in DisappearAfter.values)
        HelixSettingsTile(
          title: option.label,
          trailing: option == selected ? const Icon(Icons.check) : null,
          onTap: () => Navigator.pop(context, option),
        ),
    ],
  ),
);

/// Asks why, then for an optional note, and confirms before anything is sent.
/// Null when cancelled.
Future<PersonReport?> showReportSheet(
  BuildContext context, {
  required String name,
}) async {
  final reason = await showHelixBottomSheet<ReportReason>(
    context,
    title: 'Report $name',
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            HelixSpace.md,
            0,
            HelixSpace.md,
            HelixSpace.xs,
          ),
          child: Text(
            'Why are you reporting this person? Helix\'s operators are told '
            'about the account. No messages are sent with the report.',
          ),
        ),
        for (final option in ReportReason.values)
          HelixSettingsTile(
            title: option.label,
            onTap: () => Navigator.pop(context, option),
          ),
      ],
    ),
  );
  if (reason == null || !context.mounted) return null;
  final note = await showHelixTextInputDialog(
    context,
    title: 'Add a note (optional)',
    label: 'What happened?',
    confirmLabel: 'Report',
    maxLength: 500,
  );
  if (note == null) return null;
  return PersonReport(reason: reason, note: note.isEmpty ? null : note);
}
