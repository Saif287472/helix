import 'package:flutter/material.dart';
import 'package:helix_remote/screens/server_choice_screen.dart';
import 'package:helix_remote/screens/setup/setup_screen.dart';

/// Stable names for navigation that crosses feature boundaries.
abstract final class RemoteRoutes {
  static const serverChoice = '/server-choice';
  static const setup = '/setup';
}

/// Kept outside bootstrap and feature widgets so route construction has one
/// owner. Feature-specific routes can be added here as their view models are
/// migrated in Phase 3.
abstract final class RemoteRouter {
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    return switch (settings.name) {
      RemoteRoutes.serverChoice => MaterialPageRoute<Object?>(
        settings: settings,
        builder: (_) => const ServerChoiceScreen(),
      ),
      RemoteRoutes.setup => MaterialPageRoute<Object?>(
        settings: settings,
        builder: (_) => const SetupScreen(),
      ),
      _ => null,
    };
  }
}
