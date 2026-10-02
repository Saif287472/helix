import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_admin/src/features/accounts/accounts_controller.dart';
import 'package:helix_admin/src/features/accounts/accounts_screen.dart';
import 'package:helix_admin/src/features/common/format.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/widgets/dialogs.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// One account: its details and devices, and what an operator can do to it.
/// Pops with true when the account was banned or deleted, so the list
/// reloads.
class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({
    super.key,
    required this.adminContext,
    required this.accountId,
  });

  final AdminContext adminContext;
  final String accountId;

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  late final AccountDetailController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AccountDetailController(widget.adminContext, widget.accountId)
      ..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _report(String? problem, String success) {
    if (!mounted) return;
    showMessage(context, problem ?? success);
  }

  Future<void> _suspend() async {
    final reason = await showReasonDialog(
      context,
      title: 'Suspend this account?',
      message:
          'The person stays signed in on their devices but can only read '
          'until you resume the account.',
      action: 'Suspend',
    );
    if (reason == null) return;
    _report(
      await _controller.suspend(reason: reason.text),
      'Account suspended.',
    );
  }

  Future<void> _ban() async {
    final reason = await showReasonDialog(
      context,
      title: 'Ban this person?',
      message:
          'This bans the phone number from registering again and deletes '
          'the account. It cannot be undone.',
      action: 'Ban and delete',
      destructive: true,
    );
    if (reason == null) return;
    final problem = await _controller.ban(reason: reason.text);
    if (!mounted) return;
    if (problem == null) {
      showMessage(context, 'Account banned and deleted.');
      Navigator.of(context).pop(true);
    } else {
      showMessage(context, problem);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showTypedConfirmDialog(
      context,
      title: 'Delete this account?',
      message:
          'This deletes the account and everything the server holds for it: '
          'devices, keys, undelivered messages and backups. It cannot be '
          'undone. The phone number is not banned.',
      phrase: 'DELETE',
      action: 'Delete account',
    );
    if (!confirmed) return;
    final problem = await _controller.deleteAccount();
    if (!mounted) return;
    if (problem == null) {
      showMessage(context, 'Account deleted.');
      Navigator.of(context).pop(true);
    } else {
      showMessage(context, problem);
    }
  }

  Future<void> _recoveryCode() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Create a recovery code?',
      message:
          'The code lets the person regain access to this account. It works '
          'once, for 48 hours, and is shown only on the next screen.',
      action: 'Create code',
    );
    if (!confirmed || !mounted) return;
    final result = await _controller.createRecoveryCode();
    if (!mounted) return;
    final code = result.code;
    if (code == null) {
      showMessage(context, result.problem ?? 'No code was created.');
      return;
    }
    await showCodeOnceDialog(
      context,
      title: 'Recovery code',
      code: code.recoveryCode,
      expiresAt: code.expiresAt,
      explanation:
          'Give this code to the account owner through a channel you trust. '
          'It works once.',
    );
  }

  Future<void> _revoke(AdminDevice device) async {
    final confirmed = await showHelixDestructiveDialog(
      context,
      title: 'Revoke ${device.name}?',
      message:
          'The device is signed out at once and its keys and undelivered '
          'messages are removed.',
      action: 'Revoke',
    );
    if (!confirmed) return;
    _report(await _controller.revokeDevice(device.deviceId), 'Device revoked.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final detail = _controller.detail;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              detail?.account.helixName ?? 'Account',
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                tooltip: 'Reload account',
                icon: const Icon(Icons.refresh),
                onPressed: _controller.loading ? null : _controller.load,
              ),
            ],
          ),
          body: detail == null
              ? HelixAsyncPanel(
                  loading: _controller.loading || _controller.error == null,
                  error: _controller.error,
                  onRetry: _controller.load,
                  child: const SizedBox.shrink(),
                )
              : _Body(
                  controller: _controller,
                  detail: detail,
                  onSuspend: _suspend,
                  onUnsuspend: () async => _report(
                    await _controller.unsuspend(),
                    'Account resumed.',
                  ),
                  onBan: _ban,
                  onDelete: _delete,
                  onRecoveryCode: _recoveryCode,
                  onRevoke: _revoke,
                ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.controller,
    required this.detail,
    required this.onSuspend,
    required this.onUnsuspend,
    required this.onBan,
    required this.onDelete,
    required this.onRecoveryCode,
    required this.onRevoke,
  });

  final AccountDetailController controller;
  final AdminAccountDetail detail;
  final VoidCallback onSuspend;
  final VoidCallback onUnsuspend;
  final VoidCallback onBan;
  final VoidCallback onDelete;
  final VoidCallback onRecoveryCode;
  final void Function(AdminDevice device) onRevoke;

  @override
  Widget build(BuildContext context) {
    final account = detail.account;
    final theme = Theme.of(context);
    final suspended = account.status == AccountStatus.suspended;
    return ListView(
      padding: const EdgeInsets.all(HelixSpace.md),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(HelixSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        account.helixName ?? 'No Helix name',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    AccountStatusBadge(status: account.status),
                  ],
                ),
                const SizedBox(height: HelixSpace.xs),
                _Fact('Phone', maskedPhone(account.phoneLast4)),
                _Fact(
                  'Account id',
                  account.accountId,
                  copyTooltip: 'Copy account id',
                ),
                _Fact('Created', formatTime(account.createdAt)),
                _Fact(
                  'Last seen',
                  account.lastSeenOn == null
                      ? 'Not yet'
                      : formatDay(account.lastSeenOn!),
                ),
                _Fact('Password', detail.hasPassword ? 'Set' : 'Not set'),
                _Fact('Open reports', '${detail.openReports}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: HelixSpace.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(HelixSpace.md),
            child: Wrap(
              spacing: HelixSpace.xs,
              runSpacing: HelixSpace.xs,
              children: [
                if (suspended)
                  FilledButton.tonalIcon(
                    onPressed: controller.isBusy('suspension')
                        ? null
                        : onUnsuspend,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Resume account'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: controller.isBusy('suspension')
                        ? null
                        : onSuspend,
                    icon: const Icon(Icons.pause_circle_outline),
                    label: const Text('Suspend'),
                  ),
                OutlinedButton.icon(
                  onPressed: controller.isBusy('recovery')
                      ? null
                      : onRecoveryCode,
                  icon: const Icon(Icons.key),
                  label: const Text('Recovery code'),
                ),
                OutlinedButton.icon(
                  onPressed: controller.isBusy('ban') ? null : onBan,
                  icon: const Icon(Icons.block),
                  label: const Text('Ban'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: controller.isBusy('delete') ? null : onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: HelixSpace.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(HelixSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text('Devices', style: theme.textTheme.titleMedium),
                ),
                if (detail.devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: HelixSpace.xs),
                    child: Text('No devices.'),
                  ),
                for (final device in detail.devices)
                  _DeviceRow(
                    device: device,
                    busy: controller.isBusy('device:${device.deviceId}'),
                    onRevoke: () => onRevoke(device),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.busy,
    required this.onRevoke,
  });

  final AdminDevice device;
  final bool busy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final seen = device.lastSeenOn == null
        ? 'never seen'
        : 'last seen ${formatDay(device.lastSeenOn!)}';
    final state = device.active
        ? seen
        : 'revoked ${device.revokedAt == null ? '' : formatDay(device.revokedAt!)}'
              .trim();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_icon(device.platform)),
      title: Text(device.name.isEmpty ? 'Unnamed device' : device.name),
      subtitle: Text('${device.platform.wire} · $state'),
      trailing: device.active
          ? TextButton(
              onPressed: busy ? null : onRevoke,
              child: const Text('Revoke'),
            )
          : const HelixStatusBadge(
              label: 'Revoked',
              color: HelixStatusColors.neutral,
            ),
    );
  }

  static IconData _icon(DevicePlatform platform) => switch (platform) {
    DevicePlatform.android || DevicePlatform.ios => Icons.smartphone,
    DevicePlatform.windows ||
    DevicePlatform.macos ||
    DevicePlatform.linux => Icons.computer,
    DevicePlatform.cli => Icons.terminal,
    DevicePlatform.other => Icons.devices_other,
  };
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.copyTooltip});

  final String label;
  final String value;

  /// When set, a button copies [value] (an id the operator may need).
  final String? copyTooltip;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        Expanded(child: Text(value)),
        if (copyTooltip != null)
          IconButton(
            tooltip: copyTooltip,
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (context.mounted) showMessage(context, 'Copied.');
            },
          ),
      ],
    ),
  );
}
