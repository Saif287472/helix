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

/// One account: its identity, devices and the actions an operator can take.
/// Shown in a sheet over the list that opened it; [onRemoved] fires when the
/// account was banned or deleted, with the line for the operator, who by then
/// is looking at the page underneath and not at this sheet.
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
  final void Function(String outcome) onRemoved;

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
      // As heavy as deleting, which it includes (review B-05).
      phrase: 'BAN',
    );
    if (reason == null) return;
    final problem = await _controller.ban(reason: reason.text);
    if (!mounted) return;
    if (problem == null) {
      widget.onRemoved('Account banned and deleted.');
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
      widget.onRemoved('Account deleted.');
    } else {
      showMessage(context, problem);
    }
  }

  Future<void> _changeLimit() async {
    final change = await showDialog<_LimitChange>(
      context: context,
      builder: (_) => const _LimitDialog(),
    );
    if (change == null || !mounted) return;
    _report(
      await _controller.setOverride(
        change.key,
        value: change.value,
        reason: change.reason,
        days: change.days,
      ),
      'Limit changed for this account.',
    );
  }

  Future<void> _clearLimit(PlanLimitKey key) async {
    _report(await _controller.clearOverride(key), 'Limit back to the plan.');
  }

  Future<void> _givePremium() async {
    final months = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Give Orbit Premium'),
        children: [
          for (final m in const [1, 6, 12])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, m),
              child: Text(m == 1 ? '1 month' : '$m months'),
            ),
        ],
      ),
    );
    if (months == null || !mounted) return;
    _report(
      await _controller.grantPlan(months),
      '${months == 1 ? '1 month' : '$months months'} of Premium given.',
    );
  }

  Future<void> _endPremium() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'End Orbit Premium now?',
      message:
          'The account returns to the Free plan at once, with no grace '
          'period. Nothing it holds is deleted.',
      action: 'End Premium',
    );
    if (!confirmed || !mounted) return;
    final problem = await _controller.revokePlan();
    _report(problem, 'Premium ended.');
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
        final name = accountTitle(account);
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
                      AccountAvatar(
                        name: account.displayName ?? account.helixName,
                        radius: 24,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: HelixConsoleColors.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              accountPhone(account),
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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _controller.isBusy('plan')
                              ? null
                              : _givePremium,
                          style: ConsoleButtons.outlined,
                          icon: const Icon(Icons.workspace_premium, size: 18),
                          label: const Text('Give Premium'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _controller.isBusy('plan')
                              ? null
                              : _endPremium,
                          style: ConsoleButtons.outlined,
                          icon: const Icon(Icons.block, size: 18),
                          label: const Text('End Premium'),
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
            if (_controller.plan case final plan?) ...[
              const SizedBox(height: 14),
              _PlanCard(
                plan: plan,
                busy: _controller.isBusy('plan'),
                onChange: _changeLimit,
                onClear: _clearLimit,
              ),
            ],
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

String _limitLabel(PlanLimitKey k) => switch (k) {
  PlanLimitKey.maxDevices => 'Linked devices',
  PlanLimitKey.attachmentQuotaBytes => 'Attachment storage',
  PlanLimitKey.maxAttachmentBytes => 'Largest file',
  PlanLimitKey.attachmentRetentionDays => 'Files kept (days)',
  PlanLimitKey.backupMaxBytes => 'Backup file size',
  PlanLimitKey.backupQuotaBytes => 'Backup room',
  PlanLimitKey.unknown => 'Unknown limit',
};

bool _isBytes(PlanLimitKey k) =>
    k == PlanLimitKey.attachmentQuotaBytes ||
    k == PlanLimitKey.maxAttachmentBytes ||
    k == PlanLimitKey.backupMaxBytes ||
    k == PlanLimitKey.backupQuotaBytes;

String _limitValue(PlanLimitKey k, int v) =>
    _isBytes(k) ? formatBytes(v) : '$v';

/// What the account has under Orbit Premium (ADR-035), the limits in force and
/// the operator's overrides, each removable.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.busy,
    required this.onChange,
    required this.onClear,
  });

  final AdminAccountPlan plan;
  final bool busy;
  final VoidCallback onChange;
  final void Function(PlanLimitKey key) onClear;

  @override
  Widget build(BuildContext context) {
    final end = plan.periodEnd;
    final premium = plan.plan == PlanId.premium;
    final l = plan.limits;
    return ConsoleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ConsoleCardLabel('Orbit Premium'),
          const SizedBox(height: 12),
          ConsoleProperty(
            label: 'Plan',
            value: premium
                ? (plan.source == 'trial' ? 'Premium (trial)' : 'Premium')
                : 'Free',
            mono: false,
          ),
          if (end != null)
            ConsoleProperty(
              label: plan.inGrace ? 'Ended (in grace)' : 'Until',
              value: formatDay(end),
              mono: false,
            ),
          ConsoleProperty(label: 'Device limit', value: '${l.maxDevices}'),
          ConsoleProperty(
            label: 'Attachment storage',
            value: formatBytes(l.attachmentQuotaBytes),
          ),
          ConsoleProperty(
            label: 'Largest file',
            value: formatBytes(l.maxAttachmentBytes),
          ),
          ConsoleProperty(
            label: 'Files kept',
            value: '${l.attachmentRetentionDays} days',
            mono: false,
          ),
          if (plan.overrides.isNotEmpty) ...[
            const SizedBox(height: 10),
            const ConsoleCardLabel('Changed for this account'),
            const SizedBox(height: 6),
            for (final o in plan.overrides)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_limitLabel(o.key)}: ${_limitValue(o.key, o.value)}'
                        '${o.expiresAt == null ? '' : ' until ${formatDay(o.expiresAt!)}'}'
                        ' (${o.reason})',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: HelixConsoleColors.textBody,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: busy ? null : () => onClear(o.key),
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy ? null : onChange,
            style: ConsoleButtons.outlined,
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Change a limit'),
          ),
        ],
      ),
    );
  }
}

