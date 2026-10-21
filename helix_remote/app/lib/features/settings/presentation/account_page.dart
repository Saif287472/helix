import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/settings/application/account_providers.dart';
import 'package:helix_remote/features/settings/application/settings_providers.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:helix_remote/shared/you_facts.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: Settings > Account, drawn by `orbit_ui`'s [orbit.AccountScreen].
///
/// Shows who this device is signed in as (the phone number is masked, never
/// shown in full), then the things that change the account: the password,
/// exporting what the server holds, signing out and deleting the account.
/// The screen confirms sign-out and delete itself; "Export first" in the
/// delete dialog only exports, and the delete page (the word DELETE and the
/// proof of ownership) is a step of its own.
class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(accountOverviewProvider);
    final action = ref.watch(accountActionsProvider);
    final actions = ref.read(accountActionsProvider.notifier);
    final header = ref.watch(settingsHeaderProvider).value;
    final bytes = ref.watch(settingsAvatarProvider);
    final value = overview.value;

    final name = header == null || header.name.isEmpty ? 'You' : header.name;
    final accountId = header?.accountId ?? '';

    // A failure is the screen's toast; "could not be shared" is the notice.
    Future<String?> export() async {
      await actions.exportData();
      return ref.read(accountActionsProvider).error;
    }

    Future<void> signOut() async {
      await actions.signOut();
      final error = ref.read(accountActionsProvider).error;
      if (error != null && context.mounted) {
        orbit.showOrbitToast(context, error, error: true);
      }
    }

    return orbit.AccountScreen(
      model: orbit.AccountModel(
        name: name,
        avatar: orbit.HelixAvatarModel(
          name: name,
          colorIndex: orbit.HelixAvatarModel.colorIndexFor(
            accountId.isEmpty ? 'helix' : accountId,
          ),
          image: bytes == null ? null : MemoryImage(bytes),
        ),
        loadFailed: overview.hasError && value == null,
        busy: action.busy,
        notice: action.notice,
        phoneMasked: value?.phoneMasked ?? '',
        helixName: value?.helixName,
        hasPassword: value?.hasPassword ?? true,
        passwordChangedLabel: ref.watch(passwordSubtitleProvider) ?? '',
        deviceCount: ref.watch(youDeviceCountProvider),
        sinceLabel: ref.watch(accountSinceProvider),
      ),
      actions: orbit.AccountActions(
        onPassword: () => context.push(RoutePaths.changePassword),
        onActivity: () => context.push(RoutePaths.devicesActivity),
        onExport: export,
        onSignOut: signOut,
        onSwitchAccount: () => context.push(RoutePaths.accounts),
        onExportFirst: export,
        onDelete: () => context.push(RoutePaths.deleteAccount),
        onRetry: () => ref.invalidate(accountOverviewProvider),
      ),
    );
  }
}
