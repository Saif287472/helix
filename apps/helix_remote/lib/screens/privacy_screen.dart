import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote_api/api/rest_client.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({
    super.key,
    required this.restClient,
    required this.messagingService,
  });

  final HelixRemoteRestClient restClient;
  final RemoteMessagingService messagingService;

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
      final data = await widget.restClient.exportData();
      final pretty = const JsonEncoder.withIndent('  ').convert(data);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Exported Data'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                pretty,
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      setState(() => _status = 'Data exported successfully');
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
    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: Text('Type DELETE $accountId to confirm:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'DELETE $accountId'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == null) return;
    setState(() {
      _busy = true;
      _status = 'Deleting account...';
    });
    try {
      await widget.restClient.requestAccountDeletion(confirmation: confirmed);
      setState(() => _status = 'Account deleted. Please restart the app.');
    } catch (e) {
      setState(() => _status = 'Deletion failed: $e');
    } finally {
      setState(() => _busy = false);
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
                subtitle: const Text('Download all your data (GDPR export)'),
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
