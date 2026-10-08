import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_admin/src/features/accounts/accounts_controller.dart';
import 'package:helix_admin/src/features/accounts/accounts_screen.dart';
import 'package:helix_admin/src/features/common/format.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
import 'package:helix_admin/src/widgets/dialogs.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// One account on its own page (a phone): the details and what an operator
/// can do to it. Pops with true when the account was banned or deleted, so
/// the list reloads.
class AccountDetailScreen extends StatelessWidget {
  const AccountDetailScreen({
    super.key,
    required this.adminContext,
    required this.accountId,
  });

  final AdminContext adminContext;
  final String accountId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: AccountDetailView(
        adminContext: adminContext,
        accountId: accountId,
        onRemoved: () => Navigator.of(context).pop(true),
      ),
    );
  }
}

/// The account's details, devices and actions, without a page around it, so
/// it can fill a page or the right-hand pane of a wide window.
class AccountDetailView extends StatefulWidget {
  const AccountDetailView({
    super.key,
    required this.adminContext,
    required this.accountId,
    required this.onRemoved,
  });

  final AdminContext adminContext;
  final String accountId;

  /// The account was banned or deleted here.
  final VoidCallback onRemoved;

  @override
  State<AccountDetailView> createState() => _AccountDetailViewState();
}

class _AccountDetailViewState extends State<AccountDetailView> {
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
      widget.onRemoved();
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
      widget.onRemoved();
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

  Future<void> _copyId(String id) async {
    await Clipboard.setData(ClipboardData(text: id));
    if (mounted) showMessage(context, 'Account id copied.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final detail = _controller.detail;
        if (detail == null) {
          if (_controller.loading || _controller.error == null) {
            return const ConsoleLoading(label: 'Loading the account');
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ConsoleBanner(
                title: 'Something went wrong',
                message: _controller.error!,
                onRetry: _controller.load,
              ),
            ],
          );
        }
        final account = detail.account;
        final suspended = account.status == AccountStatus.suspended;
        final name = account.helixName;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ConsoleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: ConsoleCardLabel('User identity & state'),
                      ),
                      AccountStatusBadge(status: account.status),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      AccountAvatar(name: name, radius: 24),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name == null || name.isEmpty
                                  ? 'No Helix name'
                                  : name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: HelixConsoleColors.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              maskedPhone(account.phoneLast4),
                              style: const TextStyle(
                                fontSize: 13,
                                color: HelixConsoleColors.textBody,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Joined ${formatDay(account.createdAt)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: HelixConsoleColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ConsoleProperty(
                    label: 'Account ID',
                    value: account.accountId,
                    copyable: true,
                  ),
                  const SizedBox(height: 10),
                  ConsoleProperty(
                    label: 'Last seen',
                    mono: false,
                    value: account.lastSeenOn == null
                        ? 'Not yet'
                        : formatDay(account.lastSeenOn!),
                  ),
                  const SizedBox(height: 10),
                  ConsoleProperty(
                    label: 'Password',
                    mono: false,
                    value: detail.hasPassword ? 'Set' : 'Not set',
                  ),
                  const SizedBox(height: 10),
                  ConsoleProperty(
                    label: 'Open reports',
                    mono: false,
                    value: '${detail.openReports}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ConsoleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(child: ConsoleCardLabel('Devices')),
                      Text(
                        '${detail.devices.where((d) => d.active).length} '
                        'signed in',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: HelixConsoleColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (detail.devices.isEmpty)
                    const _NoDevices()
                  else
                    for (final device in detail.devices) ...[
                      _DeviceTile(
                        device: device,
                        busy: _controller.isBusy('device:${device.deviceId}'),
                        onRevoke: () => _revoke(device),
                      ),
                      const SizedBox(height: 8),
                    ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            ConsoleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ConsoleCardLabel('Administrative actions'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _controller.isBusy('recovery')
                              ? null
                              : _recoveryCode,
                          style: ConsoleButtons.filled,
                          icon: const Icon(Icons.key, size: 18),
                          label: const Text('Recovery code'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _copyId(account.accountId),
                          style: ConsoleButtons.outlined,
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copy user ID'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ConsoleCard(
              color: HelixConsoleColors.dangerSurface,
              borderColor: HelixConsoleColors.dangerBorder,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ConsoleCardLabel(
                    'Danger zone',
                    color: HelixConsoleColors.danger,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _controller.isBusy('suspension')
                              ? null
                              : (suspended
                                    ? () async => _report(
                                        await _controller.unsuspend(),
                                        'Account resumed.',
                                      )
                                    : _suspend),
                          style: ConsoleButtons.outlinedTone(
                            HelixConsoleColors.onWarn,
                            HelixConsoleColors.warn,
                          ),
                          icon: Icon(
                            suspended
                                ? Icons.play_circle_outline
                                : Icons.pause_circle_outline,
                            size: 18,
                          ),
                          label: Text(suspended ? 'Resume account' : 'Suspend'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _controller.isBusy('delete')
                              ? null
                              : _delete,
                          style: ConsoleButtons.outlinedTone(
                            HelixConsoleColors.danger,
                            HelixConsoleColors.danger,
                          ),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Delete'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _controller.isBusy('ban') ? null : _ban,
                    style: ConsoleButtons.filledTone(
                      HelixConsoleColors.onDanger,
                    ),
                    icon: const Icon(Icons.block, size: 18),
                    label: const Text('Ban'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _NoDevices extends StatelessWidget {
  const _NoDevices();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: HelixConsoleColors.sunken,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: HelixConsoleColors.border),
    ),
    child: const Row(
      children: [
        Icon(
          Icons.phonelink_erase_outlined,
          size: 18,
          color: HelixConsoleColors.textFaint,
        ),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'No devices. This account has not registered a device on this '
            'server yet.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: HelixConsoleColors.textMuted,
            ),
          ),
        ),
      ],
    ),
  );
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
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
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: HelixConsoleColors.sunken,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HelixConsoleColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: device.active
                  ? HelixConsoleColors.accentSurface
                  : HelixConsoleColors.border,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _icon(device.platform),
              size: 18,
              color: device.active
                  ? HelixConsoleColors.accent
                  : HelixConsoleColors.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name.isEmpty ? 'Unnamed device' : device.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: HelixConsoleColors.text,
                  ),
                ),
                Text(
                  '${device.platform.wire} · $state',
                  style: const TextStyle(
                    fontSize: 11,
                    color: HelixConsoleColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (device.active)
            TextButton(
              onPressed: busy ? null : onRevoke,
              style: TextButton.styleFrom(
                foregroundColor: HelixConsoleColors.danger,
              ),
              child: const Text('Revoke'),
            )
          else
            const ConsolePill(
              label: 'Revoked',
              tone: ConsoleTone.neutral,
              upper: true,
            ),
        ],
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
