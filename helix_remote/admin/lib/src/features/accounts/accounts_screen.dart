import 'package:flutter/material.dart';
import 'package:helix_admin/src/features/accounts/account_detail_screen.dart';
import 'package:helix_admin/src/features/accounts/accounts_controller.dart';
import 'package:helix_admin/src/features/common/format.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
import 'package:helix_admin/src/widgets/console_sheet.dart';
import 'package:helix_admin/src/widgets/dialogs.dart';
import 'package:helix_admin/src/widgets/paged_list.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Users & Devices: search by Orbit name or the last four digits, filter by
/// status, open one for its devices and actions. An account opens over the
/// list in a sheet, on a phone and on a wide window alike.
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
    final outcome = await showConsoleSheet<String>(
      context: context,
      child: AccountDetailView(
        adminContext: widget.adminContext,
        accountId: account.accountId,
        onRemoved: (outcome) => Navigator.of(context).pop(outcome),
      ),
    );
    if (outcome == null || !mounted) return;
    // The account is gone: the list says what was done to it and reloads.
    showMessage(context, outcome);
    await _accounts.refresh();
  }

  @override
  Widget build(BuildContext context) {
    // The empty-state wording depends on the filter, so it follows the
    // controller.
    return ListenableBuilder(
      listenable: _accounts,
      builder: (context, _) => PagedListView<AdminAccount>(
        controller: _accounts,
        emptyIcon: Icons.search_off,
        emptyTitle: 'No accounts found',
        emptyMessage: _accounts.query.isEmpty && _accounts.status == null
            ? 'Accounts appear here when people sign up.'
            : 'Try another search or filter.',
        header: _Header(accounts: _accounts, search: _search),
        itemBuilder: (context, account) =>
            AccountTile(account: account, onTap: () => _open(account)),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.accounts, required this.search});

  final AccountsController accounts;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const ConsoleTitle('Users & Devices'),
      const SizedBox(height: 14),
      TextField(
        controller: search,
        textInputAction: TextInputAction.search,
        onSubmitted: accounts.search,
        decoration: InputDecoration(
          hintText: 'Search by Orbit name or last 4 digits',
          prefixIcon: const Icon(
            Icons.search,
            size: 20,
            color: HelixConsoleColors.textFaint,
          ),
          suffixIcon: IconButton(
            tooltip: 'Clear search',
            icon: const Icon(
              Icons.clear,
              size: 18,
              color: HelixConsoleColors.textFaint,
            ),
            onPressed: () {
              search.clear();
              accounts.search('');
            },
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: const BorderSide(color: HelixConsoleColors.border),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: const BorderSide(color: HelixConsoleColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: const BorderSide(color: HelixConsoleColors.accent),
          ),
        ),
      ),
      const SizedBox(height: 12),
      ListenableBuilder(
        listenable: accounts,
        builder: (context, _) => ConsoleChipRow(
          children: [
            for (final (label, value) in const [
              ('All users', null),
              ('Active', AccountStatus.active),
              ('Suspended', AccountStatus.suspended),
            ])
              ConsoleChip(
                label: label,
                selected: accounts.status == value,
                onTap: () => accounts.filterByStatus(value),
              ),
          ],
        ),
      ),
    ],
  );
}

/// The round initial that stands for a person.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.name, this.radius = 22});

  final String? name;
  final double radius;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: HelixConsoleColors.accentSurface,
        shape: BoxShape.circle,
        border: Border.all(color: HelixConsoleColors.accentBorder),
      ),
      child: Text(
        name == null || name!.isEmpty
            ? '?'
            : name!.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w800,
          color: HelixConsoleColors.accent,
        ),
      ),
    ),
  );
}

/// One card of the account list.
class AccountTile extends StatelessWidget {
  const AccountTile({super.key, required this.account, required this.onTap});

  final AdminAccount account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = accountTitle(account);
    final devices = account.activeDevices == 1
        ? '1 device'
        : '${account.activeDevices} devices';
    return Semantics(
      button: true,
      child: ConsoleCard(
        radius: 12,
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Row(
          children: [
            AccountAvatar(name: account.displayName ?? account.helixName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: HelixConsoleColors.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AccountStatusBadge(status: account.status),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    accountPhone(account),
                    style: const TextStyle(
                      fontSize: 12,
                      color: HelixConsoleColors.textBody,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$devices · Joined ${formatDay(account.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: HelixConsoleColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: HelixConsoleColors.textFaint,
            ),
          ],
        ),
      ),
    );
  }
}

class AccountStatusBadge extends StatelessWidget {
  const AccountStatusBadge({super.key, required this.status});

  final AccountStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
    AccountStatus.active => const ConsolePill(
      label: 'Active',
      tone: ConsoleTone.ok,
      upper: true,
    ),
    AccountStatus.suspended => const ConsolePill(
      label: 'Suspended',
      tone: ConsoleTone.warn,
      upper: true,
    ),
    AccountStatus.unknown => const ConsolePill(
      label: 'Unknown',
      tone: ConsoleTone.neutral,
      upper: true,
    ),
  };
}
