// lib/ui/app_router.dart
import 'package:flutter/material.dart';
import 'package:helix/ui/screens/setup/setup_screen.dart';
import 'package:helix/ui/screens/home/home_screen.dart';
import 'package:helix/ui/screens/chat/chat_screen.dart';
import 'package:helix/ui/screens/diagnostics/diagnostics_screen.dart';
import 'package:helix/ui/screens/settings/settings_screen.dart';
import 'package:helix/ui/screens/qr/qr_share_screen.dart';
import 'package:helix/ui/screens/qr/qr_scan_screen.dart';
import 'package:helix/ui/screens/home/group_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String setup = '/setup';
  static const String home = '/home';
  static const String chat = '/chat';
  static const String group = '/group';
  static const String diagnostics = '/diagnostics';
  static const String settings = '/settings';
  static const String qrShare = '/qr-share';
  static const String qrScan = '/qr-scan';
}

class AppRouter {
  AppRouter._();

  static final navigatorKey = GlobalKey<NavigatorState>();

  static Route<dynamic> generateRoute(RouteSettings settings) {
    final name = settings.name ?? '/';
    final args = settings.arguments;

    if (name == AppRoutes.setup) {
      return _fade(const SetupScreen(), settings);
    }

    if (name == AppRoutes.home) {
      return _fade(const HomeScreen(), settings);
    }

    if (name.startsWith('${AppRoutes.chat}/') || name == AppRoutes.chat) {
      // Extract threadId from path segment or from arguments map
      String? threadId;
      if (name.startsWith('${AppRoutes.chat}/')) {
        threadId = name.substring(AppRoutes.chat.length + 1);
      } else if (args is Map<String, dynamic>) {
        threadId = args['threadId'] as String?;
      } else if (args is String) {
        threadId = args;
      }
      if (threadId == null || threadId.isEmpty) {
        return _error('Chat requires a thread ID.', settings);
      }
      return _slide(ChatScreen(threadId: threadId), settings);
    }

    if (name.startsWith('${AppRoutes.group}/') || name == AppRoutes.group) {
      String? groupId;
      if (name.startsWith('${AppRoutes.group}/')) {
        groupId = name.substring(AppRoutes.group.length + 1);
      } else if (args is String) {
        groupId = args;
      }
      if (groupId == null || groupId.isEmpty) {
        return _error('Group requires a group ID.', settings);
      }
      return _slide(GroupScreen(groupId: groupId), settings);
    }

    if (name == AppRoutes.diagnostics) {
      return _slide(const DiagnosticsScreen(), settings);
    }

    if (name == AppRoutes.settings) {
      return _slide(
        Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: const SettingsScreen(),
        ),
        settings,
      );
    }

    if (name == AppRoutes.qrShare) {
      return _slide(const QrShareScreen(), settings);
    }

    if (name == AppRoutes.qrScan) {
      return _slide(const QrScanScreen(), settings);
    }

    // Root: caller decides based on first-run state using initialRoute
    return _fade(const HomeScreen(), settings);
  }

  // ---------------------------------------------------------------------------
  // Transition helpers
  // ---------------------------------------------------------------------------

  static PageRoute<T> _fade<T>(Widget page, RouteSettings routeSettings) {
    return PageRouteBuilder<T>(
      settings: routeSettings,
      pageBuilder: (context, anim, secondaryAnim) => page,
      transitionsBuilder: (context, animation, secondaryAnim, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 220),
    );
  }

  static PageRoute<T> _slide<T>(Widget page, RouteSettings routeSettings) {
    return PageRouteBuilder<T>(
      settings: routeSettings,
      pageBuilder: (context, anim, secondaryAnim) => page,
      transitionsBuilder: (context, animation, secondaryAnim, child) {
        final tween = Tween(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
      transitionDuration: const Duration(milliseconds: 280),
    );
  }

  static PageRoute<T> _error<T>(String message, RouteSettings settings) {
    return MaterialPageRoute<T>(
      settings: settings,
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Navigation Error')),
        body: Center(child: Text(message)),
      ),
    );
  }
}
