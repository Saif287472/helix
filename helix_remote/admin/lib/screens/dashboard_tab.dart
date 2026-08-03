import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width > 1200 ? 3 : (width > 600 ? 2 : 1);
        return GridView.count(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: crossAxisCount == 1 ? 2.4 : 1.6,
          children: [
            _metricCard(
              context,
              'Active Devices Connections',
              '${ws['connected_devices'] ?? 0}',
              Icons.wifi,
              Colors.green,
            ),
            _metricCard(
              context,
              'Registered User Accounts',
              '${tblCounts['accounts'] ?? 0}',
              Icons.people,
              context.accentColor,
            ),
            _metricCard(
              context,
              'Mailbox Encrypted Messages',
              '${tblCounts['messages'] ?? 0}',
              Icons.mail,
              const Color(0xFF8A2BE2),
            ),
            _metricCard(
              context,
              'Quarantined Security Events',
              '${tblCounts['quarantine_events'] ?? 0}',
              Icons.security,
              Colors.orange,
            ),
            _metricCard(
              context,
              'Outbox Delivery Retry Queue',
              '${tblCounts['outbox'] ?? 0}',
              Icons.sync_problem,
              Theme.of(context).colorScheme.error,
            ),
            _metricCard(
              context,
              'Database Status Check',
              metrics['database_quick_check_ok'] == true
                  ? 'HEALTHY'
                  : 'UNHEALTHY',
              Icons.offline_bolt,
              Colors.green,
            ),
          ],
        );
      },
    );
  }

  Widget _metricCard(
    BuildContext context,
    String title,
    String val,
    IconData icon,
    Color accent,
  ) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: context.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, color: accent),
              ],
            ),
            Text(
              val,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
