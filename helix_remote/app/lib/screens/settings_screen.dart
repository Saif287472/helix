import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_attachment_service.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/screens/backup_screen.dart';
import 'package:helix_remote/screens/contacts_screen.dart';
import 'package:helix_remote/screens/device_management_screen.dart';
import 'package:helix_remote/screens/groups_screen.dart';
import 'package:helix_remote/screens/privacy_screen.dart';
import 'package:helix_remote/screens/profile_screen.dart';
import 'package:helix_remote/services/app_logger.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// Display name the server's admin chose, once fetched. Null until then,
  /// or when the server has no name - either way the screen shows the host,
  /// so nothing waits on this.
  String? _serverName;

  @override
  void initState() {
    super.initState();
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
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
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
      return widget.root.messagingService.changes;
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

  void _openContacts() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContactsScreen(
          messagingService: widget.messagingService,
          root: widget.root,
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
    final accountId = widget.messagingService.currentAccountId ?? '';
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

  void _showSoon(String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$title is not available in this build yet.')),
    );
  }

  int _acceptedContacts() {
    try {
      return widget.messagingService.acceptedContacts().length;
    } catch (_) {
      return 0;
    }
  }

  int _blockedContacts() {
    try {
      return widget.messagingService.db
          .getContacts()
          .where((contact) => contact.status == 'Blocked')
          .length;
    } catch (_) {
      return 0;
    }
  }

  int _groupCount() {
    try {
      return widget.messagingService.conversationListByKind('groups').length;
    } catch (_) {
      try {
        return widget.messagingService
            .conversationList()
            .where((conversation) => conversation.type == 'Group')
            .length;
      } catch (_) {
        return 0;
      }
    }
  }

  int _archivedCount() {
    return 0;
  }

  int _lockedCount() {
    try {
      return widget.messagingService.db.getLockedConversations().length;
    } catch (_) {
      return 0;
    }
  }

  List<_SettingsGroup> _settingsGroups(Uri serverUri) {
    final db = widget.messagingService.db;
    final appLock = db.getAppLockSettings();
    final defaultDisappearing = db.getAccountDefaultDisappearingSeconds();
    final previewsOn = db.getNotificationPreviewsEnabled();
    final silenceUnknown = db.getSilenceUnknownCallers();
    final host = serverUri.host.isEmpty ? serverUri.toString() : serverUri.host;

    return [
      _SettingsGroup(
        title: 'Account and devices',
        items: [
          _SettingsItem(
            icon: Icons.person_outline,
            color: const Color(0xFF3B82F6),
            title: 'Account',
            subtitle: 'Profile name and account ID',
            onTap: _openProfile,
          ),
          _SettingsItem(
            icon: Icons.devices_outlined,
            color: const Color(0xFF5B6EE1),
            title: 'Linked devices',
            subtitle: 'View and manage connected devices',
            onTap: _openDevices,
          ),
          _SettingsItem(
            icon: Icons.password_outlined,
            color: const Color(0xFF11A37F),
            title: 'Passkeys and authentication',
            subtitle: 'Account lock and strongest privacy defaults',
            value: appLock.enabled ? 'Lock on' : 'Lock off',
            onTap: _openPrivacy,
          ),
          _SettingsItem(
            icon: Icons.backup_outlined,
            color: const Color(0xFF2FA84F),
            title: 'Backup and restore',
            subtitle: 'Create encrypted backups or restore this device',
            onTap: _openBackup,
          ),
        ],
      ),
      _SettingsGroup(
        title: 'Privacy and security',
        items: [
          _SettingsItem(
            icon: Icons.privacy_tip_outlined,
            color: const Color(0xFF7C3AED),
            title: 'Privacy',
            subtitle: 'Export data, strict settings and privacy checkup',
            onTap: _openPrivacy,
          ),
          _SettingsItem(
            icon: Icons.lock_outline,
            color: const Color(0xFF2563EB),
            title: 'Chat lock',
            subtitle: 'Protect private chats and app access',
            value: _lockedCount() > 0 ? '${_lockedCount()}' : 'Off',
            onTap: _openPrivacy,
          ),
          _SettingsItem(
            icon: Icons.block_outlined,
            color: const Color(0xFFE11D48),
            title: 'Blocked contacts',
            subtitle: 'People blocked from contacting you',
            value: '${_blockedContacts()}',
            onTap: _openPrivacy,
          ),
          _SettingsItem(
            icon: Icons.timer_outlined,
            color: const Color(0xFFF59E0B),
            title: 'Disappearing messages',
            subtitle: 'Default timer for new conversations',
            value: _disappearingLabel(defaultDisappearing),
            onTap: _openPrivacy,
          ),
          _SettingsItem(
            icon: Icons.verified_user_outlined,
            color: const Color(0xFF14B8A6),
            title: 'Security notifications',
            subtitle: 'Review privacy checkup and account protections',
            onTap: _openPrivacy,
          ),
        ],
      ),
      _SettingsGroup(
        title: 'Chats and appearance',
        items: [
          _SettingsItem(
            icon: Icons.chat_bubble_outline,
            color: const Color(0xFF22C55E),
            title: 'Chats',
            subtitle: 'History, locked chats and message behavior',
            onTap: _openPrivacy,
          ),
          _SettingsItem(
            icon: Icons.palette_outlined,
            color: const Color(0xFFEC4899),
            title: 'Appearance',
            subtitle: 'App theme and chat presentation',
            value: 'System',
            onTap: () => _showSoon('Appearance'),
          ),
          _SettingsItem(
            icon: Icons.wallpaper_outlined,
            color: const Color(0xFFF97316),
            title: 'Chat themes and wallpaper',
            subtitle: 'Conversation color and background options',
            onTap: () => _showSoon('Chat themes and wallpaper'),
          ),
          _SettingsItem(
            icon: Icons.format_list_bulleted_outlined,
            color: const Color(0xFF06B6D4),
            title: 'Lists',
            subtitle: 'Organize favorites and chat lists',
            onTap: () => _showSoon('Lists'),
          ),
          _SettingsItem(
            icon: Icons.archive_outlined,
            color: const Color(0xFF64748B),
            title: 'Archived chats',
            subtitle: 'Chats hidden from your main list',
            value: '${_archivedCount()}',
            onTap: () => _showSoon('Archived chats'),
          ),
        ],
      ),
      _SettingsGroup(
        title: 'Notifications and calls',
        items: [
          _SettingsItem(
            icon: Icons.notifications_none_outlined,
            color: const Color(0xFFF24E1E),
            title: 'Notifications',
            subtitle: 'Message, group and call notification previews',
            value: previewsOn ? 'Preview on' : 'Private',
            onTap: _openPrivacy,
          ),
          _SettingsItem(
            icon: Icons.call_outlined,
            color: const Color(0xFF10B981),
            title: 'Call settings',
            subtitle: 'Unknown callers and voice/video call behavior',
            value: silenceUnknown ? 'Silenced' : 'Ring',
            onTap: _openPrivacy,
          ),
          _SettingsItem(
            icon: Icons.volume_up_outlined,
            color: const Color(0xFF8B5CF6),
            title: 'Sounds and vibration',
            subtitle: 'Ringtones, alerts and vibration patterns',
            onTap: () => _showSoon('Sounds and vibration'),
          ),
        ],
      ),
      _SettingsGroup(
        title: 'Storage and data',
        items: [
          _SettingsItem(
            icon: Icons.storage_outlined,
            color: const Color(0xFF0EA5E9),
            title: 'Manage storage',
            subtitle: 'Review local media and cache usage',
            onTap: () => _showSoon('Manage storage'),
          ),
          _SettingsItem(
            icon: Icons.network_check_outlined,
            color: const Color(0xFF6366F1),
            title: 'Network usage',
            subtitle: 'Connection and transfer diagnostics',
            onTap: _showServerInfo,
          ),
          _SettingsItem(
            icon: Icons.download_outlined,
            color: const Color(0xFF059669),
            title: 'Media auto-download',
            subtitle: 'Control automatic attachment downloads',
            onTap: () => _showSoon('Media auto-download'),
          ),
          _SettingsItem(
            icon: Icons.data_saver_on_outlined,
            color: const Color(0xFF0891B2),
            title: 'Data-saving settings',
            subtitle: 'Reduce media and call data usage',
            onTap: () => _showSoon('Data-saving settings'),
          ),
        ],
      ),
      _SettingsGroup(
        title: 'Contacts and groups',
        items: [
          _SettingsItem(
            icon: Icons.contacts_outlined,
            color: const Color(0xFF3B82F6),
            title: 'Contacts',
            subtitle: 'Manage Helix contacts and requests',
            value: '${_acceptedContacts()}',
            onTap: _openContacts,
          ),
          _SettingsItem(
            icon: Icons.groups_outlined,
            color: const Color(0xFF14B8A6),
            title: 'Groups',
            subtitle: 'Manage group conversations, invites and roles',
            value: '${_groupCount()}',
            onTap: _openGroups,
          ),
        ],
      ),
      _SettingsGroup(
        title: 'App preferences',
        items: [
          _SettingsItem(
            icon: Icons.accessibility_new_outlined,
            color: const Color(0xFF65A30D),
            title: 'Accessibility',
            subtitle: 'Contrast, motion and readable layout preferences',
            onTap: () => _showSoon('Accessibility'),
          ),
          _SettingsItem(
            icon: Icons.language_outlined,
            color: const Color(0xFF0F766E),
            title: 'App language',
            subtitle: "English (device's language)",
            value: 'System',
            onTap: () => _showSoon('App language'),
          ),
        ],
      ),
      _SettingsGroup(
        title: 'Support and system',
        items: [
          _SettingsItem(
            icon: Icons.help_outline,
            color: const Color(0xFF06B6D4),
            title: 'Help and feedback',
            subtitle: 'Help center, support and product feedback',
            onTap: () => _showSoon('Help and feedback'),
          ),
          _SettingsItem(
            icon: Icons.bug_report_outlined,
            color: const Color(0xFFF97316),
            title: 'Diagnostics and logs',
            subtitle: 'Export and clear Helix anomaly logs',
            trailingIcon: Icons.ios_share_outlined,
            onTap: _exportLog,
          ),
          _SettingsItem(
            icon: Icons.dns_outlined,
            color: const Color(0xFF4F46E5),
            title: 'Server connection',
            // The admin's name for the server when they set one, with the
            // host kept alongside it - the name is friendlier, but the
            // address is what actually identifies where data goes.
            subtitle: _serverName == null ? host : '$_serverName  ·  $host',
            onTap: widget.onChangeServerUrl == null
                ? _showServerInfo
                : _confirmChangeServer,
          ),
          _SettingsItem(
            icon: Icons.system_update_alt_outlined,
            color: const Color(0xFF3B82F6),
            title: 'App updates',
            subtitle: 'Check build and update information',
            onTap: _showAboutHelix,
          ),
          _SettingsItem(
            icon: Icons.info_outline,
            color: const Color(0xFF6D6AAE),
            title: 'About Helix',
            subtitle: 'Version, privacy and app information',
            onTap: _showAboutHelix,
          ),
        ],
      ),
    ];
  }

  List<_SettingsGroup> _filteredGroups(Uri serverUri) {
    final groups = _settingsGroups(serverUri);
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return groups;
    return [
      for (final group in groups)
        _SettingsGroup(
          title: group.title,
          items: group.items
              .where(
                (item) =>
                    item.title.toLowerCase().contains(q) ||
                    item.subtitle.toLowerCase().contains(q) ||
                    group.title.toLowerCase().contains(q),
              )
              .toList(),
        ),
    ].where((group) => group.items.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final serverUri = widget.root.devConfig.restBaseUri;
    final rawDisplayName = widget.messagingService.currentDisplayName ?? '';
    final accountId = widget.messagingService.currentAccountId ?? '';
    final displayName = rawDisplayName.isNotEmpty ? rawDisplayName : 'Account';
    final groups = _filteredGroups(serverUri);
    final destructiveItems = [
      _SettingsItem(
        icon: Icons.logout,
        color: const Color(0xFFDC2626),
        title: 'Log out',
        subtitle: 'Clear this device session',
        isDestructive: true,
        onTap: _confirmLogout,
      ),
      _SettingsItem(
        icon: Icons.delete_forever_outlined,
        color: const Color(0xFFB91C1C),
        title: 'Delete account',
        subtitle: 'Permanently delete your Helix account',
        isDestructive: true,
        onTap: _openPrivacy,
      ),
    ].where(_matchesSearch).toList();

    return Scaffold(
      backgroundColor: _settingsPageColor(theme, cs),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            _SettingsSearchField(
              controller: _searchController,
              query: _query,
              onChanged: (value) => setState(() => _query = value),
              onClear: () {
                _searchController.clear();
                setState(() => _query = '');
              },
            ),
            const SizedBox(height: 10),
            _ProfileCard(
              displayName: displayName,
              accountId: accountId,
              serverUri: serverUri,
              onTap: _openProfile,
              onQrTap: () => _showAccountCode(displayName),
              onEditTap: _openProfile,
            ),
            const SizedBox(height: 18),
            if (_query.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  groups.isEmpty && destructiveItems.isEmpty
                      ? 'No settings found'
                      : 'Search results',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            for (final group in groups) ...[
              _OneUiSettingsCard(group: group),
              const SizedBox(height: 14),
            ],
            if (destructiveItems.isNotEmpty) ...[
              _OneUiSettingsCard(
                group: _SettingsGroup(
                  title: 'Account actions',
                  items: destructiveItems,
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (groups.isEmpty && destructiveItems.isEmpty)
              _EmptySearchState(query: _query),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  bool _matchesSearch(_SettingsItem item) {
    final q = _query.trim().toLowerCase();
    return q.isEmpty ||
        item.title.toLowerCase().contains(q) ||
        item.subtitle.toLowerCase().contains(q);
  }

  static String _disappearingLabel(int seconds) {
    return switch (seconds) {
      0 => 'Off',
      86400 => '24h',
      604800 => '7d',
      7776000 => '90d',
      _ => '${(seconds / 86400).round()}d',
    };
  }
}

class _SettingsSearchField extends StatelessWidget {
  const _SettingsSearchField({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      height: 52,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search settings',
          prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                ),
          filled: true,
          fillColor: _settingsCardColor(theme, cs),
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.displayName,
    required this.accountId,
    required this.serverUri,
    required this.onTap,
    required this.onQrTap,
    required this.onEditTap,
  });

  final String displayName;
  final String accountId;
  final Uri serverUri;
  final VoidCallback onTap;
  final VoidCallback onQrTap;
  final VoidCallback onEditTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accountLabel = accountId.isNotEmpty
        ? _shortId(accountId)
        : 'Helix account';
    final serverLabel = serverUri.host.isNotEmpty
        ? serverUri.host
        : serverUri.toString();

    return Material(
      color: _settingsCardColor(theme, cs),
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 31,
                backgroundColor: cs.primaryContainer,
                child: Text(
                  _initials(displayName),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      accountLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Available on $serverLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Show Helix code',
                onPressed: onQrTap,
                icon: const Icon(Icons.qr_code_2),
              ),
              IconButton(
                tooltip: 'Edit profile',
                onPressed: onEditTap,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _initials(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'H';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length > 1) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return trimmed.substring(0, trimmed.length.clamp(1, 2)).toUpperCase();
  }

  static String _shortId(String accountId) {
    if (accountId.length <= 14) return accountId;
    return '${accountId.substring(0, 7)}...${accountId.substring(accountId.length - 4)}';
  }
}

class _OneUiSettingsCard extends StatelessWidget {
  const _OneUiSettingsCard({required this.group});

  final _SettingsGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      label: group.title,
      child: Material(
        color: _settingsCardColor(theme, cs),
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < group.items.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 76,
                  endIndent: 28,
                  color: cs.outlineVariant.withAlpha(
                    theme.brightness == Brightness.dark ? 56 : 110,
                  ),
                ),
              _SettingsRow(item: group.items[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.item});

  final _SettingsItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final titleColor = item.isDestructive ? cs.error : cs.onSurface;
    final subtitleColor = item.isDestructive
        ? cs.error.withAlpha(theme.brightness == Brightness.dark ? 210 : 190)
        : cs.onSurfaceVariant;

    return InkWell(
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 16, 18, 16),
        child: Row(
          children: [
            _CategoryIcon(icon: item.icon, color: item.color),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 15,
                      height: 1.14,
                      fontWeight: FontWeight.w500,
                      color: titleColor,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 15.5,
                      height: 1.2,
                      color: subtitleColor,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (item.value != null)
              Flexible(
                flex: 0,
                child: Text(
                  item.value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (item.trailingIcon != null) ...[
              const SizedBox(width: 6),
              Icon(item.trailingIcon, color: cs.onSurfaceVariant, size: 22),
            ] else ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                color: cs.onSurfaceVariant.withAlpha(180),
                size: 24,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: Icon(icon, color: Colors.white, size: 23),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      decoration: BoxDecoration(
        color: _settingsCardColor(theme, cs),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 42, color: cs.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            'No settings match "$query"',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try a different title or description.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup {
  const _SettingsGroup({required this.title, required this.items});

  final String title;
  final List<_SettingsItem> items;
}

class _SettingsItem {
  const _SettingsItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.value,
    this.trailingIcon,
    this.isDestructive = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? value;
  final IconData? trailingIcon;
  final bool isDestructive;
}

Color _settingsPageColor(ThemeData theme, ColorScheme cs) {
  if (theme.brightness == Brightness.dark) {
    return Color.alphaBlend(cs.surfaceTint.withAlpha(8), cs.surface);
  }
  return Color.alphaBlend(cs.primary.withAlpha(5), cs.surfaceContainerLowest);
}

Color _settingsCardColor(ThemeData theme, ColorScheme cs) {
  if (theme.brightness == Brightness.dark) {
    return Color.alphaBlend(
      cs.surfaceTint.withAlpha(14),
      cs.surfaceContainerLow,
    );
  }
  return cs.surfaceContainerLowest;
}