/// One limit change as the operator typed it, in the units the server keeps.
class _LimitChange {
  const _LimitChange(this.key, this.value, this.reason, this.days);

  final PlanLimitKey key;
  final int value;
  final String reason;
  final int? days;
}

/// Picks a limit, a value (in MiB for sizes), a reason and how long.
class _LimitDialog extends StatefulWidget {
  const _LimitDialog();

  @override
  State<_LimitDialog> createState() => _LimitDialogState();
}

class _LimitDialogState extends State<_LimitDialog> {
  PlanLimitKey _key = PlanLimitKey.maxDevices;
  final _value = TextEditingController();
  final _reason = TextEditingController();
  final _days = TextEditingController();

  @override
  void dispose() {
    _value.dispose();
    _reason.dispose();
    _days.dispose();
    super.dispose();
  }

  _LimitChange? _read() {
    final typed = int.tryParse(_value.text.trim());
    if (typed == null || _reason.text.trim().isEmpty) return null;
    final value = _isBytes(_key) ? typed * 1024 * 1024 : typed;
    if (value < _key.min || value > _key.max) return null;
    final days = _days.text.trim().isEmpty
        ? null
        : int.tryParse(_days.text.trim());
    if (_days.text.trim().isNotEmpty &&
        (days == null || days < 1 || days > 366)) {
      return null;
    }
    return _LimitChange(_key, value, _reason.text.trim(), days);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Change a limit'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<PlanLimitKey>(
            initialValue: _key,
            items: [
              for (final k in PlanLimitKey.values)
                if (k != PlanLimitKey.unknown)
                  DropdownMenuItem(value: k, child: Text(_limitLabel(k))),
            ],
            onChanged: (k) => setState(() => _key = k ?? _key),
          ),
          TextField(
            controller: _value,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _isBytes(_key) ? 'New value (MiB)' : 'New value',
            ),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: _reason,
            maxLength: SetPlanOverrideRequest.maxReasonLength,
            decoration: const InputDecoration(
              labelText: 'Why (for the next operator)',
            ),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: _days,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Days (blank: until removed)',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _read() == null
            ? null
            : () => Navigator.pop(context, _read()),
        child: const Text('Save'),
      ),
    ],
  );
}
