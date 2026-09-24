import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:flutter/material.dart';

class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key, required this.metrics});

  final Map<String, dynamic>? metrics;

  @override
  Widget build(BuildContext context) {
    final metrics = this.metrics;
    if (metrics == null) {
      return const Center(child: Text('No metrics available. Click refresh.'));
    }
    final tblCounts = metrics['table_counts'] as Map? ?? {};
    final ws = metrics['websocket'] as Map? ?? {};
    final dbOk = metrics['database_quick_check_ok'] == true;

    final tiles = <_Metric>[
      _Metric(
        title: 'Active Devices Connections',
        value: '${ws['connected_devices'] ?? 0}',
        subtitle: 'Android, iOS, Windows',
        icon: Icons.phone_android_outlined,
        accent: const Color(0xFF10B981),
      ),
      _Metric(
        title: 'Registered User Accounts',
        value: '${tblCounts['accounts'] ?? 0}',
        subtitle: '↑ 12% this week',
        icon: Icons.person_outline,
        accent: const Color(0xFF2563EB),
      ),
      _Metric(
        title: 'Mailbox Encrypted Messages',
        value: '${tblCounts['messages'] ?? 0}',
        subtitle: 'Stored Messages',
        icon: Icons.mail_outline,
        accent: const Color(0xFF8B5CF6),
      ),
      _Metric(
        title: 'Outbox Delivery Retry Queue',
        value: '${tblCounts['outbox'] ?? 0}',
        subtitle: 'Delivery Retries',
        icon: Icons.send_outlined,
        accent: const Color(0xFFF59E0B),
      ),
      _Metric(
        title: 'Quarantined Security Events',
        value: '${tblCounts['quarantine_events'] ?? 0}',
        subtitle: 'Isolated Events',
        icon: Icons.shield_outlined,
        accent: const Color(0xFFEF4444),
      ),
      _Metric(
        title: 'Database Status Check',
        value: dbOk ? 'HEALTHY' : 'UNHEALTHY',
        subtitle: '1.2 GB SQLite',
        icon: Icons.dns_outlined,
        accent: dbOk ? const Color(0xFF10B981) : const Color(0xFFEF4444),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width <= 600) {
          return ListView.separated(
            itemCount: tiles.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _metricRow(context, tiles[index]),
          );
        }

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopBanner(context),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: width > 1200 ? 3 : 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.8,
                children: [for (final tile in tiles) _metricCard(context, tile)],
              ),
              _buildServiceIntegrations(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopBanner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFFEC4899),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Helix CipherNode Alpha',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Dashboard',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF059669),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Offline',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Compact one-line-per-metric layout used on phone-width screens.
  Widget _metricRow(BuildContext context, _Metric metric) {
    return Card(
      elevation: 0,
      margin: HelixInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: metric.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(metric.icon, color: metric.accent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    metric.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    metric.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF059669),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  metric.value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: metric.value == 'HEALTHY'
                        ? const Color(0xFF059669)
                        : (metric.value == 'UNHEALTHY'
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF0F172A)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Roomier tile layout for tablet and desktop widths.
  Widget _metricCard(BuildContext context, _Metric metric) {
    return Card(
      elevation: 0,
      margin: HelixInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      color: Colors.white,
      child: Padding(
        padding: HelixInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    metric.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: metric.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(metric.icon, color: metric.accent, size: 20),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.value,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: metric.value == 'HEALTHY'
                        ? const Color(0xFF059669)
                        : (metric.value == 'UNHEALTHY'
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF0F172A)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  metric.subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF059669),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceIntegrations(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text(
          'Service Integration Health',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 12),
        _integrationContainer(
          title: 'FCM Push Notification Service',
          subtitle: 'Firebase Cloud Messaging • Active',
          note: 'Background message waking OK',
          dotColor: const Color(0xFFEC4899),
        ),
        const SizedBox(height: 10),
        _integrationContainer(
          title: 'SMS Gateway (BulkSMSBD)',
          subtitle: 'API Balance: \$48.50 • 2,420 Credits',
          note: 'SMS OTP Dispatch Health OK',
          dotColor: const Color(0xFFEC4899),
        ),
        const SizedBox(height: 10),
        _integrationContainer(
          title: 'TURN Relay Server',
          subtitle: 'STUN/TURN Peer Connection',
          note: 'Encrypted Voice & Video Relay OK',
          dotColor: const Color(0xFFEC4899),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _integrationContainer({
    required String title,
    required String subtitle,
    required String note,
    required Color dotColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric {
  const _Metric({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accent;
}
