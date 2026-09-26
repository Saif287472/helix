import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote/l10n/helix_localizations.dart';

class DeviceManagementScreen extends StatefulWidget {
  const DeviceManagementScreen({
    super.key,
    required this.restClient,
    this.db,
    this.deviceChanges,
  });

  final HelixRemoteRestClient restClient;

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
      setState(() {
        _devices = devices;
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
        title: Text(HelixLocalizations.of(context).revokeDevice),
        content: Text('Revoke "${device.deviceName}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(HelixLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(HelixLocalizations.of(context).revoke),
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
          SnackBar(
            content: Text(
              HelixLocalizations.of(context).couldNotRevokeDeviceCheck,
            ),
          ),
        );
      }
    }
  }

  Future<void> _rename(RemoteDevice device) async {
    final controller = TextEditingController(text: device.deviceName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(HelixLocalizations.of(context).renameDevice),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Device name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(HelixLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(HelixLocalizations.of(context).save),
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
          SnackBar(
            content: Text(
              HelixLocalizations.of(context).couldNotRenameDeviceTry,
            ),
          ),
        );
      }
    }
  }

  Future<void> _markLost(RemoteDevice device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(HelixLocalizations.of(context).reportLostDevice),
        content: Text(
          'Report "${device.deviceName}" as lost? Its sessions and queued messages will be revoked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(HelixLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(HelixLocalizations.of(context).reportLost),
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
          SnackBar(
            content: Text(
              HelixLocalizations.of(context).couldNotReportDeviceLost,
            ),
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
                    title: Text(HelixLocalizations.of(context).firstSeen),
                    subtitle: Text(device.createdAt.toLocal().toString()),
                  );
                }
                if (index == 1) {
                  return ListTile(
                    dense: true,
                    title: Text(HelixLocalizations.of(context).keyFingerprint),
                    subtitle: Text(_fingerprint(device.deviceSigningPublicKey)),
                  );
                }
                if (index == 2) return const Divider();
                if (history.isEmpty) {
                  return ListTile(
                    dense: true,
                    title: Text(
                      HelixLocalizations.of(context).noSecurityHistoryFound,
                    ),
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
              child: Text(HelixLocalizations.of(context).close),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              HelixLocalizations.of(context).couldNotLoadSecurityHistory,
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
          SnackBar(
            content: Text(
              HelixLocalizations.of(context).couldNotProcessDeviceLink,
            ),
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
      color: const Color(0xFFFFFBEB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFFDE68A)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link, size: 18, color: Color(0xFFD97706)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    count == 1
                        ? '1 device is waiting to be linked'
                        : '$count devices are waiting to be linked',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              HelixLocalizations.of(
                context,
              ).pendingDeviceLinkConfirmElsewhere,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Color(0xFFB45309),
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
                      color: Color(0xFFB45309),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${link['device_name']} • asked for link '
                        '${_shortLinkId(link['link_id'] as String)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF92400E),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _dismissPendingLink(link),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF92400E),
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        HelixLocalizations.of(context).dismiss,
                        style: const TextStyle(fontSize: 12),
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
        title: Text(HelixLocalizations.of(context).devices),
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
                            return Card(
                              child: ListTile(
                                leading: const Icon(Icons.phone_android),
                                title: Text(device.deviceName),
                                subtitle: Text(
                                  'ID: ${device.deviceId} | ${device.status}',
                                ),
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
                                    PopupMenuItem(
                                      value: 'rename',
                                      child: Text(
                                        HelixLocalizations.of(context).rename,
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'history',
                                      child: Text(
                                        HelixLocalizations.of(
                                          context,
                                        ).securityHistory,
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'lost',
                                      child: Text(
                                        HelixLocalizations.of(
                                          context,
                                        ).reportLost,
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'revoke',
                                      child: Text(
                                        HelixLocalizations.of(context).revoke,
                                      ),
                                    ),
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
        title: Text(HelixLocalizations.of(context).linkNewDevice),
        subtitle: Text(
          HelixLocalizations.of(context).approveRejectPendingRequestFresh,
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
      title: Text(HelixLocalizations.of(context).linkNewDevice),
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
          child: Text(HelixLocalizations.of(context).cancel),
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
          child: Text(HelixLocalizations.of(context).reject),
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
          child: Text(HelixLocalizations.of(context).approve),
        ),
      ],
    );
  }
}
