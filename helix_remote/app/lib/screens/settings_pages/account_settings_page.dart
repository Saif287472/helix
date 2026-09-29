import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/screens/settings_pages/settings_page_kit.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Profile, account ID and QR, data export, and account deletion.
class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({
    super.key,
    required this.restClient,
    required this.messagingService,
    this.onOpenProfile,
    this.onOpenMyQr,
    this.onOpenPassword,
    this.onBackUpHistory,
    this.lastHistoryBackupAt,
    this.onBeforeDelete,
    this.onAccountDeleted,
  });

  final HelixRemoteRestClient restClient;
  final RemoteMessagingService messagingService;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenMyQr;
  final VoidCallback? onOpenPassword;

  /// Uploads the text-history backup now; throws on failure.
  final Future<void> Function()? onBackUpHistory;
  final Future<DateTime?> Function()? lastHistoryBackupAt;

  /// Called before the server deletion request; should stop WS/calls/sync.
  final Future<void> Function()? onBeforeDelete;
  final Future<void> Function()? onAccountDeleted;

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  bool _busy = false;
  String? _status;
  bool _backingUp = false;
  DateTime? _lastBackup;

  @override
  void initState() {
    super.initState();
    _loadLastBackup();
  }

  Future<void> _loadLastBackup() async {
    final last = await widget.lastHistoryBackupAt?.call();
    if (mounted) setState(() => _lastBackup = last);
  }

  Future<void> _backUpHistory() async {
    final backUp = widget.onBackUpHistory;
    if (backUp == null || _backingUp) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _backingUp = true);
    try {
      await backUp();
      messenger.showSnackBar(
        const SnackBar(content: Text('Chat history backed up.')),
      );
      await _loadLastBackup();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not back up. Check your connection and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  String _backupSubtitle() {
    if (_backingUp) return 'Backing up…';
    final last = _lastBackup;
    if (last == null) {
      return 'Text messages back up automatically every day. Not backed up yet.';
    }
    final local = last.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Text messages back up automatically every day. Last backup: '
        '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _exportData() async {
    setState(() {
      _busy = true;
      _status = 'Exporting data...';
    });
    try {
      final dir = await getApplicationDocumentsDirectory();
      final exportDir = Directory(p.join(dir.path, 'helix_remote_exports'));
      await _cleanupExpiredExports(exportDir);
      final data = await widget.restClient.exportData();
      final pretty = const JsonEncoder.withIndent('  ').convert(data);
      await exportDir.create(recursive: true);
      final file = File(
        p.join(
          exportDir.path,
          'helix_remote_export_${DateTime.now().millisecondsSinceEpoch}.json',
        ),
      );
      await file.writeAsString(pretty, flush: true);
      if (mounted) {
        setState(
          () => _status =
              'Export saved to ${file.path}. External files are outside app wipe guarantees.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _status = 'Export failed. Check available storage and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Exports are plaintext outside the encrypted database, so old ones are
  /// removed rather than left to accumulate.
  Future<void> _cleanupExpiredExports(Directory exportDir) async {
    if (!await exportDir.exists()) return;
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    await for (final entity in exportDir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        if ((await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _deleteAccount() async {
    if (widget.messagingService.currentAccountId == null) {
      setState(() => _status = 'Not logged in');
      return;
    }
    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) => const _ConfirmDeleteDialog(),
    );
    if (confirmed == null) return;
    if (confirmed != 'DELETE') {
      setState(() => _status = 'Deletion confirmation did not match');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Stopping runtime before deletion…';
    });
    await widget.onBeforeDelete?.call();
    try {
      if (mounted) setState(() => _status = 'Deleting account…');
      await widget.restClient.requestAccountDeletion(confirmation: confirmed);
      await widget.onAccountDeleted?.call();
      if (mounted) {
        setState(() => _status = 'Account deleted and local app data cleared.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status =
              'Account deletion failed. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.messagingService.currentDisplayName ?? '';
    final accountId = widget.messagingService.currentAccountId ?? '';
    return SettingsPage(
      title: 'Account',
      children: [
        SettingsSection(
          children: [
            SettingsTile(
              icon: Icons.person_outline,
              color: HelixColorTokens.cFF3B82F6,
              title: 'Profile',
              subtitle: name.isEmpty ? 'Set your name' : name,
              onTap: widget.onOpenProfile,
            ),
            SettingsTile(
              icon: Icons.qr_code_2,
              color: HelixColorTokens.cFF14B8A6,
              title: 'My QR code',
              subtitle: 'Let someone add you by scanning it',
              onTap: widget.onOpenMyQr,
            ),
            if (widget.onOpenPassword != null)
              SettingsTile(
                icon: Icons.password_outlined,
                color: HelixColorTokens.cFF7C3AED,
                title: 'Password',
                subtitle:
                    'Sign in on any device with your phone number and password',
                onTap: widget.onOpenPassword,
              ),
            SettingsTile(
              icon: Icons.badge_outlined,
              color: HelixColorTokens.cFF5B6EE1,
              title: 'Account ID',
              subtitle: accountId.isEmpty ? '—' : accountId,
              trailing: accountId.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Copy',
                      icon: const Icon(Icons.copy_outlined),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: accountId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Account ID copied')),
                        );
                      },
                    ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Your data',
          children: [
            if (widget.onBackUpHistory != null)
              SettingsTile(
                icon: Icons.cloud_upload_outlined,
                color: HelixColorTokens.cFF3B82F6,
                title: 'Chat history backup',
                subtitle: _backupSubtitle(),
                onTap: _backingUp ? null : _backUpHistory,
              ),
            SettingsTile(
              icon: Icons.file_download_outlined,
              color: HelixColorTokens.cFFF97316,
              title: 'Export my data',
              subtitle: 'Save JSON file outside encrypted app DB',
              onTap: _busy ? null : _exportData,
            ),
          ],
        ),
        // Last, and on its own: a permanent action does not sit among the
        // ordinary ones.
        SettingsSection(
          children: [
            SettingsTile(
              icon: Icons.delete_forever_outlined,
              color: HelixStatusColors.danger,
              title: 'Delete account',
              subtitle: 'Permanently delete your account and all its data',
              destructive: true,
              onTap: _busy ? null : _deleteAccount,
            ),
          ],
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_status!, textAlign: TextAlign.center),
          ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

class _ConfirmDeleteDialog extends StatefulWidget {
  const _ConfirmDeleteDialog();

  @override
  State<_ConfirmDeleteDialog> createState() => _ConfirmDeleteDialogState();
}

class _ConfirmDeleteDialogState extends State<_ConfirmDeleteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete account'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Type DELETE to confirm.'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Confirmation'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          style: FilledButton.styleFrom(
            backgroundColor: HelixStatusColors.danger,
          ),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
