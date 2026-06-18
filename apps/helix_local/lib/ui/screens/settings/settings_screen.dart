// lib/ui/screens/settings/settings_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:helix_domain/core/constants.dart';
import 'package:helix_domain/domain/models.dart';
import 'package:helix/providers/app_providers.dart';
import 'package:share_plus/share_plus.dart';
import 'package:helix/services/app_logger.dart';
import 'package:helix/ui/app_router.dart';
import 'package:helix/ui/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _newCodeController = TextEditingController();
  final _confirmCodeController = TextEditingController();
  bool _newCodeVisible = false;
  bool _confirmCodeVisible = false;
  String? _newCodeError;
  String? _confirmCodeError;
  bool _savingCode = false;

  bool _resetting = false;

  static String _lockLabel(int minutes) {
    if (minutes == 0) return 'Never';
    return '$minutes min';
  }

  int _versionTapCount = 0;
  DateTime? _lastVersionTap;

  final _ringtonePreviewPlayer = AudioPlayer();
  String? _previewingRingtone;
  StreamSubscription<void>? _onPlayerCompleteSub;

  @override
  void initState() {
    super.initState();
    _onPlayerCompleteSub = _ringtonePreviewPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _previewingRingtone = null);
    });
  }

  @override
  void dispose() {
    _newCodeController.dispose();
    _confirmCodeController.dispose();
    _onPlayerCompleteSub?.cancel();
    _ringtonePreviewPlayer.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Ringtone
  // ---------------------------------------------------------------------------

  String _ringtoneLabel(String assetFile) {
    final base = assetFile.endsWith('.mp3')
        ? assetFile.substring(0, assetFile.length - 4)
        : assetFile;
    return base.replaceAll('_', ' ');
  }

  Future<void> _toggleRingtonePreview(String assetFile) async {
    if (_previewingRingtone == assetFile) {
      if (!mounted) return;
      await _ringtonePreviewPlayer.stop();
      if (!mounted) return;
      setState(() => _previewingRingtone = null);
      return;
    }
    if (!mounted) return;
    await _ringtonePreviewPlayer.stop();
    if (!mounted) return;
    setState(() => _previewingRingtone = assetFile);
    await _ringtonePreviewPlayer.play(AssetSource('sounds/$assetFile'));
  }

  // ---------------------------------------------------------------------------
  // Secret code
  // ---------------------------------------------------------------------------

  Future<void> _saveCode() async {
    final newErr = ref
        .read(profileServiceProvider)
        .validateSecretCode(_newCodeController.text);
    final confirmErr = _confirmCodeController.text != _newCodeController.text
        ? 'Codes do not match.'
        : null;
    setState(() {
      _newCodeError = newErr;
      _confirmCodeError = confirmErr;
    });
    if (newErr != null || confirmErr != null) return;
    setState(() => _savingCode = true);
    try {
      await ref
          .read(profileServiceProvider)
          .updateSecretCode(_newCodeController.text);
      if (mounted) {
        _newCodeController.clear();
        _confirmCodeController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Secret sentence updated.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingCode = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Biometric lock
  // ---------------------------------------------------------------------------

  Future<void> _handleBiometricLockToggle(bool enable) async {
    if (enable) {
      final supported = await LocalAuthentication().isDeviceSupported();
      if (!supported) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No biometric or device PIN/pattern/password is set up. '
                'Set one up in your device settings first, then try again.',
              ),
            ),
          );
        }
        return;
      }
    }
    await ref
        .read(profileServiceProvider)
        .updatePreferences(biometricLock: enable);
  }

  // ---------------------------------------------------------------------------
  // Reset preferences
  // ---------------------------------------------------------------------------

  Future<void> _confirmResetPreferences() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to default settings?'),
        content: const Text(
          'This restores notifications, appearance, privacy, and ringtone '
          'settings to their defaults. Your display name, secret sentence, '
          'device identity, and chats are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(profileServiceProvider).resetPreferencesToDefaults();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings reset to defaults.')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Reset Helix
  // ---------------------------------------------------------------------------

  Future<void> _resetHelix() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Helix?'),
        content: const Text(
          'This will erase your display name, secret sentence, device identity, '
          'and all active sessions. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reset everything'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _resetting = true);
    try {
      await ref.read(trustServiceProvider).clearAllPeers();
      await ref.read(profileServiceProvider).reset();
      if (mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil(AppRoutes.setup, (r) => false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _resetting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Reset failed: $e')));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Panic wipe
  // ---------------------------------------------------------------------------

  Future<void> _exportLog() async {
    final descriptor = ref.read(productDescriptorProvider);
    final file = await AppLogger.instance.getLogFile();
    if (!mounted) return;
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No anomalies recorded yet.')),
      );
      return;
    }

    if (isDesktop) {
      // On Windows, copy to Documents\<AppName>\ and open Explorer there.
      try {
        final docs = await getApplicationDocumentsDirectory();
        final destDir = Directory(p.join(docs.path, descriptor.displayName));
        await destDir.create(recursive: true);
        final dest = p.join(destDir.path, '${descriptor.exportPrefix}.txt');
        await file.copy(dest);
        await AppLogger.instance.clearLogs();
        // Open Explorer with the file selected.
        await Process.run('explorer', ['/select,', dest]);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Log saved to Documents\\${descriptor.displayName}\\')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, name: '${descriptor.exportPrefix}.txt', mimeType: 'text/plain')],
        subject: '${descriptor.displayName} Anomaly Log',
      ),
    );
    await AppLogger.instance.clearLogs();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Log exported and cleared.')),
    );
  }

  void _handleVersionTap() {
    final now = DateTime.now();
    if (_lastVersionTap != null &&
        now.difference(_lastVersionTap!) > const Duration(milliseconds: 500)) {
      _versionTapCount = 0;
    }
    _versionTapCount++;
    _lastVersionTap = now;
    if (_versionTapCount >= 3) {
      _versionTapCount = 0;
      _showPanicWipeDialog();
    }
  }

  Future<void> _showPanicWipeDialog() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Panic Wipe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'WARNING: This will instantly delete ALL data, '
              'including the database and secure storage, then exit the app.',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 16),
            const Text('Type DELETE to confirm:'),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, child) => TextButton(
              onPressed: value.text == 'DELETE'
                  ? () => Navigator.of(ctx).pop(true)
                  : null,
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('WIPE DATA'),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          content: Row(
            children: const [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('Wiping all data...')),
            ],
          ),
        ),
      );

      try {
        final db = await ref.read(databaseProvider.future);
        db.clearAll();
        // Delete only keys scoped to this product's prefix, never all keys.
        // An unscoped deleteAll() would also wipe any Helix Remote keys.
        const storage = FlutterSecureStorage();
        final prefix = ref.read(productDescriptorProvider).secureStoragePrefix;
        final allKeys = await storage.readAll();
        for (final key in allKeys.keys) {
          if (key.startsWith(prefix)) {
            await storage.delete(key: key);
          }
        }
        if (Platform.isAndroid) {
          await SystemNavigator.pop();
        } else {
          exit(0);
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context).pop(); // Dismiss loading dialog
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Wipe Failed'),
              content: Text('Failed to complete panic wipe: $e'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ref.watch(profileProvider).when(
      data: (profile) => _buildContent(context, theme, profile),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text('Error loading profile: $e')),
    );
  }

  // ---------------------------------------------------------------------------
  // Dialogs
  // ---------------------------------------------------------------------------

  void _showEditNameDialog(
      BuildContext context, ThemeData theme, Profile profile) {
    final ctrl = TextEditingController();
    String? nameErr;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          title: const Text('Change display name'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'New display name',
              hintText: profile.displayName,
              errorText: nameErr,
            ),
            onChanged: (v) {
              final err = ref
                  .read(profileServiceProvider)
                  .validateDisplayName(v);
              setDs(() => nameErr = err);
            },
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            TextButton(
              onPressed: nameErr == null && ctrl.text.isNotEmpty
                  ? () async {
                      final name = ctrl.text.trim();
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.of(ctx).pop();
                      try {
                        await ref
                            .read(profileServiceProvider)
                            .updateDisplayName(name);
                        if (mounted) {
                          messenger.showSnackBar(
                            const SnackBar(
                                content: Text('Display name updated.')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          messenger.showSnackBar(
                              SnackBar(content: Text('Error: $e')));
                        }
                      }
                    }
                  : null,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ).whenComplete(ctrl.dispose);
  }

  void _showThemeDialog(BuildContext context, Profile profile) {
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Theme'),
        children: [
          RadioGroup<String>(
            groupValue: profile.themeMode,
            onChanged: (v) {
              if (v != null) {
                ref
                    .read(profileServiceProvider)
                    .updatePreferences(themeMode: v);
                Navigator.of(ctx).pop();
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (mode, label, icon) in const [
                  ('system', 'System default', Icons.brightness_auto_outlined),
                  ('light', 'Light', Icons.light_mode_outlined),
                  ('dark', 'Dark', Icons.dark_mode_outlined),
                ])
                  RadioListTile<String>(
                    value: mode,
                    secondary: Icon(icon),
                    title: Text(label),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAccentDialog(BuildContext context, Profile profile) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accent color'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: HelixAccent.values.map((accent) {
            final selected = profile.accentColor == accent.id;
            return ChoiceChip(
              selected: selected,
              label: Text(accent.label),
              avatar: CircleAvatar(backgroundColor: accent.seed),
              selectedColor: accent.tint,
              onSelected: (_) {
                ref
                    .read(profileServiceProvider)
                    .updatePreferences(accentColor: accent.id);
                Navigator.of(ctx).pop();
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  void _showAutoLockDialog(BuildContext context, Profile profile) {
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Auto-lock after idle'),
        children: [
          RadioGroup<int>(
            groupValue: profile.lockAfterMinutes,
            onChanged: (v) {
              if (v != null) {
                ref
                    .read(profileServiceProvider)
                    .updatePreferences(lockAfterMinutes: v);
                Navigator.of(ctx).pop();
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (value, label) in const [
                  (0, 'Never'),
                  (5, '5 minutes'),
                  (15, '15 minutes'),
                  (30, '30 minutes'),
                ])
                  RadioListTile<int>(value: value, title: Text(label)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showRingtoneSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          builder: (_, scrollController) => Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color:
                      Theme.of(ctx).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Incoming call ringtone',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              Expanded(
                child: Consumer(
                  builder: (ctx, ref, _) {
                    final currentProfile =
                        ref.watch(profileProvider).value;
                    if (currentProfile == null) return const SizedBox();
                    return RadioGroup<String>(
                      groupValue: currentProfile.ringtoneAsset,
                      onChanged: (v) {
                        if (v != null) {
                          ref
                              .read(profileServiceProvider)
                              .updatePreferences(ringtoneAsset: v);
                        }
                      },
                      child: ListView(
                        controller: scrollController,
                        children: kAvailableRingtoneAssets.map((asset) {
                          final isPreviewing = _previewingRingtone == asset;
                          return RadioListTile<String>(
                            dense: true,
                            value: asset,
                            title: Text(_ringtoneLabel(asset)),
                            subtitle: asset == kDefaultRingtoneAsset
                                ? const Text('Default')
                                : null,
                            secondary: IconButton(
                              icon: Icon(
                                isPreviewing
                                    ? Icons.stop_circle_outlined
                                    : Icons.play_circle_outline,
                              ),
                              tooltip:
                                  isPreviewing ? 'Stop preview' : 'Preview',
                              onPressed: () async {
                                await _toggleRingtonePreview(asset);
                                setSheetState(() {});
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSecurityLimitationsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Security limitations'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SecurityLimitationItem(
                  'An attacker with physical access to your device.'),
              _SecurityLimitationItem(
                  'Malicious software already running on this device.'),
              _SecurityLimitationItem(
                  'A peer who deliberately shares or screenshots messages.'),
              _SecurityLimitationItem(
                  'Traffic analysis revealing that two devices are communicating.'),
              _SecurityLimitationItem(
                  'Network-level attackers on the same LAN observing packet metadata.'),
              _SecurityLimitationItem(
                  'Client isolation bypass at the router/access point level.'),
              _SecurityLimitationItem(
                  'Screen capture tools that operate at the OS or GPU level.'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  void _showChangeCodeDialog(BuildContext context, ThemeData theme) {
    _newCodeController.clear();
    _confirmCodeController.clear();
    _newCodeError = null;
    _confirmCodeError = null;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          title: const Text('Change secret sentence'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        try {
                          final phrase = ref
                              .read(profileServiceProvider)
                              .generateDicewarePassphrase();
                          _newCodeController.text = phrase;
                          _confirmCodeController.text = phrase;
                          setDs(() {
                            _newCodeError = null;
                            _confirmCodeError = null;
                          });
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')));
                        }
                      },
                      icon: const Icon(Icons.auto_awesome, size: 14),
                      label: const Text('Generate'),
                      style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _newCodeController,
                  obscureText: !_newCodeVisible,
                  decoration: InputDecoration(
                    labelText: 'New secret sentence',
                    errorText: _newCodeError,
                    suffixIcon: IconButton(
                      icon: Icon(_newCodeVisible
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () => setDs(
                          () => _newCodeVisible = !_newCodeVisible),
                    ),
                  ),
                  onChanged: (v) {
                    final err = ref
                        .read(profileServiceProvider)
                        .validateSecretCode(v);
                    setDs(() => _newCodeError = err);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _confirmCodeController,
                  obscureText: !_confirmCodeVisible,
                  decoration: InputDecoration(
                    labelText: 'Confirm new code',
                    errorText: _confirmCodeError,
                    suffixIcon: IconButton(
                      icon: Icon(_confirmCodeVisible
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () => setDs(
                          () => _confirmCodeVisible = !_confirmCodeVisible),
                    ),
                  ),
                  onChanged: (v) {
                    setDs(() => _confirmCodeError =
                        v != _newCodeController.text
                            ? 'Codes do not match.'
                            : null);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            TextButton(
              onPressed: (_savingCode ||
                      _newCodeController.text.isEmpty ||
                      _confirmCodeController.text.isEmpty ||
                      _newCodeError != null ||
                      _confirmCodeError != null)
                  ? null
                  : () async {
                      Navigator.of(ctx).pop();
                      await _saveCode();
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Trusted devices card
  // ---------------------------------------------------------------------------

  Widget _buildTrustedDevicesCard(ThemeData theme) {
    final trusted =
        ref.watch(knownPeersProvider).value?.where((p) => p.trusted).toList() ??
            [];
    final trust = ref.read(trustServiceProvider);

    if (trusted.isEmpty) {
      return _SettingsCard(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              _SettingsIcon(Icons.verified_user_outlined, color: Colors.teal),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'No trusted devices yet. Open a chat → ⋮ → Verify identity to trust a device.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(160)),
                ),
              ),
            ],
          ),
        ),
      ]);
    }

    return _SettingsCard(
      children: trusted.map((peer) {
        final since =
            '${peer.firstSeenAt.day.toString().padLeft(2, '0')}/'
            '${peer.firstSeenAt.month.toString().padLeft(2, '0')}/'
            '${peer.firstSeenAt.year}';
        return ListTile(
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: Colors.teal.withAlpha(30),
            child: Text(
              (peer.nickname ?? peer.lastPublicName).isNotEmpty
                  ? (peer.nickname ?? peer.lastPublicName)[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.teal),
            ),
          ),
          title: Text(peer.nickname ?? peer.lastPublicName),
          subtitle: Text('Trusted since $since',
              style: theme.textTheme.bodySmall),
          trailing: PopupMenuButton<String>(
            onSelected: (action) async {
              switch (action) {
                case 'rename':
                  final ctrl = TextEditingController(
                      text: peer.nickname ?? peer.lastPublicName);
                  final nick = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Rename device'),
                      content: TextField(
                        controller: ctrl,
                        autofocus: true,
                        decoration:
                            const InputDecoration(labelText: 'Nickname'),
                        onSubmitted: (_) =>
                            Navigator.of(ctx).pop(ctrl.text),
                      ),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.of(ctx).pop(null),
                            child: const Text('Cancel')),
                        FilledButton(
                            onPressed: () =>
                                Navigator.of(ctx).pop(ctrl.text),
                            child: const Text('Save')),
                      ],
                    ),
                  );
                  ctrl.dispose();
                  if (nick != null && nick.trim().isNotEmpty) {
                    await trust.renamePeer(peer.fingerprint, nick.trim());
                  }
                case 'untrust':
                  await trust.untrustPeer(peer.fingerprint);
                case 'forget':
                  await trust.forgetPeer(peer.fingerprint);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(
                  value: 'untrust', child: Text('Remove trust')),
              PopupMenuItem(
                value: 'forget',
                child: Text('Forget device',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Main content
  // ---------------------------------------------------------------------------

  Widget _buildContent(
      BuildContext context, ThemeData theme, Profile profile) {
    final themeModeLabel = switch (profile.themeMode) {
      'light' => 'Light',
      'dark' => 'Dark',
      _ => 'System default',
    };
    final currentAccent = HelixAccent.values.firstWhere(
      (a) => a.id == profile.accentColor,
      orElse: () => HelixAccent.values.first,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // ── Profile ─────────────────────────────────────────────────────────
        Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
                color: theme.colorScheme.outlineVariant.withAlpha(80)),
          ),
          color: theme.colorScheme.primaryContainer.withAlpha(80),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(
                    profile.displayName.isNotEmpty
                        ? profile.displayName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Your display name',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                theme.colorScheme.onSurface.withAlpha(160)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit name',
                  onPressed: () =>
                      _showEditNameDialog(context, theme, profile),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Discoverable ─────────────────────────────────────────────────────
        _SettingsCard(children: [
          SwitchListTile(
            secondary: _SettingsIcon(
              profile.discoverability == DiscoverabilityState.discoverable
                  ? Icons.wifi_tethering
                  : Icons.wifi_tethering_off,
              color: Colors.blue,
            ),
            title: const Text('Discoverable'),
            subtitle:
                const Text('Peers on the same network can find you.'),
            value: profile.discoverability ==
                DiscoverabilityState.discoverable,
            onChanged: (v) async {
              final next = v
                  ? DiscoverabilityState.discoverable
                  : DiscoverabilityState.hidden;
              await ref
                  .read(profileServiceProvider)
                  .updateDiscoverability(next);
              await ref
                  .read(discoveryCoordinatorProvider)
                  .updateDiscoverability(v);
            },
          ),
        ]),
        const SizedBox(height: 20),

        // ── Messaging ────────────────────────────────────────────────────────
        const _SectionLabel('Messaging'),
        _SettingsCard(children: [
          SwitchListTile(
            secondary: _SettingsIcon(Icons.done_all_outlined,
                color: Colors.indigo),
            title: const Text('Read receipts'),
            subtitle:
                const Text('Send read status while a chat is open.'),
            value: profile.readReceiptsEnabled,
            onChanged: (v) => ref
                .read(profileServiceProvider)
                .updatePreferences(readReceiptsEnabled: v),
          ),
          SwitchListTile(
            secondary:
                _SettingsIcon(Icons.more_horiz, color: Colors.indigo),
            title: const Text('Typing indicators'),
            subtitle:
                const Text('Show peers when you\'re composing.'),
            value: profile.typingIndicatorsEnabled,
            onChanged: (v) => ref
                .read(profileServiceProvider)
                .updatePreferences(typingIndicatorsEnabled: v),
          ),
          SwitchListTile(
            secondary: _SettingsIcon(Icons.notifications_outlined,
                color: Colors.orange),
            title: const Text('Show sender in notifications'),
            subtitle: const Text('When off, only shows "New message".'),
            value: profile.notifyShowSender,
            onChanged: (v) => ref
                .read(profileServiceProvider)
                .updatePreferences(notifyShowSender: v),
          ),
          SwitchListTile(
            secondary: _SettingsIcon(Icons.volume_up_outlined,
                color: const Color(0xFF43A047)),
            title: const Text('Message sound'),
            subtitle:
                const Text('Play sound for incoming messages.'),
            value: profile.notifySound,
            onChanged: (v) => ref
                .read(profileServiceProvider)
                .updatePreferences(notifySound: v),
          ),
          SwitchListTile(
            secondary: _SettingsIcon(Icons.content_copy_outlined,
                color: Colors.blueGrey),
            title: const Text('Allow copying messages'),
            subtitle: const Text(
                'Long-press to copy. Clipboard cleared after 30 s.'),
            value: profile.copyEnabled,
            onChanged: (v) async {
              if (v) {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Enable message copying?'),
                    content: const Text(
                      'Clipboard contents may be read by other apps. '
                      'Helix will try to clear the clipboard after 30 seconds.',
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Enable')),
                    ],
                  ),
                );
                if (confirmed != true) return;
              }
              await ref
                  .read(profileServiceProvider)
                  .updatePreferences(copyEnabled: v);
            },
          ),
        ]),
        const SizedBox(height: 20),

        // ── Privacy & Security ───────────────────────────────────────────────
        const _SectionLabel('Privacy & Security'),
        _SettingsCard(children: [
          SwitchListTile(
            secondary:
                _SettingsIcon(Icons.fingerprint, color: Colors.red),
            title: const Text('Biometric lock'),
            subtitle:
                const Text('Require biometrics to open the app.'),
            value: profile.biometricLock,
            onChanged: _handleBiometricLockToggle,
          ),
          ListTile(
            enabled: profile.biometricLock,
            leading: _SettingsIcon(Icons.timer_outlined,
                color: Colors.orange),
            title: const Text('Auto-lock after idle'),
            subtitle: Text(_lockLabel(profile.lockAfterMinutes)),
            trailing: const Icon(Icons.chevron_right),
            onTap: profile.biometricLock
                ? () => _showAutoLockDialog(context, profile)
                : null,
          ),
          SwitchListTile(
            secondary: _SettingsIcon(Icons.screenshot_monitor_outlined,
                color: Colors.purple),
            title: const Text('Screenshot protection'),
            subtitle: const Text(
                'Best-effort — not guaranteed on all platforms.'),
            value: profile.screenshotProtect,
            onChanged: (v) => ref
                .read(profileServiceProvider)
                .updatePreferences(screenshotProtect: v),
          ),
          ListTile(
            leading: _SettingsIcon(Icons.vpn_key_outlined,
                color: Colors.red.shade700),
            title: const Text('Change secret sentence'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showChangeCodeDialog(context, theme),
          ),
        ]),
        const SizedBox(height: 20),

        // ── Appearance ───────────────────────────────────────────────────────
        const _SectionLabel('Appearance'),
        _SettingsCard(children: [
          ListTile(
            leading: _SettingsIcon(Icons.brightness_auto_outlined,
                color: Colors.pink),
            title: const Text('Theme'),
            subtitle: Text(themeModeLabel),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showThemeDialog(context, profile),
          ),
          ListTile(
            leading: _SettingsIcon(Icons.palette_outlined,
                color: Colors.pinkAccent),
            title: const Text('Accent color'),
            subtitle: Text(currentAccent.label),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: currentAccent.seed,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => _showAccentDialog(context, profile),
          ),
          SwitchListTile(
            secondary: _SettingsIcon(Icons.contrast,
                color: Colors.grey.shade800),
            title: const Text('AMOLED black in dark mode'),
            value: profile.amoledDark,
            onChanged: (v) => ref
                .read(profileServiceProvider)
                .updatePreferences(amoledDark: v),
          ),
        ]),
        const SizedBox(height: 20),

        // ── Notifications ────────────────────────────────────────────────────
        const _SectionLabel('Notifications'),
        _SettingsCard(children: [
          ListTile(
            leading: _SettingsIcon(Icons.music_note_outlined,
                color: Colors.teal),
            title: const Text('Incoming call ringtone'),
            subtitle: Text(_ringtoneLabel(profile.ringtoneAsset)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showRingtoneSheet(context),
          ),
        ]),
        const SizedBox(height: 20),

        // ── Advanced ─────────────────────────────────────────────────────────
        const _SectionLabel('Advanced'),
        _SettingsCard(children: [
          ListTile(
            leading: _SettingsIcon(Icons.network_check_outlined,
                color: Colors.blueGrey),
            title: const Text('Network diagnostics'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                Navigator.of(context).pushNamed(AppRoutes.diagnostics),
          ),
          ListTile(
            leading:
                _SettingsIcon(Icons.restart_alt, color: Colors.blueGrey),
            title: const Text('Restart discovery'),
            subtitle: const Text('Rebind local discovery services.'),
            onTap: () async {
              await ref.read(discoveryCoordinatorProvider).restart();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Discovery restart requested.')),
                );
              }
            },
          ),
          ListTile(
            leading: _SettingsIcon(
                Icons.settings_backup_restore_outlined,
                color: Colors.orange),
            title: const Text('Reset to default settings'),
            subtitle: const Text(
                'Restores preferences. Identity and chats are kept.'),
            onTap: _confirmResetPreferences,
          ),
        ]),
        const SizedBox(height: 20),

        // ── Trusted Devices ──────────────────────────────────────────────────
        const _SectionLabel('Trusted Devices'),
        _buildTrustedDevicesCard(theme),
        const SizedBox(height: 20),

        // ── About ────────────────────────────────────────────────────────────
        const _SectionLabel('About'),
        _SettingsCard(children: [
          ListTile(
            leading: _SettingsIcon(Icons.schema_outlined,
                color: Colors.indigo),
            title: const Text('Protocol version'),
            trailing: Text('v$kProtocolMajor.$kProtocolMinor',
                style: theme.textTheme.bodySmall),
          ),
          ListTile(
            leading:
                _SettingsIcon(Icons.apps_outlined, color: Colors.blue),
            title: const Text('App version'),
            trailing: Text('7.2.4', style: theme.textTheme.bodySmall),
            onTap: _handleVersionTap,
          ),
          ListTile(
            leading: _SettingsIcon(Icons.bug_report_outlined,
                color: Colors.deepOrange),
            title: const Text('Anomaly Log'),
            subtitle: const Text('Export & clear device log'),
            trailing: const Icon(Icons.ios_share_outlined),
            onTap: _exportLog,
          ),
          ListTile(
            leading: _SettingsIcon(Icons.security_outlined,
                color: Colors.grey),
            title: const Text('Security limitations'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showSecurityLimitationsDialog(context),
          ),
        ]),
        const SizedBox(height: 24),

        // ── Danger zone ──────────────────────────────────────────────────────
        FilledButton.icon(
          onPressed: _resetting ? null : _resetHelix,
          icon: _resetting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.delete_forever_outlined, size: 18),
          label: Text(_resetting ? 'Resetting...' : 'Reset Helix'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helper widgets
// ---------------------------------------------------------------------------

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon(this.icon, {required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i < children.length - 1) {
        items.add(Divider(
          height: 1,
          indent: 68,
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ));
      }
    }
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      color: theme.colorScheme.surface,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(children: items),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SecurityLimitationItem extends StatelessWidget {
  const _SecurityLimitationItem(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.remove_circle_outline,
              size: 14,
              color: theme.colorScheme.onSurface.withAlpha(120)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
