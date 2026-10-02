import 'package:flutter/material.dart';
import 'package:helix_admin/src/features/accounts/account_detail_screen.dart';
import 'package:helix_admin/src/features/accounts/accounts_controller.dart';
import 'package:helix_admin/src/features/common/format.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/widgets/paged_list.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Accounts: search by Helix name or the last four digits, filter by status,
/// open one for its devices and actions.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key, required this.adminContext, this.pageSize});

  final AdminContext adminContext;
  final int? pageSize;

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  late final AccountsController _accounts;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _accounts = AccountsController(
      widget.adminContext,
      pageSize: widget.pageSize ?? PageRequest.defaultLimit,
    )..refresh();
  }

  @override
  void dispose() {
    _accounts.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(AdminAccount account) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AccountDetailScreen(
          adminContext: widget.adminContext,
          accountId: account.accountId,
        ),
      ),
    );
    if (changed ?? false) await _accounts.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _accounts,
      builder: (context, _) => PagedListView<AdminAccount>(
        controller: _accounts,
        emptyIcon: Icons.people_outline,
        emptyTitle: 'No accounts found',
        emptyMessage: _accounts.query.isEmpty && _accounts.status == null
            ? 'Accounts appear here when people sign up.'
            : 'Try another search or filter.',
        header: _Filters(accounts: _accounts, search: _search),
        itemBuilder: (context, account) =>
            AccountTile(account: account, onTap: () => _open(account)),
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.accounts, required this.search});

  final AccountsController accounts;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      HelixSpace.md,
      HelixSpace.md,
      HelixSpace.md,
      HelixSpace.xs,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: search,
          textInputAction: TextInputAction.search,
          onSubmitted: accounts.search,
          decoration: InputDecoration(
            labelText: 'Search by Helix name or last 4 digits',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Clear search',
              icon: const Icon(Icons.clear),
              onPressed: () {
                search.clear();
                accounts.search('');
              },
            ),
          ),
        ),
        const SizedBox(height: HelixSpace.xs),
        ListenableBuilder(
          listenable: accounts,
          builder: (context, _) => Wrap(
            spacing: HelixSpace.xs,
            children: [
              for (final (label, value) in const [
                ('All', null),
                ('Active', AccountStatus.active),
                ('Suspended', AccountStatus.suspended),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: accounts.status == value,
                  onSelected: (_) => accounts.filterByStatus(value),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// One row of the account list.
class AccountTile extends StatelessWidget {
  const AccountTile({super.key, required this.account, required this.onTap});

  final AdminAccount account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = account.helixName;
    final devices = account.activeDevices == 1
        ? '1 device'
        : '${account.activeDevices} devices';
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        child: Text(name == null || name.isEmpty ? '?' : name.characters.first),
      ),
      title: Text(name == null || name.isEmpty ? 'No Helix name' : name),
      subtitle: Text(
        '${maskedPhone(account.phoneLast4)} · $devices · '
        'joined ${formatDay(account.createdAt)}',
      ),
      trailing: AccountStatusBadge(status: account.status),
    );
  }
}

class AccountStatusBadge extends StatelessWidget {
  const AccountStatusBadge({super.key, required this.status});

  final AccountStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
    AccountStatus.active => const HelixStatusBadge(
      label: 'Active',
      color: HelixStatusColors.positive,
    ),
    AccountStatus.suspended => const HelixStatusBadge(
      label: 'Suspended',
      color: HelixStatusColors.caution,
    ),
    AccountStatus.unknown => const HelixStatusBadge(
      label: 'Unknown',
      color: HelixStatusColors.neutral,
    ),
  };
}
