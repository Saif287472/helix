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

    return GridView.count(
      crossAxisCount: MediaQuery.of(context).size.width > 1200 ? 3 : 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.6,
      children: [
        _metricCard(
          'Active Devices Connections',
          '${ws['connected_devices'] ?? 0}',
          Icons.wifi,
          Colors.green,
        ),
        _metricCard(
          'Registered User Accounts',
          '${tblCounts['accounts'] ?? 0}',
          Icons.people,
          const Color(0xFF00E5FF),
        ),
        _metricCard(
          'Mailbox Encrypted Messages',
          '${tblCounts['messages'] ?? 0}',
          Icons.mail,
          const Color(0xFF8A2BE2),
        ),
        _metricCard(
          'Quarantined Security Events',
          '${tblCounts['quarantine_events'] ?? 0}',
          Icons.security,
          Colors.orange,
        ),
        _metricCard(
          'Outbox Delivery Retry Queue',
          '${tblCounts['outbox'] ?? 0}',
          Icons.sync_problem,
          const Color(0xFFFF3366),
        ),
        _metricCard(
          'Database Status Check',
          metrics['database_quick_check_ok'] == true ? 'HEALTHY' : 'UNHEALTHY',
          Icons.offline_bolt,
          Colors.green,
        ),
      ],
    );
  }

  Widget _metricCard(String title, String val, IconData icon, Color accent) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: const Color(0xFF161624),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
                Icon(icon, color: accent),
              ],
            ),
            Text(
              val,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
