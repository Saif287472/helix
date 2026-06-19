import 'package:flutter/material.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_domain/models.dart';

class DeviceManagementScreen extends StatefulWidget {
  const DeviceManagementScreen({super.key, required this.restClient});

  final HelixRemoteRestClient restClient;

  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  List<RemoteDevice> _devices = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
          : _devices.isEmpty
          ? const Center(child: Text('No devices found'))
          : ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (_, i) {
                final device = _devices[i];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.phone_android),
                    title: Text(device.deviceName),
                    subtitle: Text('ID: ${device.deviceId} | ${device.status}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _revoke(device),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
