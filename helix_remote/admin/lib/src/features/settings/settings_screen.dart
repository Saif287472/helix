import 'package:flutter/material.dart';
import 'package:helix_admin/src/api/error_text.dart';
import 'package:helix_admin/src/features/common/format.dart';
import 'package:helix_admin/src/features/dashboard/server_controller.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/session/admin_session_scope.dart';
import 'package:helix_admin/src/widgets/dialogs.dart';
import 'package:helix_admin/src/widgets/password_field.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Server name, the admin password, App lock, cleanup and sign-out.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.server});

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

  @override
  Widget build(BuildContext context) {
    final session = AdminSessionScope.of(context);
    return ListenableBuilder(
      listenable: server,
      builder: (context, _) {
        final config = server.config;
        final expires = session.sessionExpiresAt;
        return ListView(
          padding: const EdgeInsets.all(HelixSpace.md),
          children: [
            _Group(
              title: 'Server',
              children: [
                ListTile(
                  title: const Text('Server name'),
                  subtitle: Text(
                    config == null || config.serverName.isEmpty
                        ? 'Not set'
                        : config.serverName,
                  ),
                  trailing: TextButton(
                    onPressed: config == null || server.isBusy('name')
                        ? null
                        : () => _rename(context),
                    child: const Text('Rename'),
                  ),
                ),
                ListTile(
                  title: const Text('Address'),
                  subtitle: Text(session.serverAddress?.text ?? ''),
                ),
                if (expires != null)
                  ListTile(
                    title: const Text('Signed in until'),
                    subtitle: Text(
                      '${formatTime(expires)} (admin sessions last 12 hours)',
                    ),
                  ),
              ],
            ),
            _Group(
              title: 'Security',
              children: [
                ListTile(
                  title: const Text('Change admin password'),
                  subtitle: const Text('Signs out every other admin session.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _changePassword(context),
                ),
                SwitchListTile(
                  title: const Text('App lock'),
                  subtitle: const Text(
                    "Ask for this device's screen lock when the console opens.",
                  ),
                  value: session.appLockEnabled,
                  onChanged: (on) => _appLock(context, on),
                ),
              ],
            ),
            _Group(
              title: 'Maintenance',
              children: [
                ListTile(
                  title: const Text('Purge dead jobs'),
                  subtitle: const Text(
                    'Clears failed background jobs and expired rows.',
                  ),
                  trailing: server.isBusy('purge')
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: server.isBusy('purge') ? null : () => _purge(context),
                ),
              ],
            ),
            const SizedBox(height: HelixSpace.md),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => _signOut(context),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: HelixSpace.md),
    child: Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HelixSpace.md,
              HelixSpace.md,
              HelixSpace.md,
              0,
            ),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          ...children,
        ],
      ),
    ),
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
        border: OutlineInputBorder(),
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
