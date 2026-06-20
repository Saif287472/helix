import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({
    super.key,
    required this.restClient,
    required this.messagingService,
    this.onAccountDeleted,
  });

  final HelixRemoteRestClient restClient;
  final RemoteMessagingService messagingService;
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
      setState(
        () => _status =
            'Export saved to ${file.path}. External files are outside app wipe guarantees.',
      );
    } catch (e) {
      setState(() => _status = 'Export failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount() async {
    final accountId = widget.messagingService.currentAccountId;
    if (accountId == null) {
      setState(() => _status = 'Not logged in');
      return;
    }
    final controller = TextEditingController();
    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type DELETE $accountId to confirm.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Confirmation'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (confirmed == null) return;
    if (confirmed != 'DELETE $accountId') {
      setState(() => _status = 'Deletion confirmation did not match');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Deleting account...';
    });
    try {
      await widget.restClient.requestAccountDeletion(confirmation: confirmed);
      await widget.onAccountDeleted?.call();
      setState(() => _status = 'Account deleted and local app data cleared.');
    } catch (e) {
      setState(() => _status = 'Deletion failed: $e');
    } finally {
      setState(() => _busy = false);
    }
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
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Account')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.file_download),
                title: const Text('Export My Data'),
                subtitle: const Text('Save JSON file outside encrypted app DB'),
                enabled: !_busy,
                onTap: _exportData,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Delete Account'),
                subtitle: const Text('Permanently delete account and all data'),
                enabled: !_busy,
                onTap: _deleteAccount,
              ),
            ),
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
    );
  }
}
