import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';

class DeviceManagementScreen extends StatefulWidget {
  const DeviceManagementScreen({
    super.key,
    required this.restClient,
    this.db,
    this.deviceChanges,
    this.currentDeviceId,
  });

  final HelixRemoteRestClient restClient;

  /// This device, so the list can mark it and keep "sign out" off it.
  final String? currentDeviceId;

  /// Local database, used to read pending new-device pairing requests the
  /// server pushed to this device. Optional: without it the screen simply
  /// omits that section.
  final HelixRemoteDatabase? db;

  /// Optional stream of sync changes; reloads device list when devices area changes.
  final Stream<RemoteSyncChange>? deviceChanges;

  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  List<RemoteDevice> _devices = [];
  List<Map<String, dynamic>> _pendingLinks = [];
  bool _busy = false;
  String? _error;
  StreamSubscription<RemoteSyncChange>? _changeSub;

  @override
  void initState() {
    super.initState();
    _changeSub = widget.deviceChanges?.listen((change) {
      if (change.affects(RemoteSyncChangeArea.devices)) {
        _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _changeSub?.cancel();
    super.dispose();
  }

  int get _nowMs => DateTime.now().millisecondsSinceEpoch;

  void _loadPendingLinks() {
    final db = widget.db;
    if (db == null) {
      _pendingLinks = [];
      return;
    }
    try {
      db.purgeExpiredDeviceLinks(nowMs: _nowMs);
      _pendingLinks = db.getPendingDeviceLinks(nowMs: _nowMs);
    } catch (_) {
      // A local read failure must not take the device list down with it.
      _pendingLinks = [];
    }
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final devices = await widget.restClient.listDevices();
      if (!mounted) return;
      // The server also returns signed-out devices (for the admin console);
      // this screen is "where am I signed in", so only active ones show.
      final active = devices.where((d) => d.isActive).toList()
        ..sort((a, b) {
          if (a.deviceId == widget.currentDeviceId) return -1;
          if (b.deviceId == widget.currentDeviceId) return 1;
          final aSeen = a.lastSeenAt ?? a.createdAt;
          final bSeen = b.lastSeenAt ?? b.createdAt;
          return bSeen.compareTo(aSeen);
        });
      setState(() {
        _devices = active;
        _loadPendingLinks();
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Could not load devices. Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(RemoteDevice device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke Device'),
        content: Text('Revoke "${device.deviceName}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.restClient.revokeDevice(device.deviceId.toString());
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not revoke device. Check your connection and try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _signOutOthers() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out all other devices?'),
        content: const Text(
          'Every other device signed in to your account will be signed out. This device stays signed in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out others'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final count = await widget.restClient.revokeOtherDevices();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? 'Signed out 1 other device.'
                : 'Signed out $count other devices.',
          ),
        ),
      );
      if (mounted) await _load();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not sign out the other devices. Check your connection and try again.',
          ),
        ),
      );
    }
  }

  String _activity(RemoteDevice device) {
    if (device.deviceId == widget.currentDeviceId) return 'This device';
    final seen = device.lastSeenAt;
    if (seen == null) return 'Signed in ${_date(device.createdAt)}';
    final ago = DateTime.now().difference(seen);
    if (ago.inMinutes < 2) return 'Active now';
    if (ago.inHours < 1) return 'Active ${ago.inMinutes} min ago';
    if (ago.inDays < 1) return 'Active ${ago.inHours} h ago';
    if (ago.inDays < 7) return 'Active ${ago.inDays} d ago';
    return 'Last active ${_date(seen)}';
  }

  String _date(DateTime time) {
    final local = time.toLocal();
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '${local.year}-$m-$d';
  }

  Future<void> _rename(RemoteDevice device) async {
    final controller = TextEditingController(text: device.deviceName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Device name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == device.deviceName) return;
    try {
      await widget.restClient.renameDevice(
        deviceId: device.deviceId,
        deviceName: name,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not rename device. Try again.')),
        );
      }
    }
  }

