import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    required this.db,
    required this.restClient,
    required this.tempDir,
  });

  final HelixRemoteDatabase db;
  final HelixRemoteRestClient restClient;
  final String tempDir;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  String? _status;

  Future<void> _createBackup() async {
    setState(() {
      _busy = true;
      _status = 'Creating backup...';
    });
    try {
      final snapshot = widget.db.exportBackupSnapshot();
      final backupId = _randomId();
      final kdf = 'pbkdf2-sha256';
      final salt = base64Url.encode(
        List<int>.generate(16, (_) => Random.secure().nextInt(256)),
      );
      await widget.restClient.uploadBackup(
        backupId: backupId,
        backupData: snapshot,
        version: 1,
        kdf: kdf,
        salt: salt,
      );
      setState(() => _status = 'Backup created successfully (ID: $backupId)');
    } catch (e) {
      setState(() => _status = 'Backup failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    setState(() {
      _busy = true;
      _status = 'Downloading backup...';
    });
    try {
      final backup = await widget.restClient.downloadBackup();
      final backupData = backup['backup_data'] as String;
      widget.db.restoreBackupSnapshot(backupData);
      setState(() => _status = 'Backup restored successfully');
    } catch (e) {
      setState(() => _status = 'Restore failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  String _randomId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.upload),
                title: const Text('Create Backup'),
                subtitle: const Text('Export all data to the server'),
                enabled: !_busy,
                onTap: _createBackup,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Restore Backup'),
                subtitle: const Text('Download and restore from server'),
                enabled: !_busy,
                onTap: _restoreBackup,
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
