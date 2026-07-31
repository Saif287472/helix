import 'package:flutter/material.dart';

class ConfigTab extends StatelessWidget {
  const ConfigTab({
    super.key,
    required this.config,
    required this.federationDomainController,
    required this.federationAddressController,
    required this.federationDirectoryController,
    required this.onSetWorldwideMode,
  });

  final Map<String, dynamic>? config;
  final TextEditingController federationDomainController;
  final TextEditingController federationAddressController;
  final TextEditingController federationDirectoryController;
  final ValueChanged<bool> onSetWorldwideMode;

  @override
  Widget build(BuildContext context) {
    final config = this.config;
    if (config == null) {
      return const Center(child: Text('No configuration available.'));
    }
    return SingleChildScrollView(
      child: Card(
        color: const Color(0xFF161624),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Server Configuration Properties',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              _configField('Server ID', config['server_id'] ?? 'unknown'),
              _configField(
                'Server Public Key',
                config['server_public_key'] ?? 'unknown',
              ),
              _configField('Server Running Port', config['port'] ?? 'unknown'),
              _configField('Host Address Bound', config['host'] ?? 'unknown'),
              _configField('Database Path', config['db_path'] ?? 'unknown'),
              _configField(
                'Attachments Path',
                config['attachments_dir'] ?? 'unknown',
              ),
              _configField(
                'Push Notifications Configured',
                config['push_configured'] == true ? 'ENABLED' : 'DISABLED',
              ),
              _configField(
                'TURN Server Configured',
                config['turn_configured'] == true ? 'ENABLED' : 'DISABLED',
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              _buildFederationControls(config),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFederationControls(Map<String, dynamic> config) {
    final federation = (config['federation'] as Map<String, dynamic>?) ?? const {};
    final enabled = federation['worldwide_mode'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Worldwide Mode',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Switch(value: enabled, onChanged: onSetWorldwideMode),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: federationDomainController,
          decoration: const InputDecoration(labelText: 'Federation domain'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: federationAddressController,
          decoration: const InputDecoration(labelText: 'Public server address'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: federationDirectoryController,
          decoration: const InputDecoration(labelText: 'Directory server URL'),
        ),
      ],
    );
  }

  Widget _configField(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          SelectableText(
            val,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              fontFamily: 'monospace',
              color: Color(0xFF00E5FF),
            ),
          ),
        ],
      ),
    );
  }
}
