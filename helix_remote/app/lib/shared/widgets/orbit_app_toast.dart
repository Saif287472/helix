import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/router/app_router.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// A toast for a host that sits above the navigator (`MaterialApp.builder` in
/// `main.dart`): there is no Overlay above it, so the message goes into the
/// router's own navigator.
void showAppToast(
  WidgetRef ref,
  String text, {
  bool error = false,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final overlay = ref
      .read(appRouterProvider)
      .routerDelegate
      .navigatorKey
      .currentState
      ?.overlay;
  if (overlay == null || !overlay.mounted) return;
  orbit.showOrbitToast(
    overlay.context,
    text,
    overlay: overlay,
    error: error,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}
