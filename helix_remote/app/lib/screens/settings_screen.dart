import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_attachment_service.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/presentation/settings/settings_view_model.dart';
import 'package:helix_remote/screens/backup_screen.dart';
import 'package:helix_remote/screens/device_management_screen.dart';
import 'package:helix_remote/screens/groups_screen.dart';
import 'package:helix_remote/screens/privacy_screen.dart';
import 'package:helix_remote/screens/profile_screen.dart';
import 'package:helix_remote/services/app_logger.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

part 'settings/actions.dart';
part 'settings/widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.root,
    required this.messagingService,
    this.onChangeServerUrl,
  });

  final RemoteCompositionRoot root;
  final RemoteMessagingService messagingService;
  final Future<void> Function()? onChangeServerUrl;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsViewModel _viewModel;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// Display name the server's admin chose, once fetched. Null until then,
  /// or when the server has no name - either way the screen shows the host,
  /// so nothing waits on this.
  String? _serverName;

  @override
  void initState() {
    super.initState();
    _viewModel = SettingsViewModel(widget.messagingService);
    _loadServerName();
  }

  Future<void> _loadServerName() async {
    try {
      final info = await widget.root.restClient.getServerInfo();
      final name = (info['server_name'] as String? ?? '').trim();
      if (!mounted || name.isEmpty) return;
      setState(() => _serverName = name);
    } catch (_) {
      // Cosmetic: an older server without the endpoint, or a offline
      // launch, just leaves the host showing.
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _exportLog() async {
    final file = await AppLogger.instance.getLogFile();
    if (!mounted) return;
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No anomalies recorded yet.')),
      );
      return;
    }

    if (Platform.isWindows) {
      try {
        final docs = await getApplicationDocumentsDirectory();
        final destDir = Directory(p.join(docs.path, 'Helix Remote'));
        await destDir.create(recursive: true);
        final dest = p.join(destDir.path, 'helix_remote_log.txt');
        await file.copy(dest);
        await AppLogger.instance.clearLogs();
        await Process.run('explorer', ['/select,', dest]);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Log saved to Documents\\Helix Remote\\'),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
      return;
    }

    // Android: ChooserActivity crashes on BlueStacks / Android 9 with a native
    // NullPointerException that kills the process before Dart can catch it.
    // Skip share_plus entirely on Android and show the in-app viewer directly.
    if (Platform.isAndroid) {
      await _showLogFallback(file);
      return;
    }

    ShareResult? shareResult;
    try {
      shareResult = await SharePlus.instance
          .share(
            ShareParams(
              files: [
                XFile(
                  file.path,
                  name: 'helix_remote_log.txt',
                  mimeType: 'text/plain',
                ),
              ],
              subject: 'Helix Remote Anomaly Log',
            ),
          )
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      shareResult = null;
    } catch (_) {
      shareResult = null;
    }

    if (!mounted) return;

    if (shareResult?.status == ShareResultStatus.success) {
      await AppLogger.instance.clearLogs();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Log exported and cleared.')),
      );
      return;
    }

    await _showLogFallback(file);
  }

  Future<void> _showLogFallback(File file) async {
    String content;
    try {
      content = await file.readAsString();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not read log: $e')));
      return;
    }
    if (!mounted) return;

    String? savedPath;
    if (Platform.isAndroid) {
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final dest = File(p.join(extDir.path, 'helix_remote_log.txt'));
          await dest.writeAsString(content);
          savedPath = dest.path;
        }
      } catch (_) {}
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anomaly Log'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (savedPath != null) ...[
                SelectableText(
                  'Saved to:\n$savedPath',
                  style: const TextStyle(
                    fontSize: 10,
                    color: HelixStatusColors.neutral,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    content,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          if (Platform.isAndroid)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await SharePlus.instance.share(
                  ShareParams(
                    files: [
                      XFile(
                        file.path,
                        name: 'helix_remote_log.txt',
                        mimeType: 'text/plain',
                      ),
                    ],
                    subject: 'Helix Remote Anomaly Log',
                  ),
                );
              },
              child: const Text('Share...'),
            ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: content));
              await AppLogger.instance.clearLogs();
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    duration: const Duration(seconds: 8),
                    content: Text(
                      Platform.isAndroid
                          ? 'Log cleared. Long-press the text above, select all, copy, then close.'
                          : 'Log copied to clipboard and cleared.',
                    ),
                  ),
                );
              }
            },
            child: const Text('Copy & clear'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmChangeServer() async {
    final serverHost = widget.root.devConfig.restBaseUri.host;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Server URL'),
        content: Text(
          'Currently connected to $serverHost.\n\n'
          'This will disconnect and let you enter a new server URL. '
          'Your local account data is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Change'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    unawaited(widget.onChangeServerUrl!());
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out'),
        content: const Text(
          'This clears the saved session on this device. Your account and '
          'server data are not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.root.logout();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Stream<RemoteSyncChange>? _tryMessagingChanges() {
    try {
      return _viewModel.changes;
    } catch (_) {
      return null;
    }
  }

  RemoteAttachmentService? _tryAttachmentService() {
    try {
      return widget.root.attachmentService;
    } catch (_) {
      return null;
    }
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          root: widget.root,
          messagingService: widget.messagingService,
        ),
      ),
    );
  }

  void _openDevices() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeviceManagementScreen(
          restClient: widget.root.restClient,
          deviceChanges: _tryMessagingChanges(),
        ),
      ),
    );
  }

  void _openBackup() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BackupScreen(
          db: widget.root.database,
          restClient: widget.root.restClient,
          tempDir: widget.root.devConfig.attachmentCacheDir,
          onBeforeRestore: () async {
            await widget.root.callService.endActiveCall();
            await widget.root.disconnectWebSocket();
          },
          onAfterRestore: widget.root.connectWebSocket,
        ),
      ),
    );
  }

  void _openPrivacy() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrivacyScreen(
          restClient: widget.root.restClient,
          messagingService: widget.messagingService,
          onBeforeDelete: widget.root.disconnectWebSocket,
          onAccountDeleted: widget.root.purgeAfterAccountDeletion,
        ),
      ),
    );
  }

  void _openGroups() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupsScreen(
          groupService: widget.root.groupService,
          messagingService: widget.messagingService,
          attachmentService: _tryAttachmentService(),
        ),
      ),
    );
  }

  void _showServerInfo() {
    final serverUri = widget.root.devConfig.restBaseUri;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server connection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_serverName != null) ...[
              Text(
                _serverName!,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
            ],
            Text('${serverUri.scheme}://${serverUri.host}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAccountCode(String displayName) {
    final accountId = _viewModel.accountId;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$displayName code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 168,
              height: 168,
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.qr_code_2,
                size: 112,
                color: Theme.of(ctx).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              accountId.isEmpty ? 'No account ID available' : accountId,
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          if (accountId.isNotEmpty)
            FilledButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: accountId));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Account ID copied')),
                );
              },
              child: const Text('Copy'),
            ),
        ],
      ),
    );
  }

  void _showAboutHelix() {
    showAboutDialog(
      context: context,
      applicationName: 'Helix Remote',
      applicationVersion: 'Secure remote messaging',
      applicationIcon: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(Icons.bolt, color: Theme.of(context).colorScheme.onPrimary),
      ),
      applicationLegalese: 'Built for private Helix communication.',
    );
  }

  @override
  Widget build(BuildContext context) => _buildScreen(context);

  void _update(VoidCallback change) => setState(change);
}