  Future<void> _markLost(RemoteDevice device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report Lost Device'),
        content: Text(
          'Report "${device.deviceName}" as lost? Its sessions and queued messages will be revoked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Report Lost'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.restClient.reportLostDevice(device.deviceId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not report device as lost. Try again.'),
          ),
        );
      }
    }
  }

  Future<void> _showHistory(RemoteDevice device) async {
    try {
      final history = await widget.restClient.getDeviceSecurityHistory(
        device.deviceId,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${device.deviceName} Security'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: history.isEmpty ? 4 : history.length + 3,
              itemBuilder: (_, index) {
                if (index == 0) {
                  return ListTile(
                    dense: true,
                    title: const Text('First seen'),
                    subtitle: Text(device.createdAt.toLocal().toString()),
                  );
                }
                if (index == 1) {
                  return ListTile(
                    dense: true,
                    title: const Text('Key fingerprint'),
                    subtitle: Text(_fingerprint(device.deviceSigningPublicKey)),
                  );
                }
                if (index == 2) return const Divider();
                if (history.isEmpty) {
                  return const ListTile(
                    dense: true,
                    title: Text('No security history found.'),
                  );
                }
                final row = history[index - 3];
                return ListTile(
                  dense: true,
                  title: Text(row['type'].toString()),
                  subtitle: Text(
                    DateTime.fromMillisecondsSinceEpoch(
                      row['timestamp'] as int,
                    ).toLocal().toString(),
                  ),
                );
              },
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not load security history. Check your connection and try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _approveOrRejectLinkRequest() async {
    final decision = await showDialog<_LinkDecision>(
      context: context,
      builder: (_) => const _DeviceLinkDecisionDialog(),
    );
    if (decision == null ||
        decision.linkId.isEmpty ||
        decision.verificationCode.length != 6) {
      return;
    }

    try {
      if (decision.approve) {
        await widget.restClient.approveDeviceLink(
          linkId: decision.linkId,
          verificationCode: decision.verificationCode,
        );
      } else {
        await widget.restClient.rejectDeviceLink(
          linkId: decision.linkId,
          verificationCode: decision.verificationCode,
        );
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              decision.approve
                  ? 'Device link approved.'
                  : 'Device link rejected.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not process device link. Try again.'),
          ),
        );
      }
    }
  }

  /// New devices that have asked to pair with this account.
  ///
  /// The server pushes these to the account's existing devices. Before the
  /// inbound event was handled they were simply dropped, which left the
  /// "link a device" form as the only route in - and that form requires
  /// hand-typing the Link ID and the 6-digit code shown on the other screen.
  ///
  /// The code is deliberately absent here: it only ever exists on the
  /// requesting device, so this list is a prompt to go and confirm there,
  /// not a way to approve remotely.
  Widget _buildPendingLinks(BuildContext context) {
    final count = _pendingLinks.length;
    return Card(
      color: HelixStatusColors.pendingSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: HelixStatusColors.pendingOutline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.link,
                  size: 18,
                  color: HelixStatusColors.pendingIcon,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    count == 1
                        ? '1 device is waiting to be linked'
                        : '$count devices are waiting to be linked',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: HelixStatusColors.onPendingSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Open Helix on that device and confirm the code it shows. The code is never sent to this device.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: HelixStatusColors.pendingAccent,
              ),
            ),
            const SizedBox(height: 10),
            for (final link in _pendingLinks)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.phone_android,
                      size: 16,
                      color: HelixStatusColors.pendingAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${link['device_name']} • asked for link '
                        '${_shortLinkId(link['link_id'] as String)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: HelixStatusColors.onPendingSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _dismissPendingLink(link),
                      style: TextButton.styleFrom(
                        foregroundColor: HelixStatusColors.onPendingSurface,
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Dismiss',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _shortLinkId(String linkId) =>
      linkId.length <= 8 ? linkId : linkId.substring(0, 8);

  void _dismissPendingLink(Map<String, dynamic> link) {
    final db = widget.db;
    final linkId = link['link_id'] as String?;
    if (db == null || linkId == null) return;
    try {
      db.markPendingDeviceLinkResolved(linkId, status: 'DISMISSED');
      setState(_loadPendingLinks);
    } catch (_) {
      // Nothing actionable: the row stays and the next reload retries.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh devices',
          ),
        ],
      ),
      body: _busy
          ? const Center(child: HelixSkeleton(width: 192, height: 24))
          : _error != null
          ? HelixErrorState(message: _error!, onRetry: _load)
          : Column(
              children: [
                if (_pendingLinks.isNotEmpty) ...[
                  _buildPendingLinks(context),
                  const SizedBox(height: 8),
                ],
                _buildLinkDeviceAction(context),
                if (widget.currentDeviceId != null &&
                    _devices.any((d) => d.deviceId != widget.currentDeviceId))
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    child: ListTile(
                      leading: Icon(
                        Icons.logout,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: const Text('Sign out all other devices'),
                      subtitle: const Text('Keeps only this device signed in'),
                      onTap: _signOutOthers,
                    ),
                  ),
                Expanded(
                  child: _devices.isEmpty
                      ? const HelixEmptyState(
                          icon: Icons.devices_other_outlined,
                          title: 'No devices found',
                          message:
                              'Link another device to manage its access here.',
                        )
                      : ListView.builder(
                          itemCount: _devices.length,
                          itemBuilder: (_, i) {
                            final device = _devices[i];
                            final isThisDevice =
                                device.deviceId == widget.currentDeviceId;
                            return Card(
                              child: ListTile(
                                leading: Icon(
                                  isThisDevice
                                      ? Icons.smartphone
                                      : Icons.phone_android,
                                ),
                                title: Text(device.deviceName),
                                subtitle: Text(_activity(device)),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'rename') {
                                      _rename(device);
                                    } else if (value == 'history') {
                                      _showHistory(device);
                                    } else if (value == 'lost') {
                                      _markLost(device);
                                    } else if (value == 'revoke') {
                                      _revoke(device);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'rename',
                                      child: Text('Rename'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'history',
                                      child: Text('Security History'),
                                    ),
                                    if (!isThisDevice) ...[
                                      const PopupMenuItem(
                                        value: 'lost',
                                        child: Text('Report Lost'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'revoke',
                                        child: Text('Revoke'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildLinkDeviceAction(BuildContext context) {
    return Card(
      margin: HelixInsets.all(12),
      child: ListTile(
        leading: const Icon(Icons.qr_code_scanner),
        title: const Text('Link New Device'),
        subtitle: const Text(
          'Approve or reject a pending request from a fresh device.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _approveOrRejectLinkRequest,
      ),
    );
  }

  String _fingerprint(String publicKey) {
    final normalized = publicKey.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final prefix = normalized.length <= 16
        ? normalized
        : normalized.substring(0, 16);
    return prefix
        .replaceAllMapped(RegExp(r'.{4}'), (match) => '${match.group(0)} ')
        .trim();
  }
}

class _LinkDecision {
  const _LinkDecision({
    required this.approve,
    required this.linkId,
    required this.verificationCode,
  });

  final bool approve;
  final String linkId;
  final String verificationCode;
}

class _DeviceLinkDecisionDialog extends StatefulWidget {
  const _DeviceLinkDecisionDialog();

  @override
  State<_DeviceLinkDecisionDialog> createState() =>
      _DeviceLinkDecisionDialogState();
}

class _DeviceLinkDecisionDialogState extends State<_DeviceLinkDecisionDialog> {
  final _linkController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _linkController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Link New Device'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _linkController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Link ID'),
          ),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'Verification code',
              counterText: '',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            _LinkDecision(
              approve: false,
              linkId: _linkController.text.trim(),
              verificationCode: _codeController.text.trim(),
            ),
          ),
          child: const Text('Reject'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _LinkDecision(
              approve: true,
              linkId: _linkController.text.trim(),
              verificationCode: _codeController.text.trim(),
            ),
          ),
          child: const Text('Approve'),
        ),
      ],
    );
  }
}
