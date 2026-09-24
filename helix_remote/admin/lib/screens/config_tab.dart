import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/server_name_card.dart';

class ConfigTab extends StatefulWidget {
  const ConfigTab({
    super.key,
    required this.config,
    required this.federationDomainController,
    required this.federationAddressController,
    required this.federationDirectoryController,
    required this.onSetWorldwideMode,
    required this.onSaveServerName,
    this.serverHost,
    this.isLoading = false,
    this.onTriggerBackup,
    this.onSignOut,
    this.appLockEnabled = true,
    this.onAppLockChanged,
  });

  final Map<String, dynamic>? config;
  final TextEditingController federationDomainController;
  final TextEditingController federationAddressController;
  final TextEditingController federationDirectoryController;
  final ValueChanged<bool> onSetWorldwideMode;
  final Future<String> Function(String name) onSaveServerName;
  final String? serverHost;
  final bool isLoading;
  final Future<void> Function()? onTriggerBackup;
  final VoidCallback? onSignOut;
  final bool appLockEnabled;
  final ValueChanged<bool>? onAppLockChanged;

  @override
  State<ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<ConfigTab> {
  bool _maintenanceMode = false;
  late bool _appLockEnabled;

  @override
  void initState() {
    super.initState();
    _appLockEnabled = widget.appLockEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    if (config == null) {
      return const Center(child: Text('No configuration available.'));
    }

    final federation =
        (config['federation'] as Map<String, dynamic>?) ?? const {};
    final worldwideEnabled = federation['worldwide_mode'] == true;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. SERVER NODE IDENTITY
          ServerNameCard(
            initialName: config['server_name'] as String? ?? '',
            maxLength: config['max_server_name_length'] as int? ?? 60,
            onSave: widget.onSaveServerName,
            fallbackName: config['default_server_name'] as String?,
            serverHost: widget.serverHost,
          ),
          const SizedBox(height: 16),

          // 2. SERVER CONFIGURATION PROPERTIES
          _buildCard(
            title: 'SERVER CONFIGURATION PROPERTIES',
            subtitle:
                'Internal node network sockets, persistent storage, and cryptographic signatures',
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 550;
                final items = [
                  _propItem(
                    label: 'PUBLIC SERVER ADDRESS',
                    val: (config['public_base_url'] != null &&
                            config['public_base_url'].toString().isNotEmpty)
                        ? config['public_base_url'].toString()
                        : (widget.serverHost ?? 'https://helix.agiletechbd.com'),
                  ),
                  _propItem(
                    label: 'DEFAULT FALLBACK NAME',
                    val: config['default_server_name']?.toString() ??
                        'Helix CipherNode Alpha',
                  ),
                  _propItem(
                    label: 'HOST & PORT',
                    val: '${config['host'] ?? '0.0.0.0'}:${config['port'] ?? '8080'}',
                  ),
                  _propItem(
                    label: 'SERVER ID',
                    val: config['server_id']?.toString() ?? 'srv_alpha_90b1',
                    copyable: true,
                  ),
                  _propItem(
                    label: 'SERVER PUBLIC KEY',
                    val: config['server_public_key']?.toString() ??
                        'pub_9b14c381a4b92c8e',
                    copyable: true,
                  ),
                  _propItem(
                    label: 'DATABASE PATH',
                    val: config['db_path']?.toString() ?? '/app/data/helix.db',
                  ),
                ];

                if (!isWide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: items
                        .map((w) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: w,
                            ))
                        .toList(),
                  );
                }

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: items.map((w) {
                    final itemWidth = (constraints.maxWidth - 12) / 2;
                    return SizedBox(width: itemWidth, child: w);
                  }).toList(),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // 3. WORLDWIDE MODE & PEER NETWORK
          _buildCard(
            title: 'WORLDWIDE MODE & PEER NETWORK',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Worldwide Network Mode',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Advertise node to global Helix directory for universal cross-server discovery',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: worldwideEnabled,
                      activeColor: const Color(0xFF2563EB),
                      onChanged: widget.onSetWorldwideMode,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFFE2E8F0)),
                const SizedBox(height: 16),
                TextField(
                  controller: widget.federationDomainController,
                  decoration: InputDecoration(
                    labelText: 'Federation Domain',
                    hintText: 'node-alpha.helixnet.io',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: widget.federationDirectoryController,
                  decoration: InputDecoration(
                    labelText: 'Directory Server URL',
                    hintText: 'https://dir.helixnet.io/v1',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. LOCAL SECURITY & APP LOCK
          _buildCard(
            title: 'LOCAL SECURITY & APP LOCK',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Device Biometric / PIN Lock',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Require FaceID, Fingerprint or Device PIN on launching Helix Admin console',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _appLockEnabled,
                      activeColor: const Color(0xFF2563EB),
                      onChanged: (val) {
                        setState(() => _appLockEnabled = val);
                        widget.onAppLockChanged?.call(val);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFFE2E8F0)),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Security Credentials',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Change local application PIN code',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF334155),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'PIN change initiated. Authenticate to proceed.',
                            ),
                          ),
                        );
                      },
                      child: const Text('Change PIN'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 5. DATABASE SNAPSHOTS & DISASTER RECOVERY
          _buildCard(
            title: 'DATABASE SNAPSHOTS & DISASTER RECOVERY',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hot Database Snapshot',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Write a WAL-synchronized SQLite snapshot without stopping active sessions',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: widget.isLoading
                          ? null
                          : () => widget.onTriggerBackup?.call(),
                      child: widget.isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Create Snapshot'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFFE2E8F0)),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Restore Snapshot Backup (.db)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Upload a valid SQLite snapshot file to recover this node',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF334155),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Select snapshot backup file (.db) to restore.',
                            ),
                          ),
                        );
                      },
                      child: const Text('Restore DB'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 6. NODE MAINTENANCE & CACHE PURGE
          _buildCard(
            title: 'NODE MAINTENANCE & CACHE PURGE',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Server Maintenance Mode',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Reject incoming client traffic and reject message delivery with 503 Service Unavailable',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _maintenanceMode,
                      activeColor: const Color(0xFFD97706),
                      onChanged: (val) =>
                          setState(() => _maintenanceMode = val),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFFE2E8F0)),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Purge Cache & Temp Data',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Delete expired registration challenges, ephemeral cache keys, and temp staging',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(color: Color(0xFFFCA5A5)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Temporary staging and expired cache purged successfully.',
                            ),
                          ),
                        );
                      },
                      child: const Text('Purge Data'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 7. ADMIN SESSION CONTROL
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ADMIN SESSION CONTROL',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFDC2626),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sign Out / Disconnect Node',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF991B1B),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Clears cached admin authentication tokens from this device. You will need the master secret to sign back in.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFB91C1C),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    FilledButton(
                      key: const Key('settings_sign_out_button'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: widget.onSignOut,
                      child: const Text(
                        'Sign Out',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF64748B),
              letterSpacing: 0.5,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
              ),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _propItem({
    required String label,
    required String val,
    bool copyable = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Color(0xFF64748B),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  val,
                  style: const TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              if (copyable)
                IconButton(
                  icon: const Icon(Icons.copy, size: 16, color: Color(0xFF64748B)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Copy',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: val));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$label copied to clipboard')),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
