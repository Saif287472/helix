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
    } catch (e) {
      setState(() => _error = '$e');
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Revoke failed: $e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Rename failed: $e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lost-device failed: $e')));
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
          title: Text('${device.deviceName} History'),
          content: SizedBox(
            width: double.maxFinite,
            child: history.isEmpty
                ? const Text('No security history found.')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final row in history)
                        ListTile(
                          dense: true,
                          title: Text(row['type'].toString()),
                          subtitle: Text(
                            DateTime.fromMillisecondsSinceEpoch(
                              row['timestamp'] as int,
                            ).toLocal().toString(),
                          ),
                        ),
                    ],
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('History failed: $e')));
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
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : Column(
              children: [
                _buildLinkDeviceUnavailableBanner(context),
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

  Widget _buildLinkDeviceUnavailableBanner(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: ListTile(
        leading: const Icon(Icons.link_off, color: Colors.grey),
        title: const Text('Link New Device'),
        subtitle: const Text(
          'Device linking requires server-side support not yet available. '
          'To add a new device, register a new account or contact support.',
        ),
        trailing: const Icon(Icons.block, color: Colors.grey),
        enabled: false,
      ),
    );
  }
}
