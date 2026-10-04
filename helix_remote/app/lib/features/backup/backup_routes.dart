import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/backup/presentation/backup_page.dart';
import 'package:helix_remote/features/backup/presentation/recovery_backup_page.dart';
import 'package:helix_remote/features/backup/presentation/restore_history_page.dart';
import 'package:helix_remote/features/backup/presentation/transfer_page.dart';
import 'package:helix_remote/shared/route_paths.dart';

/// The backup pages. The router adds these with one line; the paths are in
/// `RoutePaths` so Settings and sign-in can link to them without importing
/// this feature.
final List<RouteBase> backupRoutes = [
  GoRoute(
    path: RoutePaths.backup,
    builder: (context, state) => const BackupPage(),
  ),
  GoRoute(
    path: RoutePaths.backupRestore,
    builder: (context, state) => const RestoreHistoryPage(),
  ),
  GoRoute(
    path: RoutePaths.backupTransfer,
    builder: (context, state) => const TransferPage(),
  ),
  GoRoute(
    path: RoutePaths.backupRecovery,
    builder: (context, state) => const RecoveryBackupPage(),
  ),
  // The last step of signing in on a new device. The router sends people here
  // while `postSignInProvider` says so.
  GoRoute(
    path: RoutePaths.restoreAfterSignIn,
    builder: (context, state) => const RestoreHistoryPage(afterSignIn: true),
  ),
];
