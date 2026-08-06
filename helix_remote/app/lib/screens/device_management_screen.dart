import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';

class DeviceManagementScreen extends StatefulWidget {
  const DeviceManagementScreen({
    super.key,
    required this.restClient,
    this.deviceChanges,
  });

  final HelixRemoteRestClient restClient;

  /// Optional stream of sync changes; reloads device list when devices area changes.
  final Stream<RemoteSyncChange>? deviceChanges;

  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  List<RemoteDevice> _devices = [];
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

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final devices = await widget.restClient.listDevices();
      setState(() => _devices = devices);
    } catch (_) {
      setState(
        () => _error =
            'Could not load devices. Check your connection and try again.',
      );
    } finally {
      setState(() => _busy = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _busy
          ? const Center(child: HelixSkeleton(width: 192, height: 24))
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : Column(
              children: [
                _buildLinkDeviceAction(context),
                Expanded(
                  child: _devices.isEmpty
                      ? const Center(child: Text('No devices found'))
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
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'rename',
                                      child: Text('Rename'),
                                    ),
                                    PopupMenuItem(
                                      value: 'history',
                                      child: Text('Security History'),
                                    ),
                                    PopupMenuItem(
                                      value: 'lost',
                                      child: Text('Report Lost'),
                                    ),
                                    PopupMenuItem(
                                      value: 'revoke',
                                      child: Text('Revoke'),
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
