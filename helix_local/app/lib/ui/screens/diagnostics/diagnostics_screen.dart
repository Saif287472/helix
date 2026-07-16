// lib/ui/screens/diagnostics/diagnostics_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix/providers/app_providers.dart';

// ---------------------------------------------------------------------------
// Diagnostics screen (UI-010)
// ---------------------------------------------------------------------------

class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  NetworkDiagnostics? _data;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(diagnosticsServiceProvider).getDiagnostics();
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // When embedded inside HomeScreen's IndexedStack the Scaffold/AppBar is
    // provided by HomeScreen. When pushed via Navigator it needs its own.
    final isStandalone =
        ModalRoute.of(context) != null &&
        ModalRoute.of(context)!.isFirst == false;

    final content = _buildContent(theme);

    if (isStandalone) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Network Diagnostics'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
            ),
          ],
        ),
        body: content,
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              Text('Network Diagnostics', style: theme.textTheme.titleMedium),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: _loading ? null : _load,
              ),
            ],
          ),
        ),
        Expanded(child: content),
      ],
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 40,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                'Failed to load diagnostics.',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(_error!, style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_data == null) return const SizedBox.shrink();

    final d = _data!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Client isolation warning
        if (d.clientIsolationSuspected)
          _WarningBanner(
            icon: Icons.warning_amber_outlined,
            color: Colors.amber,
            title: 'Client isolation suspected',
            body:
                'Your router may be blocking peer-to-peer communication '
                'between devices on this network. Direct connections may '
                'fail. Try a different network or disable AP isolation.',
          ),

        // Firewall guidance
        if (d.firewallNote != null)
          _WarningBanner(
            icon: Icons.security_outlined,
            color: Colors.orange,
            title: 'Windows Firewall',
            body: d.firewallNote!,
          ),

        _SectionHeader(label: 'Network'),
        _DiagRow(
          icon: Icons.router_outlined,
          label: 'Interface type',
          value: d.interfaceType ?? 'Unknown',
        ),
        _DiagRow(
          icon: Icons.lan_outlined,
          label: 'Local IP address',
          value: d.localIp ?? 'Not available',
        ),
        _DiagRow(
          icon: Icons.wifi_outlined,
          label: 'Network name (SSID)',
          value: d.networkName ?? 'Not available',
        ),
        const Divider(),

        _SectionHeader(label: 'Discovery'),
        _DiagBoolRow(
          icon: Icons.search_outlined,
          label: 'mDNS / DNS-SD',
          value: d.mdnsAvailable,
          trueLabel: 'Available',
          falseLabel: 'Not available',
        ),
        _DiagBoolRow(
          icon: Icons.broadcast_on_home_outlined,
          label: 'UDP broadcast',
          value: d.udpBroadcastAvailable,
          trueLabel: 'Available',
          falseLabel: 'Not available',
        ),
        const Divider(),

        _SectionHeader(label: 'Listener'),
        _DiagBoolRow(
          icon: Icons.settings_ethernet_outlined,
          label: 'TCP listener',
          value: d.tcpListenerActive,
          trueLabel: 'Active on port ${d.tcpListenerPort}',
          falseLabel: 'Not active',
        ),
        const Divider(),

        _SectionHeader(label: 'Protocol'),
        _DiagRow(
          icon: Icons.info_outline,
          label: 'Protocol version',
          value: d.protocolVersion,
        ),
        const Divider(),

        // Footer note
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.withAlpha(30),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_outline, size: 14, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No diagnostic data is saved or exported. '
                  'This information is collected locally and displayed here only.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Subwidgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: theme.colorScheme.onSurface.withAlpha(160),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagBoolRow extends StatelessWidget {
  const _DiagBoolRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.trueLabel,
    required this.falseLabel,
  });

  final IconData icon;
  final String label;
  final bool value;
  final String trueLabel;
  final String falseLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = value ? Colors.green : Colors.red;
    final statusIcon = value
        ? Icons.check_circle_outline
        : Icons.cancel_outlined;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: theme.colorScheme.onSurface.withAlpha(160),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Icon(statusIcon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            value ? trueLabel : falseLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        border: Border.all(color: color.withAlpha(120)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(color: color),
                ),
                const SizedBox(height: 4),
                Text(body, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
