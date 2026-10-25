import 'package:flutter/material.dart';
import 'package:helix_admin/src/api/error_text.dart';
import 'package:helix_admin/src/features/audit/audit_screen.dart';
import 'package:helix_admin/src/features/common/format.dart';
import 'package:helix_admin/src/features/dashboard/server_controller.dart';
import 'package:helix_admin/src/features/logs/logs_screen.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/session/admin_session_scope.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
import 'package:helix_admin/src/widgets/console_sheet.dart';
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

/// Configuration: the server as one page - who it is, how it is doing, the
/// four groups of switches and actions, the facts an operator copies, and the
/// way out. Changes save at once and are written to the audit trail.
class ConfigView extends StatelessWidget {
  const ConfigView({
    super.key,
    required this.server,
    required this.adminContext,
  });

  final ServerController server;
  final AdminContext adminContext;

  /// The log opens over this page; the audit trail is long enough to want a
  /// page of its own.
  void _showLog(BuildContext context) => showConsoleSheet(
    context: context,
    child: LogsScreen(adminContext: adminContext),
  );

  void _openAudit(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => AuditPage(adminContext: adminContext)),
  );

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

  /// The health the server reported about itself: how many of its readiness
  /// checks passed, and the words that say what that means. Maintenance is a
  /// switch the operator put on on purpose, not a check that failed.
  static ({String words, String note, int passed, int total, ConsoleTone tone})
  _health(ServerController server) {
    final ready = server.ready;
    if (ready == null) {
      return (
        words: 'Not checked',
        note: 'The server has not answered a readiness check.',
        passed: 0,
        total: 0,
        tone: ConsoleTone.neutral,
      );
    }
    final checks = ready.checks;
    final passed = checks.values.where((ok) => ok).length;
    final note = '$passed of ${checks.length} readiness checks passed';
    if (server.config?.maintenance ?? false) {
      return (
        words: 'Maintenance mode',
        note: note,
        passed: passed,
        total: checks.length,
        tone: ConsoleTone.warn,
      );
    }
    return passed == checks.length
        ? (
            words: 'Operational',
            note: note,
            passed: passed,
            total: checks.length,
            tone: ConsoleTone.ok,
          )
        : (
            words: 'Checks failing',
            note: note,
            passed: passed,
            total: checks.length,
            tone: ConsoleTone.danger,
          );
  }

  /// Sign-up in the words the operator uses, for the hero's pill.
  static String _registrationWords(AdminConfig? config) =>
      switch (config?.registration) {
        RegistrationMode.phone => 'Phone number',
        RegistrationMode.invite => 'Invite code',
        RegistrationMode.closed => 'Sign-up closed',
        _ => 'Sign-up unknown',
      };

  /// The name, the version and how people sign up - the one place a server is
  /// introduced, so it is the first card and the only one that lifts.
  Widget _hero(BuildContext context, AdminConfig? config) => ConsoleCard(
    elevated: true,
    radius: 24,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const ConsoleIconTile(
              icon: Icons.dns_outlined,
              accent: HelixConsoleColors.accent,
              size: 48,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config == null || config.serverName.isEmpty
                        ? 'Not set'
                        : config.serverName,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: HelixConsoleColors.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Shown to people who sign up',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: HelixConsoleColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ConsolePill(label: config?.version ?? 'Not available'),
                  ConsolePill(label: _registrationWords(config)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: config == null || server.isBusy('name')
                  ? null
                  : () => _rename(context),
              style: ConsoleButtons.pill,
              child: const Text('Edit name'),
            ),
          ],
        ),
      ],
    ),
  );

  /// The meter the operator reads before any of the checks behind it, and the
  /// two things they do about it: pause the server, or clear what expired.
  Widget _healthCard(BuildContext context) {
    final config = server.config;
    final health = _health(server);
    return ConsoleCard(
      elevated: true,
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ConsoleCardLabel('Server health'),
          const SizedBox(height: 16),
          Row(
            children: [
              ConsoleDot(color: health.tone.dot),
              const SizedBox(width: 10),
              Text(
                health.words,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: health.tone.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            health.note,
            style: const TextStyle(
              fontSize: 12,
              height: 1.35,
              color: HelixConsoleColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          ConsoleMeter(
            passed: health.passed,
            total: health.total,
            color: health.tone.dot,
          ),
          const SizedBox(height: 8),
          ConsoleSettingRow(
            title: 'Server maintenance mode',
            subtitle: 'Apps get 503; this console keeps working',
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
            subtitle: 'Failed jobs and expired sign-in rows only',
            trailing: OutlinedButton(
              onPressed: server.isBusy('purge') ? null : () => _purge(context),
              style: ConsoleButtons.pillTone(
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
    );
  }

  /// The four groups a fix usually needs, two by two on a wide window and
  /// stacked on a phone. Each tile holds its own switches and actions: the
  /// grid is the screen, not a way out of it.
  Widget _quickAccess(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final tiles = <Widget>[
        _tile(
          icon: Icons.public,
          accent: HelixConsoleColors.accent,
          title: 'Network & Sync',
          subtitle: 'Other Helix servers',
          body: _networkTile(context),
        ),
        _tile(
          icon: Icons.article_outlined,
          accent: HelixConsoleColors.violet,
          title: 'Logs & Activity',
          subtitle: 'Server and console activity',
          body: _activityTile(context),
        ),
        _tile(
          icon: Icons.tune,
          accent: HelixConsoleColors.onOk,
          title: 'Features',
          subtitle: 'Server-wide switches',
          body: _featureTile(context),
        ),
        _tile(
          icon: Icons.lock_outline,
          accent: HelixConsoleColors.onWarn,
          title: 'Security',
          subtitle: 'Device lock and password',
          body: _securityTile(context),
        ),
      ];
      if (constraints.maxWidth < 560) {
        return Column(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              tiles[i],
            ],
          ],
        );
      }
      final width = (constraints.maxWidth - 14) / 2;
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          for (final tile in tiles) SizedBox(width: width, child: tile),
        ],
      );
    },
  );

  Widget _tile({
    required IconData icon,
    required Color accent,
    required String title,
    required String subtitle,
    required Widget body,
  }) => ConsoleCard(
    radius: 20,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ConsoleIconTile(icon: icon, accent: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: HelixConsoleColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
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
        const SizedBox(height: 8),
        body,
      ],
    ),
  );

  Widget _networkTile(BuildContext context) {
    final config = server.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConsoleSettingRow(
          title: 'Worldwide Network Mode',
          subtitle: 'Federate with other servers',
          trailing: Switch(
            value: config?.federationEnabled ?? false,
            onChanged: config == null || server.isBusy('federation')
                ? null
                : (on) => _federation(context, on),
          ),
        ),
        if (config?.federationDomain != null)
          ConsoleProperty(
            label: 'Federation domain',
            value: config!.federationDomain!,
          ),
      ],
    );
  }

  Widget _activityTile(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ConsoleSettingRow(
        title: 'Live log',
        subtitle: 'Right now',
        trailing: OutlinedButton(
          onPressed: () => _showLog(context),
          style: ConsoleButtons.pill,
          child: const Text('Show log'),
        ),
      ),
      const Divider(height: 28),
      ConsoleSettingRow(
        title: 'Audit trail',
        subtitle: 'What this console did',
        trailing: OutlinedButton(
          onPressed: () => _openAudit(context),
          style: ConsoleButtons.pill,
          child: const Text('Open audit'),
        ),
      ),
    ],
  );

  Widget _featureTile(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (server.flagsNote != null) ConsoleBanner(message: server.flagsNote!),
      if (server.flags.isEmpty && server.flagsNote == null)
        const Text(
          'This server has no feature flags.',
          style: TextStyle(fontSize: 13, color: HelixConsoleColors.textMuted),
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
                    final problem = await server.setFlag(entry.key, on);
                    if (context.mounted && problem != null) {
                      showMessage(context, problem);
                    }
                  },
          ),
        ),
        const SizedBox(height: 12),
      ],
    ],
  );

  Widget _securityTile(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ConsoleSettingRow(
        title: 'Device biometric / PIN lock',
        subtitle: 'Ask on every open',
        trailing: Switch(
          value: AdminSessionScope.read(context).appLockEnabled,
          onChanged: (on) => _appLock(context, on),
        ),
      ),
      const Divider(height: 28),
      ConsoleSettingRow(
        title: 'Admin password',
        subtitle: 'Signs out other sessions',
        trailing: OutlinedButton(
          onPressed: () => _changePassword(context),
          style: ConsoleButtons.pill,
          child: const Text('Change password'),
        ),
      ),
    ],
  );

  /// The facts an operator copies somewhere else, in one list. The version and
  /// how people sign up are the hero's, so they are not repeated here.
  Widget _facts(AdminSessionController session, AdminConfig? config) =>
      ConsoleCard(
        radius: 24,
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: ConsoleCardLabel('This server'),
            ),
            ConsoleValueRow(
              label: 'Public server address',
              value: session.serverAddress?.text ?? 'Not available',
              icon: Icons.link,
              accent: HelixConsoleColors.accent,
              mono: true,
              copyValue: session.serverAddress?.text,
            ),
            consoleListDivider,
            ConsoleValueRow(
              label: 'Node ID',
              value: config?.nodeId ?? 'Not available',
              icon: Icons.fingerprint,
              accent: HelixConsoleColors.violet,
              mono: true,
              copyValue: config?.nodeId,
            ),
            consoleListDivider,
            ConsoleValueRow(
              label: 'Attachment limit',
              value: config == null
                  ? 'Not available'
                  : formatBytes(config.maxAttachmentBytes),
              icon: Icons.attach_file,
              accent: HelixConsoleColors.onOk,
            ),
            if (session.sessionExpiresAt case final expires?) ...[
              consoleListDivider,
              ConsoleValueRow(
                label: 'Signed in until',
                value: formatTime(expires),
                icon: Icons.schedule,
                accent: HelixConsoleColors.onWarn,
              ),
            ],
          ],
        ),
      );

  /// The one card that ends the session, so it is the last thing on the page
  /// and the only red one.
  Widget _dangerZone(BuildContext context) => ConsoleCard(
    radius: 24,
    color: HelixConsoleColors.dangerSurface,
    borderColor: HelixConsoleColors.dangerBorder,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ConsoleCardLabel('Danger zone', color: HelixConsoleColors.danger),
        const SizedBox(height: 14),
        ConsoleSettingRow(
          title: 'Sign out of this server',
          titleColor: HelixConsoleColors.onDanger,
          subtitleColor: HelixConsoleColors.danger,
          subtitle: 'Ends every admin session here',
          trailing: FilledButton(
            onPressed: () => confirmAndSignOut(context),
            style: ConsoleButtons.pillFilledTone(HelixConsoleColors.danger),
            child: const Text('Sign out'),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final session = AdminSessionScope.of(context);
    return ListenableBuilder(
      listenable: server,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          const ConsoleTitle('Configuration'),
          const SizedBox(height: 18),
          _hero(context, server.config),
          const SizedBox(height: 16),
          _healthCard(context),
          const SizedBox(height: 16),
          _quickAccess(context),
          const SizedBox(height: 16),
          _facts(session, server.config),
          const SizedBox(height: 16),
          _dangerZone(context),
        ],
      ),
    );
  }
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
