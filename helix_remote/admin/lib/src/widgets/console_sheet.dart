import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// A console view that opens over the place it was called from instead of on a
/// page of its own: the live log, and one account's details.
///
/// A sheet is a route like a page, so ending the admin session closes it with
/// everything else above the shell (`app.dart`).
Future<T?> showConsoleSheet<T>({
  required BuildContext context,
  required Widget child,
  double heightFactor = 0.8,
  double maxWidth = 720,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: HelixConsoleColors.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    side: BorderSide(color: HelixConsoleColors.border),
  ),
  // On a wide window the sheet stays a centred column, not a full-width band.
  constraints: BoxConstraints(maxWidth: maxWidth),
  builder: (_) => ScaffoldMessenger(
    // The sheet is drawn over the shell's Scaffold, and it covers the bottom
    // of the screen where that Scaffold shows a short line - so a sheet that
    // reports a problem carries a messenger and a Scaffold of its own.
    child: Scaffold(
      backgroundColor: HelixConsoleColors.surface,
      body: SizedBox(
        height: MediaQuery.sizeOf(context).height * heightFactor,
        child: child,
      ),
    ),
  ),
);
