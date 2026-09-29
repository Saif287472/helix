import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:helix_remote/services/screen_security.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_crypto/helix_remote_crypto.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    required this.db,
    required this.restClient,
    required this.tempDir,
    this.onBeforeRestore,
    this.onAfterRestore,
  });

  final HelixRemoteDatabase db;
  final HelixRemoteRestClient restClient;
  final String tempDir;

  /// Called before the restore begins; should quiesce WS/calls/sync.
  final Future<void> Function()? onBeforeRestore;

  /// Called after restore completes (success or failure); should reconnect.
  final Future<void> Function()? onAfterRestore;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen>
    with SecureScreenStateMixin {
  bool _busy = false;
  String? _status;
  int? _lastBackupSize;
  int? _lastBackupCreatedAt;
  String? _lastBackupKdf;
  final RemoteBackupCrypto _backupCrypto = RemoteBackupCrypto();

  Future<void> _createBackup() async {
    final passphrase = await _promptRecoverySecret(
      title: 'Create Backup',
      action: 'Encrypt Backup',
    );
    if (passphrase == null) return;
    setState(() {
      _busy = true;
      _status = 'Creating backup...';
    });
    try {
      final snapshot = widget.db.exportBackupSnapshot();
      final snapshotBytes = Uint8List.fromList(utf8.encode(snapshot));
      final backupId = _randomId();
      final envelope = await _backupCrypto.encryptBackupEnvelope(
        plaintext: snapshotBytes,
        passphrase: passphrase,
        backupId: backupId,
        backupKeyHint: 'User-held recovery secret required',
      );
      await widget.restClient.uploadBackup(
        backupId: backupId,
        backupData: jsonEncode(envelope.toJson()),
        version: envelope.version,
        kdf: envelope.kdf,
        salt: base64Url.encode(envelope.salt),
        backupKeyHint: envelope.backupKeyHint,
        deletionWatermark: envelope.deletionWatermark,
      );
      if (mounted) {
        setState(() {
          _lastBackupSize = snapshotBytes.length;
          _lastBackupCreatedAt = envelope.createdAt;
          _lastBackupKdf = envelope.kdf;
          _status = 'Backup created successfully (ID: $backupId)';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = 'Backup failed. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    final passphrase = await _promptRecoverySecret(
      title: 'Restore Backup',
      action: 'Decrypt Backup',
    );
    if (passphrase == null) return;
    setState(() {
      _busy = true;
      _status = 'Quiescing runtime before restore…';
    });
    await widget.onBeforeRestore?.call();
    try {
      if (mounted) setState(() => _status = 'Downloading backup…');
      final backup = await widget.restClient.downloadBackup();
      final backupData = backup['backup_data'] as String;
      final envelope = RemoteBackupEnvelope.fromJson(
        jsonDecode(backupData) as Map<String, dynamic>,
      );
      if (envelope.restoreSemantics != 'replace_local_state') {
        throw UnsupportedError('Unsupported restore semantics');
      }
      if (mounted) setState(() => _status = 'Decrypting…');
      final plaintext = await _backupCrypto.decryptBackupEnvelope(
        envelope,
        passphrase: passphrase,
      );
      final snapshot = utf8.decode(plaintext);
      if (mounted) setState(() => _status = 'Validating backup in staging…');
      widget.db.validateBackupSnapshot(snapshot);
      _validateSnapshotInStaging(snapshot);
      if (mounted) setState(() => _status = 'Restoring…');
      widget.db.restoreBackupSnapshot(snapshot);
      if (mounted) {
        setState(
          () => _status =
              'Backup restored. Services reconnecting — '
              'close and reopen the app to see fully updated data.',
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e is UnsupportedError
            ? 'Restore failed: backup format is not supported by this version of Helix.'
            : 'Restore failed. Check your connection and recovery secret, then try again.';
        setState(() => _status = msg);
      }
    } finally {
      await widget.onAfterRestore?.call();
      if (mounted) setState(() => _busy = false);
    }
  }

  String _randomId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<String?> _promptRecoverySecret({
    required String title,
    required String action,
  }) async {
    final secret = await showDialog<String>(
      context: context,
      builder: (ctx) =>
          _RecoverySecretDialog(title: title, actionLabel: action),
    );
    if (secret == null || secret.trim().isEmpty) return null;
    return secret.trim();
  }

  void _validateSnapshotInStaging(String snapshot) {
    final staging = HelixRemoteDatabase(File(':memory:'));
    staging.initialize();
    try {
      staging.restoreBackupSnapshot(snapshot);
    } finally {
      staging.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: HelixInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.upload),
                  title: const Text('Create Backup'),
                  subtitle: const Text(
                    'Encrypt app data with Argon2id recovery protection',
                  ),
                  enabled: !_busy,
                  onTap: _createBackup,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Restore Backup'),
                  subtitle: const Text(
                    'Decrypt, stage-validate, then replace local state',
                  ),
                  enabled: !_busy,
                  onTap: _restoreBackup,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: const Text('Backup Status'),
                  subtitle: Text(_backupStatusText()),
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

  String _backupStatusText() {
    if (_lastBackupCreatedAt == null) {
      return 'No successful backup in this session.';
    }
    final created = DateTime.fromMillisecondsSinceEpoch(
      _lastBackupCreatedAt!,
    ).toLocal();
    final size = _lastBackupSize ?? 0;
    final kdf = _lastBackupKdf ?? RemoteBackupCrypto.currentKdf;
    return 'Last backup: $created | $size bytes | $kdf | recovery secret';
  }
}

class _RecoverySecretDialog extends StatefulWidget {
  const _RecoverySecretDialog({required this.title, required this.actionLabel});
  final String title;
  final String actionLabel;
  @override
  State<_RecoverySecretDialog> createState() => _RecoverySecretDialogState();
}

class _RecoverySecretDialogState extends State<_RecoverySecretDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Recovery secret'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
