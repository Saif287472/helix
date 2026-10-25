import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/settings/application/accounts_providers.dart';
import 'package:helix_remote/features/settings/application/settings_providers.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: Settings > Accounts, drawn by `orbit_ui`'s
/// [orbit.AccountsScreen]: the accounts signed in on this phone, to open,
/// remove or add one. Opening another account or adding one leaves this page
/// (home of that account, or sign-in).
class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(accountLinesProvider);
    final page = ref.watch(accountsPageProvider);
    final actions = ref.read(accountsPageProvider.notifier);
    final header = ref.watch(settingsHeaderProvider).value;
    final bytes = ref.watch(settingsAvatarProvider);

    orbit.AccountsEntry entry(AccountLine line) {
      // The account on screen looks as it does on You: its picture, and the
      // colour of its server-side id.
      final seed = line.current && (header?.accountId ?? '').isNotEmpty
          ? header!.accountId
          : line.id;
      return orbit.AccountsEntry(
        id: line.id,
        title: line.title,
        detail: line.detail,
        current: line.current,
        unread: line.unread,
        avatar: orbit.HelixAvatarModel(
          name: line.title,
          colorIndex: orbit.HelixAvatarModel.colorIndexFor(seed),
          image: line.current && bytes != null ? MemoryImage(bytes) : null,
        ),
      );
    }

    return orbit.AccountsScreen(
      model: orbit.AccountsModel(
        accounts: [for (final l in lines) entry(l)],
        busy: page.busy,
        notice: page.error,
      ),
      actions: orbit.AccountsActions(
        onOpen: actions.open,
        onAdd: actions.add,
        onRemove: actions.remove,
      ),
    );
  }
}
