import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Opens a sheet of choices and returns the one picked, wrapped in a record so
/// that picking a `null` value ("Off") is not mistaken for dismissing the
/// sheet. Null means dismissed.
///
/// [options] pairs each value with its label. The current one is ticked. Used
/// for every "pick one of a few" row in Settings so they all look and behave
/// the same, and each row is a full-width, 56 px target.
Future<({T value})?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T value, String label)> options,
  required T selected,
}) => showHelixBottomSheet<({T value})>(
  context,
  title: title,
  builder: (sheetContext) => Column(
    children: [
      for (final (value, label) in options)
        HelixSettingsTile(
          title: label,
          trailing: value == selected
              ? Icon(
                  Icons.check,
                  semanticLabel: 'Selected',
                  color: Theme.of(sheetContext).colorScheme.primary,
                )
              : null,
          onTap: () => Navigator.pop(sheetContext, (value: value)),
        ),
    ],
  ),
);
