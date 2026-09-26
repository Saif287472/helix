import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../admin_client.dart';
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
    this.client,
    this.serverHost,
    this.isLoading = false,
    this.onTriggerBackup,
    this.onSignOut,
    this.appLockEnabled = false,
    this.onAppLockChanged,
  });

  final Map<String, dynamic>? config;
  final TextEditingController federationDomainController;
  final TextEditingController federationAddressController;
  final TextEditingController federationDirectoryController;
  final ValueChanged<bool> onSetWorldwideMode;
  final Future<String> Function(String name) onSaveServerName;

  /// Used for the server-owned feature flags. Optional: without it the
  /// feature-flag card is not rendered.
  final AdminClient? client;
  final String? serverHost;
  final bool isLoading;
  final Future<void> Function()? onTriggerBackup;
  final VoidCallback? onSignOut;

  /// Defaults to false so an unbound instance renders the real, unforced
  /// state. It used to default to true, which made the switch display "on"
  /// for an operator who had never enabled it.
  final bool appLockEnabled;
  final ValueChanged<bool>? onAppLockChanged;

  @override
  State<ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<ConfigTab> {
  late bool _appLockEnabled;
  /// Server-owned flags this console is allowed to toggle.
  ///
  /// `federation_directory_v2` is deliberately absent: federation is deferred
  /// for this product, and the flag gates nothing today, so surfacing a switch
  /// for it would be inventing a control.
  static const _toggleableFlags = <String, String>{
    'crash_reporting_upload': 'Client crash reports',
    'minimal_analytics': 'Minimal analytics',
  };

  Map<String, bool> _featureFlags = const {};
  String? _flagsError;
  bool _loadingFlags = false;
  final Set<String> _pendingFlags = <String>{};

  /// Which long-running action is in flight, so its button can show a spinner
  /// and cannot be double-tapped. `null` when idle.
  String? _busyAction;

  /// Server-reported maintenance state, seeded from `config` and only moved
  /// after the server confirms a change.
  late bool _maintenanceEnabled;

  void _seedMaintenance() {
    _maintenanceEnabled = widget.config?['maintenance_mode'] == true;
  }

  Future<void> _setMaintenance(bool enabled) async {
    final client = widget.client;
    if (client == null) return;
    final previous = _maintenanceEnabled;
    setState(() {
      _busyAction = 'maintenance';
      // Optimistic so the switch responds immediately; rolled back below if the
      // server refuses.
      _maintenanceEnabled = enabled;
    });
    try {
      await client.setMaintenanceMode(enabled);
      if (!mounted) return;
      setState(() => _busyAction = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Maintenance mode is ON. Clients get 503 until you turn it '
                      'off.'
                : 'Maintenance mode is off. Clients are being served again.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _maintenanceEnabled = previous;
        _busyAction = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not change maintenance mode: $e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  Future<void> _changePin() async {
    final client = widget.client;
    if (client == null) return;

    // The dialog owns its own controllers and returns the entered values.
    // Handing it controllers from here and disposing them the moment
    // showDialog returns is a use-after-dispose: the dialog is still animating
    // out and its TextFields still reference them.
    final entered = await showDialog<({String current, String next})>(
      context: context,
      builder: (ctx) => const _PasswordChangeDialog(),
    );
    if (entered == null || !mounted) return;
    final currentPassword = entered.current;
    final newPassword = entered.next;

    setState(() => _busyAction = 'pin');
    try {
      await client.changeAdminPin(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      if (!mounted) return;
      setState(() => _busyAction = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Admin password changed. Existing sessions stay signed in; use '
            'the new password next time you connect.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyAction = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not change the password: $e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  Future<void> _purgeData() async {
    final client = widget.client;
    if (client == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Purge expired data?'),
        content: const Text(
          'Deletes expired attachment references, dead-letter and failed '
          'outbox rows older than a week, and refresh tokens older than a '
          'month.\n\nAccounts, devices, messages, contacts and the audit trail '
          'are not touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Purge'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyAction = 'purge');
    try {
      final removed = await client.purgeData();
      if (!mounted) return;
      setState(() => _busyAction = null);
      final total = removed.values.fold<int>(0, (a, b) => a + b);
      final detail = removed.entries
          .where((e) => e.value > 0)
          .map((e) => '${e.value} ${e.key}')
          .join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            total == 0
                ? 'Nothing to purge - no expired rows were past the retention '
                      'window.'
                : 'Purged $total row${total == 1 ? '' : 's'} ($detail).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyAction = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not purge data: $e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  Future<void> _copySupportBundle() async {
    final client = widget.client;
    if (client == null) return;
    setState(() => _busyAction = 'support');
    try {
      final bundle = await client.getSupportDiagnostic();
      if (!mounted) return;
      setState(() => _busyAction = null);
      final text = const JsonEncoder.withIndent(
        '  ',
      ).convert(bundle);
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Support bundle copied. Tokens and secrets are excluded.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyAction = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not build the support bundle: $e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _appLockEnabled = widget.appLockEnabled;
    _seedMaintenance();
    _loadFeatureFlags();
  }

  @override
  void didUpdateWidget(ConfigTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The shell owns the preference, so a change made elsewhere (a reload, or
    // a sign-out that resets it) has to be reflected rather than leaving the
    // switch showing a stale local value.
    if (widget.appLockEnabled != oldWidget.appLockEnabled) {
      setState(() => _appLockEnabled = widget.appLockEnabled);
    }
    // Maintenance mode is server state, so a config refresh is the authority.
    if (!_busyActionEqualsMaintenance() &&
        widget.config?['maintenance_mode'] !=
            oldWidget.config?['maintenance_mode']) {
      _seedMaintenance();
    }
  }

  /// True while a maintenance request is in flight, during which the server's
  /// own value must not overwrite the optimistic local one.
  bool _busyActionEqualsMaintenance() => _busyAction == 'maintenance';

  Future<void> _loadFeatureFlags() async {
    final client = widget.client;
    if (client == null) return;
    setState(() {
      _loadingFlags = true;
      _flagsError = null;
    });
    try {
      final flags = await client.getFeatureFlags();
      if (!mounted) return;
      setState(() {
        _featureFlags = {
          for (final entry in flags.entries)
            if (_toggleableFlags.containsKey(entry.key)) entry.key: entry.value,
        };
        _loadingFlags = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingFlags = false;
        _flagsError = e.toString();
      });
    }
  }

  Future<void> _setFlag(String name, bool enabled) async {
    final client = widget.client;
    if (client == null) return;
    setState(() {
      _pendingFlags.add(name);
      _flagsError = null;
    });
    try {
      await client.setFeatureFlag(name, enabled);
      if (!mounted) return;
      // Only reflect the new value once the server confirmed it, so the
      // switch never shows a state the server did not accept.
      setState(() {
        _featureFlags = {..._featureFlags, name: enabled};
        _pendingFlags.remove(name);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pendingFlags.remove(name);
        _flagsError = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update "$name": $e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
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
                // The server sends the literal string 'unknown' for an unset
                // server_id / server_public_key. Surface that as "not
                // available" instead of substituting an invented value.
                final rawServerId = config['server_id']?.toString();
                final serverId = (rawServerId == null || rawServerId.isEmpty ||
                        rawServerId == 'unknown')
                    ? null
                    : rawServerId;
                final rawPublicKey = config['server_public_key']?.toString();
                final serverPublicKey =
                    (rawPublicKey == null || rawPublicKey.isEmpty ||
                            rawPublicKey == 'unknown')
                        ? null
                        : rawPublicKey;
                final publicBaseUrl =
                    (config['public_base_url']?.toString().isNotEmpty ?? false)
                        ? config['public_base_url'].toString()
                        : (widget.serverHost ??
                              'Not available - the server reported no public '
                                  'base URL');
                final items = [
                  _propItem(
                    label: 'PUBLIC SERVER ADDRESS',
                    val: publicBaseUrl,
                  ),
                  _propItem(
                    label: 'DEFAULT FALLBACK NAME',
                    val: config['default_server_name']?.toString() ??
                        'Not available',
                  ),
                  _propItem(
                    label: 'HOST & PORT',
                    val: '${config['host'] ?? 'not reported'}:'
                        '${config['port'] ?? 'not reported'}',
                  ),
                  _propItem(
                    label: 'SERVER ID',
                    val: serverId ?? 'Not available',
                    copyable: true,
                    available: serverId != null,
                  ),
                  _propItem(
                    label: 'SERVER PUBLIC KEY',
                    val: serverPublicKey ?? 'Not available',
                    copyable: true,
                    available: serverPublicKey != null,
                  ),
                  _propItem(
                    label: 'DATABASE PATH',
                    val: config['db_path']?.toString() ?? 'Not available',
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
                      activeThumbColor: const Color(0xFF2563EB),
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
                      activeThumbColor: const Color(0xFF2563EB),
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
                      onPressed:
                          _busyAction == 'pin' ? null : () => _changePin(),
                      child: _busyAction == 'pin'
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Change Password'),
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
                      value: _maintenanceEnabled,
                      activeThumbColor: const Color(0xFFD97706),
                      onChanged: _busyAction == 'maintenance'
                          ? null
                          : (val) => _setMaintenance(val),
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
                      onPressed:
                          _busyAction == 'purge' ? null : () => _purgeData(),
                      child: _busyAction == 'purge'
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Purge Data'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFFE2E8F0)),
                const SizedBox(height: 14),
                _buildSupportBundleRow(context),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 6b. SERVER-OWNED FEATURE FLAGS
          if (widget.client != null) ...[
            _buildFeatureFlagsCard(context),
            const SizedBox(height: 16),
          ],

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

  /// Server-owned feature flags.
  ///
  /// These are real switches: the server reads the stored value on the code
  /// path each flag gates. The values come from
  /// `GET /ops/feature-flags`, never from a local guess, and a switch only
  /// moves after the server confirms the write.
  Widget _buildFeatureFlagsCard(BuildContext context) {
    final descriptions = <String, String>{
      'crash_reporting_upload':
          'Accept crash reports from client devices. Reports are redacted by '
              'the client and written only to this server\'s own log.',
      'minimal_analytics':
          'Accept minimal, redacted usage analytics from client devices.',
    };

    return _buildCard(
      title: 'FEATURE FLAGS',
      subtitle: 'Server-owned switches. Changes take effect immediately.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loadingFlags)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_flagsError != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 18,
                    color: Color(0xFFDC2626),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Could not load feature flags: $_flagsError',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF991B1B),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadFeatureFlags,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else
            for (final entry in _toggleableFlags.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.value,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            descriptions[entry.key] ?? '',
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (_pendingFlags.contains(entry.key))
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      Switch(
                        value: _featureFlags[entry.key] ?? false,
                        activeThumbColor: const Color(0xFF2563EB),
                        onChanged: (val) => _setFlag(entry.key, val),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  /// The support-bundle action, placed with the maintenance controls.
  Widget _buildSupportBundleRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Copy Support Bundle',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Puts readiness, outbox, WebSocket and rate-limiter state on '
                'the clipboard for a bug report. Tokens, the TURN secret and '
                'raw SDP are excluded by the server.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          key: const Key('config_copy_support_bundle'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF334155),
            side: const BorderSide(color: Color(0xFFCBD5E1)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: _busyAction == 'support' ? null : _copySupportBundle,
          child: _busyAction == 'support'
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Copy Bundle'),
        ),
      ],
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
    bool available = true,
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
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: available
                        ? const Color(0xFF0F172A)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ),
              if (copyable)
                IconButton(
                  icon: const Icon(Icons.copy, size: 16, color: Color(0xFF64748B)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: available ? 'Copy' : 'Nothing to copy',
                  // Never put a placeholder on the clipboard: an operator who
                  // copies a fake server id or public key pastes it into a
                  // federation registration or a support ticket.
                  onPressed: available
                      ? () {
                          Clipboard.setData(ClipboardData(text: val));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$label copied to clipboard')),
                          );
                        }
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Collects the current and new master admin password.
///
/// Owns its controllers and disposes them with its own state, so they cannot
/// outlive (or be outlived by) the dialog. Returns the entered pair, or null if
/// cancelled.
///
/// Validates locally - length and the confirmation match - before popping, so
/// an obviously-wrong submission never costs a round trip. The server
/// re-checks the current password regardless, because a client-side check is a
/// convenience, not a control.
class _PasswordChangeDialog extends StatefulWidget {
  const _PasswordChangeDialog();

  @override
  State<_PasswordChangeDialog> createState() => _PasswordChangeDialogState();
}

class _PasswordChangeDialogState extends State<_PasswordChangeDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final current = _current.text;
    final next = _next.text;
    final confirm = _confirm.text;

    if (current.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }
    if (next.trim().length < 6) {
      setState(
        () => _error = 'The new password must be at least 6 characters.',
      );
      return;
    }
    if (next != confirm) {
      setState(() => _error = 'The two new passwords do not match.');
      return;
    }
    Navigator.pop(context, (current: current, next: next));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change admin password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This is the master password for this server. Anyone holding it '
            'can read every account on the node.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('admin_pin_current'),
            controller: _current,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Current password'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('admin_pin_new'),
            controller: _next,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'New password',
              helperText: 'At least 6 characters',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('admin_pin_confirm'),
            controller: _confirm,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('admin_pin_submit'),
          onPressed: _submit,
          child: const Text('Change Password'),
        ),
      ],
    );
  }
}
