import 'package:flutter/material.dart';
import 'package:helix_remote/screens/setup/setup_screen.dart';

/// Stable names for navigation that crosses feature boundaries.
abstract final class RemoteRoutes {
  static const setup = '/setup';
}

/// Kept outside bootstrap and feature widgets so route construction has one
/// owner.
abstract final class RemoteRouter {
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    return switch (settings.name) {
      RemoteRoutes.setup => MaterialPageRoute<Object?>(
        settings: settings,
        builder: (_) => const SetupScreen(),
      ),
      _ => null,
    };
  }
}
