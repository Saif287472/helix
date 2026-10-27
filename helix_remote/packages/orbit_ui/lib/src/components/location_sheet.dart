import 'dart:async';

import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/overlays.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';

/// The Location choice from the attach sheet: send where you are once, or keep
/// sharing it for 15 minutes, an hour or 8 hours. [onShare] is given how long
/// to keep sharing (null for once) and answers with the sentence to show when
/// it could not be done, or null. The sheet says plainly that the people in
/// the chat see where you are until it ends, and that you can stop sooner.
Future<void> showOrbitLocationSheet(
  BuildContext context, {
  required FutureOr<String?> Function(Duration? live) onShare,
}) {
  void share(Duration? live) {
    unawaited(() async {
      final error = await onShare(live);
      if (error != null && context.mounted) {
        showOrbitToast(context, error, error: true);
      }
    }());
  }

  return showOrbitSheet(
    context,
    title: 'Share location',
    text:
        'Only the people in this chat can see it, and only while it is '
        'shared. Live sharing ends by itself, or when you tap Stop sharing.',
    items: [
      OrbitMenuItem(
        icon: OrbitIcons.mapPin,
        label: 'Send current location',
        sub: 'Once, where you are now',
        onTap: () => share(null),
      ),
      OrbitMenuItem.divider,
      OrbitMenuItem(
        icon: OrbitIcons.clock,
        label: 'Share live for 15 minutes',
        onTap: () => share(const Duration(minutes: 15)),
      ),
      OrbitMenuItem(
        icon: OrbitIcons.clock,
        label: 'Share live for 1 hour',
        onTap: () => share(const Duration(hours: 1)),
      ),
      OrbitMenuItem(
        icon: OrbitIcons.clock,
        label: 'Share live for 8 hours',
        onTap: () => share(const Duration(hours: 8)),
      ),
    ],
  );
}
