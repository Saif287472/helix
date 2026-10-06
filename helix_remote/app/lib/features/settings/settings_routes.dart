import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/settings/presentation/about_page.dart';
import 'package:helix_remote/features/settings/presentation/account_page.dart';
import 'package:helix_remote/features/settings/presentation/advanced_page.dart';
import 'package:helix_remote/features/settings/presentation/blocked_page.dart';
import 'package:helix_remote/features/settings/presentation/change_password_page.dart';
import 'package:helix_remote/features/settings/presentation/chats_page.dart';
import 'package:helix_remote/features/settings/presentation/delete_account_page.dart';
import 'package:helix_remote/features/settings/presentation/legal_page.dart';
import 'package:helix_remote/features/settings/presentation/notifications_page.dart';
import 'package:helix_remote/features/settings/presentation/privacy_page.dart';
import 'package:helix_remote/features/settings/presentation/storage_page.dart';
import 'package:helix_remote/shared/route_paths.dart';

/// The settings pages, added to the router with one line. The tab itself is
/// built by the home screen; these are what its rows open.
final List<RouteBase> settingsRoutes = [
  GoRoute(
    path: RoutePaths.account,
    builder: (context, state) => const AccountPage(),
  ),
  GoRoute(
    path: RoutePaths.changePassword,
    builder: (context, state) => const ChangePasswordPage(),
  ),
  GoRoute(
    path: RoutePaths.deleteAccount,
    builder: (context, state) => const DeleteAccountPage(),
  ),
  GoRoute(
    path: RoutePaths.privacy,
    builder: (context, state) => const PrivacyPage(),
  ),
  GoRoute(
    path: RoutePaths.blocked,
    builder: (context, state) => const BlockedPage(),
  ),
  GoRoute(
    path: RoutePaths.notifications,
    builder: (context, state) => const NotificationsPage(),
  ),
  GoRoute(
    path: RoutePaths.chats,
    builder: (context, state) => const ChatsSettingsPage(),
  ),
  GoRoute(
    path: RoutePaths.storage,
    builder: (context, state) => const StoragePage(),
  ),
  GoRoute(
    path: RoutePaths.about,
    builder: (context, state) => const AboutPage(),
  ),
  GoRoute(
    path: RoutePaths.legal,
    builder: (context, state) => const LegalPage(),
  ),
  GoRoute(
    path: RoutePaths.advanced,
    builder: (context, state) => const AdvancedPage(),
  ),
];
