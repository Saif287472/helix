import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({
    super.key,
    required this.restClient,
    required this.messagingService,
    this.onBeforeDelete,
    this.onAccountDeleted,
  });

  final HelixRemoteRestClient restClient;
  final RemoteMessagingService messagingService;

  /// Called before the server deletion request; should stop WS/calls/sync.
  final Future<void> Function()? onBeforeDelete;

  final Future<void> Function()? onAccountDeleted;

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  bool _busy = false;
  String? _status;

  Future<void> _exportData() async {
    setState(() {
      _busy = true;
      _status = 'Exporting data...';
    });
    try {
      await _cleanupExpiredExports();
      final data = await widget.restClient.exportData();
      final pretty = const JsonEncoder.withIndent('  ').convert(data);
      final dir = await getApplicationDocumentsDirectory();
      final exportDir = Directory(p.join(dir.path, 'helix_remote_exports'));
      if (!exportDir.existsSync()) {
        exportDir.createSync(recursive: true);
      }
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

  Future<void> _deleteAccount() async {
    final accountId = widget.messagingService.currentAccountId;
    if (accountId == null) {
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

  Future<void> _applyStrictPreset() async {
    final preview = widget.messagingService.db.strictAccountSettingsPreview();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Strict Account Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in preview.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('${entry.key}: ${entry.value}'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    widget.messagingService.db.applyStrictAccountSettingsPreset();
    widget.messagingService.updatePrivacy(
      const RemotePrivacySettings(
        searchDiscoverable: false,
        presenceVisibility: 'NOBODY',
        lastSeenVisibility: 'NOBODY',
      ),
    );
    widget.messagingService.setReadReceiptsEnabled(false);
    if (mounted) {
      setState(() => _status = 'Strict privacy preset applied.');
    }
  }

  void _setAppLock(bool enabled) {
    final current = widget.messagingService.db.getAppLockSettings();
    widget.messagingService.db.setAppLockSettings(
      RemoteAppLockSettings(
        enabled: enabled,
        relockAfterSeconds: current.relockAfterSeconds,
        useBiometric: current.useBiometric,
        pinVerifier: current.pinVerifier,
        recoveryBehavior: current.recoveryBehavior,
      ),
    );
    setState(() {});
  }

  void _setRelockPolicy(int seconds) {
    final current = widget.messagingService.db.getAppLockSettings();
    widget.messagingService.db.setAppLockSettings(
      RemoteAppLockSettings(
        enabled: current.enabled,
        relockAfterSeconds: seconds,
        useBiometric: current.useBiometric,
        pinVerifier: current.pinVerifier,
        recoveryBehavior: current.recoveryBehavior,
      ),
    );
    setState(() {});
  }

  void _setDefaultDisappearing(int seconds) {
    widget.messagingService.db.setAccountDefaultDisappearingSeconds(seconds);
    setState(() {});
  }

  Future<void> _cleanupExpiredExports() async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(dir.path, 'helix_remote_exports'));
    if (!exportDir.existsSync()) return;
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    for (final entity in exportDir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        if (entity.lastModifiedSync().isBefore(cutoff)) {
          entity.deleteSync();
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = widget.messagingService.db;
    final appLock = db.getAppLockSettings();
    final checkup = db.privacyCheckupItems();
    final defaultDisappearing = db.getAccountDefaultDisappearingSeconds();
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.file_download),
                  title: const Text('Export My Data'),
                  subtitle: const Text(
                    'Save JSON file outside encrypted app DB',
                  ),
                  enabled: !_busy,
                  onTap: _exportData,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Delete Account'),
                  subtitle: const Text(
                    'Permanently delete account and all data',
                  ),
                  enabled: !_busy,
                  onTap: _deleteAccount,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.security),
                  title: const Text('Strict Account Settings'),
                  subtitle: const Text('Preview and apply strongest defaults'),
                  enabled: !_busy,
                  onTap: _applyStrictPreset,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.lock_outline),
                      title: const Text('App Lock'),
                      subtitle: Text(
                        'Relock after ${appLock.relockAfterSeconds == 0 ? 'immediately' : '${appLock.relockAfterSeconds}s'}',
                      ),
                      value: appLock.enabled,
                      onChanged: _busy ? null : _setAppLock,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: DropdownButtonFormField<int>(
                        initialValue: appLock.relockAfterSeconds,
                        decoration: const InputDecoration(
                          labelText: 'Relock policy',
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Immediate')),
                          DropdownMenuItem(value: 60, child: Text('1 minute')),
                          DropdownMenuItem(
                            value: 300,
                            child: Text('5 minutes'),
                          ),
                          DropdownMenuItem(
                            value: 900,
                            child: Text('15 minutes'),
                          ),
                        ],
                        onChanged: _busy || !appLock.enabled
                            ? null
                            : (v) => _setRelockPolicy(v ?? 60),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.notifications_off_outlined),
                      title: const Text('Hide Notification Previews'),
                      subtitle: const Text(
                        'Locked chats and strict mode always redact content',
                      ),
                      value: !db.getNotificationPreviewsEnabled(),
                      onChanged: _busy
                          ? null
                          : (v) {
                              db.setNotificationPreviews(enabled: !v);
                              setState(() {});
                            },
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.call_missed_outlined),
                      title: const Text('Silence Unknown Callers'),
                      subtitle: const Text(
                        'Unknown calls do not ring and are rate-limited',
                      ),
                      value: db.getSilenceUnknownCallers(),
                      onChanged: _busy
                          ? null
                          : (v) {
                              db.setSilenceUnknownCallers(enabled: v);
                              setState(() {});
                            },
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: DropdownButtonFormField<int>(
                        initialValue: defaultDisappearing,
                        decoration: const InputDecoration(
                          labelText: 'Default disappearing messages',
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Off')),
                          DropdownMenuItem(
                            value: 86400,
                            child: Text('24 hours'),
                          ),
                          DropdownMenuItem(
                            value: 604800,
                            child: Text('7 days'),
                          ),
                          DropdownMenuItem(
                            value: 7776000,
                            child: Text('90 days'),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (v) => _setDefaultDisappearing(v ?? 0),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.fact_check_outlined),
                      title: Text('Privacy Checkup'),
                    ),
                    for (final item in checkup)
                      ListTile(
                        dense: true,
                        title: Text(item.label),
                        subtitle: Text(item.enforcementSource),
                        trailing: SizedBox(
                          width: 72,
                          child: Text(
                            item.state,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (_status != null) ...[
                const SizedBox(height: 16),
                Text(_status!, textAlign: TextAlign.center),
              ],
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
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
      title: const Text('Delete Account'),
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
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
