import 'package:flutter/material.dart';
import 'package:helix_admin/src/api/error_text.dart';
import 'package:helix_admin/src/features/common/format.dart';
import 'package:helix_admin/src/features/dashboard/server_controller.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/session/admin_session_scope.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
import 'package:helix_admin/src/widgets/dialogs.dart';
import 'package:helix_admin/src/widgets/password_field.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Plain names for the feature flags the server allow-lists.
const flagLabels = {
  'crash_reporting_upload': 'Accept crash reports from apps',
  'minimal_analytics': 'Minimal analytics',
  'group_calls': 'Group calls',
};

/// Ops & Logs > Config: the server's name and properties, federation, the
/// admin password and App lock, maintenance, feature flags and sign-out.
class ConfigView extends StatelessWidget {
  const ConfigView({super.key, required this.server});

  final ServerController server;

  Future<void> _rename(BuildContext context) async {
    final current = server.config?.serverName ?? '';
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: current),
    );
    if (name == null || !context.mounted) return;
    final problem = await server.rename(name);
    if (context.mounted) {
      showMessage(context, problem ?? 'Server name saved.');
    }
  }

  Future<void> _purge(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Purge dead jobs?',
      message:
          'Removes background jobs that failed for good, and expired '
          'sign-in and recovery rows. Nothing a person can see is removed.',
      action: 'Purge',
    );
    if (!confirmed || !context.mounted) return;
    final outcome = await server.purge();
    if (!context.mounted) return;
    final problem = outcome.problem;
    if (problem != null) {
      showMessage(context, problem);
      return;
    }
    await showInfoDialog(
      context,
      title: 'Purge finished',
      message: _purgeSummary(outcome.result),
    );
  }

  /// "Removed 3 dead jobs and 2 expired rows." or a plain "nothing" line.
  static String _purgeSummary(PurgeResult? result) {
    final removed = result?.removed ?? const <String, int>{};
    final parts = [
      for (final e in removed.entries)
        if (e.value > 0)
          '${formatCount(e.value)} ${e.key.replaceAll('_', ' ')}',
    ];
    return parts.isEmpty
        ? 'There was nothing to purge.'
        : 'Removed ${parts.join(', ')}.';
  }

  Future<void> _changePassword(BuildContext context) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _ChangePasswordDialog(session: AdminSessionScope.read(context)),
    );
    if (changed ?? false) {
      if (context.mounted) {
        showMessage(
          context,
          'Password changed. Other admin sessions were signed out.',
        );
      }
    }
  }

  Future<void> _appLock(BuildContext context, bool on) async {
    final problem = await AdminSessionScope.read(context).setAppLock(on);
    if (problem != null && context.mounted) showMessage(context, problem);
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'You will need the admin password to sign in again.',
      action: 'Sign out',
    );
    if (confirmed && context.mounted) {
      await AdminSessionScope.read(context).signOut();
    }
  }

  Future<void> _maintenance(BuildContext context, bool on) async {
    if (on) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Turn on maintenance mode?',
        message:
            'The server will answer 503 to every app until you turn it off. '
            'This console keeps working.',
        action: 'Turn on',
      );
      if (!confirmed || !context.mounted) return;
    }
    final problem = await server.setMaintenance(on);
    if (!context.mounted) return;
    showMessage(
      context,
      problem ?? (on ? 'Maintenance mode is on.' : 'Maintenance mode is off.'),
    );
  }

  Future<void> _federation(BuildContext context, bool on) async {
    final problem = await server.setFederation(on);
    if (!context.mounted) return;
    showMessage(
      context,
      problem ?? (on ? 'Federation is on.' : 'Federation is off.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = AdminSessionScope.of(context);
    return ListenableBuilder(
      listenable: server,
      builder: (context, _) {
        final config = server.config;
        final expires = session.sessionExpiresAt;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ConsoleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ConsoleCardLabel('Server node identity'),
                  const SizedBox(height: 14),
                  ConsoleSettingRow(
                    title: config == null || config.serverName.isEmpty
                        ? 'Not set'
                        : config.serverName,
                    subtitle:
                        'Public node identity shown to people who sign up',
                    trailing: OutlinedButton(
                      onPressed: config == null || server.isBusy('name')
                          ? null
                          : () => _rename(context),
                      style: ConsoleButtons.outlined,
                      child: const Text('Edit name'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ConsoleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ConsoleCardLabel('Server configuration properties'),
                  const SizedBox(height: 4),
                  const Text(
                    'Address, version and limits as this server reports them',
                    style: TextStyle(
                      fontSize: 12,
                      color: HelixConsoleColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Properties(
                    items: [
                      ConsoleProperty(
                        label: 'Public server address',
                        value: session.serverAddress?.text ?? 'Not available',
                      ),
                      ConsoleProperty(
                        label: 'Node ID',
                        value: config?.nodeId ?? 'Not available',
                        copyable: config != null,
                      ),
                      ConsoleProperty(
                        label: 'Version',
                        value: config?.version ?? 'Not available',
                      ),
                      ConsoleProperty(
                        label: 'Sign-up',
                        mono: false,
                        value: switch (config?.registration) {
                          RegistrationMode.phone => 'Phone number',
                          RegistrationMode.invite => 'Invite code',
                          RegistrationMode.closed => 'Closed',
                          _ => 'Not available',
                        },
                      ),
                      ConsoleProperty(
                        label: 'Attachment limit',
                        mono: false,
                        value: config == null
                            ? 'Not available'
                            : formatBytes(config.maxAttachmentBytes),
                      ),
                      if (expires != null)
                        ConsoleProperty(
                          label: 'Signed in until',
                          mono: false,
                          value: formatTime(expires),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ConsoleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ConsoleCardLabel('Worldwide mode & peer network'),
                  const SizedBox(height: 14),
                  ConsoleSettingRow(
                    title: 'Worldwide Network Mode',
                    subtitle: 'Talk to other Helix servers (federation)',
                    trailing: Switch(
                      value: config?.federationEnabled ?? false,
                      onChanged: config == null || server.isBusy('federation')
                          ? null
                          : (on) => _federation(context, on),
                    ),
                  ),
                  if (config?.federationDomain != null) ...[
                    const SizedBox(height: 14),
                    ConsoleProperty(
                      label: 'Federation domain',
                      value: config!.federationDomain!,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            ConsoleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ConsoleCardLabel('Local security & app lock'),
                  const SizedBox(height: 14),
                  ConsoleSettingRow(
                    title: 'Device biometric / PIN lock',
                    subtitle:
                        "Ask for this device's screen lock when the console "
                        'opens',
                    trailing: Switch(
                      value: session.appLockEnabled,
                      onChanged: (on) => _appLock(context, on),
                    ),
                  ),
                  const Divider(height: 28),
                  ConsoleSettingRow(
                    title: 'Admin password',
                    subtitle: 'Changing it signs out every other admin session',
                    trailing: OutlinedButton(
                      onPressed: () => _changePassword(context),
                      style: ConsoleButtons.outlined,
                      child: const Text('Change password'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ConsoleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ConsoleCardLabel('Node maintenance & clean-up'),
                  const SizedBox(height: 14),
                  ConsoleSettingRow(
                    title: 'Server maintenance mode',
                    subtitle:
                        'Apps get 503 Service Unavailable while it is on. '
                        'This console keeps working',
                    trailing: Switch(
                      value: config?.maintenance ?? false,
                      onChanged: config == null || server.isBusy('maintenance')
                          ? null
                          : (on) => _maintenance(context, on),
                    ),
                  ),
                  const Divider(height: 28),
                  ConsoleSettingRow(
                    title: 'Purge dead jobs',
                    subtitle:
                        'Clears failed background jobs and expired sign-in '
                        'rows. Nothing a person can see is removed',
                    trailing: OutlinedButton(
                      onPressed: server.isBusy('purge')
                          ? null
                          : () => _purge(context),
                      style: ConsoleButtons.outlinedTone(
                        HelixConsoleColors.danger,
                        HelixConsoleColors.dangerBorder,
                      ),
                      child: server.isBusy('purge')
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Purge'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ConsoleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ConsoleCardLabel('Feature flags'),
                  const SizedBox(height: 4),
                  const Text(
                    'Server-owned switches. Changes take effect immediately.',
                    style: TextStyle(
                      fontSize: 12,
                      color: HelixConsoleColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (server.flagsNote != null)
                    ConsoleBanner(message: server.flagsNote!),
                  if (server.flags.isEmpty && server.flagsNote == null)
                    const Text(
                      'This server has no feature flags.',
                      style: TextStyle(
                        fontSize: 13,
                        color: HelixConsoleColors.textMuted,
                      ),
                    ),
                  for (final entry in server.flags.entries) ...[
                    ConsoleSettingRow(
                      title: flagLabels[entry.key] ?? entry.key,
                      subtitle: entry.key,
                      trailing: Switch(
                        value: entry.value,
                        onChanged: server.isBusy('flag:${entry.key}')
                            ? null
                            : (on) async {
                                final problem = await server.setFlag(
                                  entry.key,
                                  on,
                                );
                                if (context.mounted && problem != null) {
                                  showMessage(context, problem);
                                }
                              },
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            ConsoleCard(
              color: HelixConsoleColors.dangerSurface,
              borderColor: HelixConsoleColors.dangerBorder,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ConsoleCardLabel(
                    'Admin session control',
                    color: HelixConsoleColors.danger,
                  ),
                  const SizedBox(height: 14),
                  ConsoleSettingRow(
                    title: 'Sign out of this server',
                    titleColor: HelixConsoleColors.onDanger,
                    subtitleColor: HelixConsoleColors.danger,
                    subtitle:
                        'Clears the saved admin session from this device. '
                        'You will need the admin password to sign back in',
                    trailing: FilledButton(
                      onPressed: () => _signOut(context),
                      style: ConsoleButtons.filledTone(
                        HelixConsoleColors.danger,
                      ),
                      child: const Text('Sign out'),
                    ),
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

/// Two columns of property boxes on a wide card, one on a phone.
class _Properties extends StatelessWidget {
  const _Properties({required this.items});

  final List<Widget> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 520) {
        return Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              items[i],
            ],
          ],
        );
      }
      final width = (constraints.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final item in items) SizedBox(width: width, child: item),
        ],
      );
    },
  );
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Server name'),
    content: TextField(
      controller: _name,
      autofocus: true,
      maxLength: AdminConfigPatch.maxServerNameLength,
      decoration: const InputDecoration(
        labelText: 'Name people see for this server',
      ),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _name.text),
        child: const Text('Save'),
      ),
    ],
  );
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.session});

  final AdminSessionController session;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_current.text.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }
    final problem = validateNewPassword(_next.text, _confirm.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.changePassword(
        current: _current.text,
        next: _next.text,
      );
      if (mounted) Navigator.pop(context, true);
    } on Object catch (e) {
      widget.session.reportError(e);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeAdminError(e, now: widget.session.services.now);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Change admin password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PasswordField(
              controller: _current,
              label: 'Current password',
              enabled: !_busy,
              autofocus: true,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: HelixSpace.sm),
            PasswordField(
              controller: _next,
              label: 'New password',
              enabled: !_busy,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: HelixSpace.sm),
            PasswordField(
              controller: _confirm,
              label: 'Repeat the new password',
              enabled: !_busy,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: HelixSpace.xs),
            Text(
              'At least ${AdminPasswordRequest.minLength} characters.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: HelixSpace.xs),
              Semantics(
                liveRegion: true,
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Change password'),
        ),
      ],
    );
  }
}
