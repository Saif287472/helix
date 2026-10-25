import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// A console view that opens over the place it was called from instead of on a
/// page of its own: the live log, and one account's details.
///
/// It covers [heightFactor] of the screen and no more. A sheet that fills the
/// phone leaves only a drag handle to get back with; leaving the place behind
/// visible keeps its own controls reachable, so an operator can see what they
/// are returning to.
///
/// A sheet is a route like a page, so ending the admin session closes it with
/// everything else above the shell (`app.dart`).
Future<T?> showConsoleSheet<T>({
  required BuildContext context,
  required Widget child,
  double heightFactor = 0.68,
  double maxWidth = 720,
}) {
  // Its height is set in the body, not on the route: an open keyboard lifts the
  // sheet above it, and the room left is only known there. The drag-handle band
  // (48 px, with no route cap to make room for it) counts inside that height,
  // so the share the operator sees is always `heightFactor` of the screen.
  final height = MediaQuery.sizeOf(context).height * heightFactor;
  return showModalBottomSheet<T>(
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
    builder: (sheet) {
      final keyboard = MediaQuery.viewInsetsOf(sheet).bottom;
      final room = MediaQuery.sizeOf(sheet).height - keyboard;
      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SizedBox(
          height: math.min(height, room) - _dragHandleBand,
          child: ScaffoldMessenger(
            // The sheet is drawn over the shell's Scaffold, and it covers the
            // bottom of the screen where that Scaffold shows a short line - so
            // a sheet that reports a problem carries a messenger and a Scaffold
            // of its own.
            child: Scaffold(
              // Only the padding above lifts it; a second squeeze would take
              // the room twice and leave the view too short for its own header.
              resizeToAvoidBottomInset: false,
              backgroundColor: HelixConsoleColors.surface,
              body: child,
            ),
          ),
        ),
      );
    },
  );
}

/// The band the bottom sheet puts its drag handle in, inside its own height.
const _dragHandleBand = 48.0;
