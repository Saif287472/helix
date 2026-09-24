import 'package:helix_remote_ui/helix_remote_ui.dart';
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

    final tiles = <_Metric>[
      _Metric(
        'Active Devices Connections',
        '${ws['connected_devices'] ?? 0}',
        Icons.wifi,
        Colors.green,
      ),
      _Metric(
        'Registered User Accounts',
        '${tblCounts['accounts'] ?? 0}',
        Icons.people,
        context.accentColor,
      ),
      _Metric(
        'Mailbox Encrypted Messages',
        '${tblCounts['messages'] ?? 0}',
        Icons.mail,
        HelixColorTokens.cFF8A2BE2,
      ),
      _Metric(
        'Quarantined Security Events',
        '${tblCounts['quarantine_events'] ?? 0}',
        Icons.security,
        Colors.orange,
      ),
      _Metric(
        'Outbox Delivery Retry Queue',
        '${tblCounts['outbox'] ?? 0}',
        Icons.sync_problem,
        Theme.of(context).colorScheme.error,
      ),
      _Metric(
        'Database Status Check',
        metrics['database_quick_check_ok'] == true ? 'HEALTHY' : 'UNHEALTHY',
        Icons.offline_bolt,
        Colors.green,
      ),
    ];

    if (metrics.containsKey('push_provider')) {
      final push = metrics['push_provider'] as Map? ?? {};
      final ok = push['configured'] == true && push['available'] == true;
      tiles.add(
        _Metric(
          'FCM Push Service',
          ok ? 'ACTIVE' : 'INACTIVE',
          Icons.notifications_active,
          ok ? Colors.green : Colors.grey,
        ),
      );
    }
    if (metrics.containsKey('turn')) {
      final turn = metrics['turn'] as Map? ?? {};
      final ok = turn['configured'] == true;
      tiles.add(
        _Metric(
          'TURN Relay Server',
          ok ? 'ACTIVE' : 'INACTIVE',
          Icons.cell_tower,
          ok ? Colors.green : Colors.grey,
        ),
      );
    }
    if (metrics.containsKey('sms') || metrics.containsKey('sms_gateway')) {
      final sms = metrics['sms'] as Map? ?? metrics['sms_gateway'] as Map? ?? {};
      final ok = sms['configured'] == true;
      tiles.add(
        _Metric(
          'SMS OTP Gateway',
          ok ? 'ACTIVE' : 'INACTIVE',
          Icons.sms,
          ok ? Colors.green : Colors.grey,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // On a phone the grid tiles are the wrong shape: a single number
        // in a tile 150dp tall means six metrics take about a metre of
        // scrolling. One compact row each fits the same information in
        // roughly a third of the height and keeps it all on one screen.
        if (width <= 600) {
          return ListView.separated(
            itemCount: tiles.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _metricRow(context, tiles[index]),
          );
        }
        return GridView.count(
          crossAxisCount: width > 1200 ? 3 : 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.6,
          children: [for (final tile in tiles) _metricCard(context, tile)],
        );
      },
    );
  }

  /// Compact one-line-per-metric layout used on phone-width screens.
  Widget _metricRow(BuildContext context, _Metric metric) {
    return Card(
      elevation: 0,
      margin: HelixInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: HelixInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: metric.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(metric.icon, color: metric.accent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                metric.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: context.textSecondary),
              ),
            ),
            const SizedBox(width: 12),
            // Word values like UNHEALTHY are far wider than a count, so
            // they scale down rather than pushing the label into an
            // ellipsis.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  metric.value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Roomier tile layout, kept for tablet and desktop widths where there
  /// is horizontal space to spend.
  Widget _metricCard(BuildContext context, _Metric metric) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: HelixInsets.all(24),
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
                    style: TextStyle(
                      fontSize: 14,
                      color: context.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(metric.icon, color: metric.accent),
              ],
            ),
            Text(
              metric.value,
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

class _Metric {
  const _Metric(this.title, this.value, this.icon, this.accent);

  final String title;
  final String value;
  final IconData icon;
  final Color accent;
}
