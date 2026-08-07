import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:helix_remote/l10n/helix_localizations.dart';

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
        title: Text(HelixLocalizations.of(context).strictAccountSettings),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in preview.entries)
              Padding(
                padding: HelixInsets.symmetric(vertical: 2),
                child: Text('${entry.key}: ${entry.value}'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(HelixLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(HelixLocalizations.of(context).apply),
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

  static String _relockLabel(int seconds) => switch (seconds) {
    0 => 'immediately',
    60 => 'after 1 minute',
    300 => 'after 5 minutes',
    900 => 'after 15 minutes',
    _ => 'after ${seconds}s',
  };

  @override
  Widget build(BuildContext context) {
    final db = widget.messagingService.db;
    final appLock = db.getAppLockSettings();
    final checkup = db.privacyCheckupItems();
    final defaultDisappearing = db.getAccountDefaultDisappearingSeconds();
    return Scaffold(
      appBar: AppBar(
        title: Text(HelixLocalizations.of(context).privacySecurity),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: HelixInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.file_download),
                  title: Text(HelixLocalizations.of(context).exportMyData),
                  subtitle: Text(
                    HelixLocalizations.of(context).saveJsonFileOutsideEncrypted,
                  ),
                  enabled: !_busy,
                  onTap: _exportData,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.security),
                  title: Text(
                    HelixLocalizations.of(context).strictAccountSettings,
                  ),
                  subtitle: Text(
                    HelixLocalizations.of(
                      context,
                    ).previewApplyStrongestDefaults,
                  ),
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
                      title: Text(HelixLocalizations.of(context).appLock),
                      subtitle: Text(
                        'Relock ${_relockLabel(appLock.relockAfterSeconds)}',
                      ),
                      value: appLock.enabled,
                      onChanged: _busy ? null : _setAppLock,
                    ),
                    Padding(
                      padding: HelixInsets.fromLTRB(16, 0, 16, 12),
                      child: DropdownButtonFormField<int>(
                        initialValue: appLock.relockAfterSeconds,
                        decoration: const InputDecoration(
                          labelText: 'Relock policy',
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 0,
                            child: Text(
                              HelixLocalizations.of(context).immediate,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 60,
                            child: Text(HelixLocalizations.of(context).minute),
                          ),
                          DropdownMenuItem(
                            value: 300,
                            child: Text(HelixLocalizations.of(context).minutes),
                          ),
                          DropdownMenuItem(
                            value: 900,
                            child: Text(
                              HelixLocalizations.of(context).minutes2,
                            ),
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
                      title: Text(
                        HelixLocalizations.of(context).hideNotificationPreviews,
                      ),
                      subtitle: Text(
                        HelixLocalizations.of(
                          context,
                        ).lockedChatsStrictModeAlways,
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
                      title: Text(
                        HelixLocalizations.of(context).silenceUnknownCallers,
                      ),
                      subtitle: Text(
                        HelixLocalizations.of(context).unknownCallsDoNotRing,
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
                      padding: HelixInsets.fromLTRB(16, 0, 16, 12),
                      child: DropdownButtonFormField<int>(
                        initialValue: defaultDisappearing,
                        decoration: const InputDecoration(
                          labelText: 'Default disappearing messages',
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 0,
                            child: Text(HelixLocalizations.of(context).off),
                          ),
                          DropdownMenuItem(
                            value: 86400,
                            child: Text(HelixLocalizations.of(context).hours),
                          ),
                          DropdownMenuItem(
                            value: 604800,
                            child: Text(HelixLocalizations.of(context).days),
                          ),
                          DropdownMenuItem(
                            value: 7776000,
                            child: Text(HelixLocalizations.of(context).days2),
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
              // Settings advertises a blocked count and a locked-chat count
              // on the row that opens this screen. Until now neither could be
              // reviewed here: blocking lives on the contact's own page and
              // locking on the conversation's, so the only way to find out
              // who you had blocked was to remember.
              _ListCard(
                icon: Icons.block_outlined,
                title: 'Blocked contacts',
                emptyLabel: 'No blocked contacts.',
                entries: [
                  for (final contact in db.getContacts())
                    if (contact.status == 'Blocked')
                      _ListCardEntry(
                        label: contact.nickname.isEmpty
                            ? contact.peerAccountId
                            : contact.nickname,
                        sublabel: contact.peerAccountId,
                        actionLabel: 'Unblock',
                        onAction: _busy
                            ? null
                            : () {
                                widget.messagingService.unblockContact(
                                  contact.peerAccountId,
                                );
                                setState(() {});
                              },
                      ),
                ],
              ),
              const SizedBox(height: 8),
              _ListCard(
                icon: Icons.lock_person_outlined,
                title: 'Locked chats',
                emptyLabel: 'No locked chats.',
                entries: [
                  for (final conversation in db.getLockedConversations())
                    _ListCardEntry(
                      label: conversation.title.isEmpty
                          ? conversation.conversationId
                          : conversation.title,
                      sublabel: conversation.type,
                      actionLabel: 'Unlock',
                      onAction: _busy
                          ? null
                          : () {
                              db.setConversationLocked(
                                conversation.conversationId,
                                locked: false,
                                hidden: false,
                              );
                              setState(() {});
                            },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.fact_check_outlined),
                      title: Text(
                        HelixLocalizations.of(context).privacyCheckup,
                      ),
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
              // Last, not second. A permanent, unrecoverable action does not
              // belong above the ordinary toggles.
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.delete_forever,
                    color: HelixStatusColors.danger,
                  ),
                  title: Text(HelixLocalizations.of(context).deleteAccount),
                  subtitle: Text(
                    HelixLocalizations.of(
                      context,
                    ).permanentlyDeleteAccountAllIts,
                  ),
                  enabled: !_busy,
                  onTap: _deleteAccount,
                ),
              ),
              if (_status != null) ...[
                const SizedBox(height: 16),
                Text(_status!, textAlign: TextAlign.center),
              ],
              if (_busy)
                Padding(
                  padding: HelixInsets.all(16),
                  child: const CircularProgressIndicator(),
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
      title: Text(HelixLocalizations.of(context).deleteAccount),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(HelixLocalizations.of(context).typeDeleteConfirm),
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
          child: Text(HelixLocalizations.of(context).cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          style: FilledButton.styleFrom(
            backgroundColor: HelixStatusColors.danger,
          ),
          child: Text(HelixLocalizations.of(context).delete),
        ),
      ],
    );
  }
}

/// One reviewable list inside the privacy screen - blocked contacts, locked
/// chats. Shows an explicit empty state rather than collapsing to nothing:
/// "no blocked contacts" and "this screen forgot to render" look identical
/// when the card just disappears.
class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.icon,
    required this.title,
    required this.emptyLabel,
    required this.entries,
  });

  final IconData icon;
  final String title;
  final String emptyLabel;
  final List<_ListCardEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(icon),
            title: Text(title),
            trailing: entries.isEmpty ? null : Text('${entries.length}'),
          ),
          if (entries.isEmpty)
            Padding(
              padding: HelixInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  emptyLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            )
          else
            for (final entry in entries)
              ListTile(
                dense: true,
                title: Text(entry.label),
                subtitle: Text(
                  entry.sublabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: TextButton(
                  onPressed: entry.onAction,
                  child: Text(entry.actionLabel),
                ),
              ),
        ],
      ),
    );
  }
}

class _ListCardEntry {
  const _ListCardEntry({
    required this.label,
    required this.sublabel,
    required this.actionLabel,
    required this.onAction,
  });

  final String label;
  final String sublabel;
  final String actionLabel;
  final VoidCallback? onAction;
}
