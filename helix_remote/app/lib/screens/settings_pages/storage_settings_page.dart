import 'dart:io';

import 'package:flutter/material.dart';
import 'package:helix_remote/screens/settings_pages/settings_page_kit.dart';
import 'package:helix_remote/services/app_logger.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// How much space Helix uses on this phone, and clean-up for what is safe to
/// remove.
///
/// Media is shown but deliberately not clearable: the server keeps
/// attachments for a limited time, so a cleared file past that window could
/// never be downloaded again, and the same folder holds uploads in progress.
class StorageSettingsPage extends StatefulWidget {
  const StorageSettingsPage({
    super.key,
    required this.attachmentCacheDir,
    required this.databaseDir,
  });

  final String attachmentCacheDir;
  final String databaseDir;

  @override
  State<StorageSettingsPage> createState() => _StorageSettingsPageState();
}

class _StorageSettingsPageState extends State<StorageSettingsPage> {
  int? _media;
  int? _database;
  int? _exports;
  int? _logs;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  static Future<int> _sizeOf(
    Directory dir, {
    bool Function(File)? where,
  }) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && (where == null || where(entity))) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  Future<Directory> _exportDir() async => Directory(
    p.join(
      (await getApplicationDocumentsDirectory()).path,
      'helix_remote_exports',
    ),
  );

  Future<void> _measure() async {
    final media = await _sizeOf(Directory(widget.attachmentCacheDir));
    final database = await _sizeOf(
      Directory(widget.databaseDir),
      where: (f) => p.basename(f.path).contains('.db'),
    );
    final exports = await _sizeOf(await _exportDir());
    final logFile = await AppLogger.instance.getLogFile();
    final logs = logFile == null ? 0 : await logFile.length();
    if (!mounted) return;
    setState(() {
      _media = media;
      _database = database;
      _exports = exports;
      _logs = logs;
    });
  }

  static String formatBytes(int? bytes) {
    if (bytes == null) return '…';
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[unit]}';
  }

  Future<void> _clear({
    required String title,
    required String body,
    required Future<void> Function() action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(MaterialLocalizations.of(ctx).deleteButtonTooltip),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      await _measure();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = [_media, _database, _exports, _logs].every((v) => v != null)
        ? _media! + _database! + _exports! + _logs!
        : null;
    return SettingsPage(
      title: 'Storage and data',
      children: [
        SettingsSection(
          title: 'Used on this phone',
          footer:
              'Media is kept so photos, videos and files open without '
              'downloading again. It isn\'t cleared here because the server '
              'keeps attachments for a limited time - once that passes, a '
              'deleted copy can\'t be recovered. Delete a chat to remove its '
              'media.',
          children: [
            SettingsTile(
              icon: Icons.pie_chart_outline,
              color: HelixColorTokens.cFF4F46E5,
              title: 'Total',
              value: formatBytes(total),
            ),
            SettingsTile(
              icon: Icons.perm_media_outlined,
              color: HelixColorTokens.cFF0EA5E9,
              title: 'Media and files',
              value: formatBytes(_media),
            ),
            SettingsTile(
              icon: Icons.chat_outlined,
              color: HelixColorTokens.cFF2FA84F,
              title: 'Messages and chats',
              subtitle: 'Encrypted message database',
              value: formatBytes(_database),
            ),
          ],
        ),
        SettingsSection(
          title: 'Safe to delete',
          children: [
            SettingsTile(
              icon: Icons.file_download_outlined,
              color: HelixColorTokens.cFFF97316,
              title: 'Exported data files',
              subtitle: 'Copies made with "Export my data"',
              value: formatBytes(_exports),
              onTap: _busy || (_exports ?? 0) == 0
                  ? null
                  : () => _clear(
                      title: 'Delete exported data files?',
                      body:
                          'Removes the export files saved on this phone. Your '
                          'account and messages are not affected.',
                      action: () async {
                        final dir = await _exportDir();
                        if (await dir.exists()) {
                          await dir.delete(recursive: true);
                        }
                      },
                    ),
            ),
            SettingsTile(
              icon: Icons.bug_report_outlined,
              color: HelixColorTokens.cFF6D6AAE,
              title: 'Diagnostic logs',
              value: formatBytes(_logs),
              onTap: _busy || (_logs ?? 0) == 0
                  ? null
                  : () => _clear(
                      title: 'Delete diagnostic logs?',
                      body:
                          'Removes the local error log. Export it first from '
                          'Diagnostics if you are sending it to support.',
                      action: AppLogger.instance.clearLogs,
                    ),
            ),
          ],
        ),
      ],
    );
  }
}
