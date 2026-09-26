import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:flutter/material.dart';

/// Status-dot palette for the Service Integration Health cards. Green only
/// means "the server says this is working"; amber means "set up but broken";
/// slate means "not set up".
const _ok = Color(0xFF10B981);
const _warn = Color(0xFFF59E0B);
const _off = Color(0xFF94A3B8);

class DashboardTab extends StatelessWidget {
  const DashboardTab({
    super.key,
    required this.metrics,
    this.latencyMs,
  });

  final Map<String, dynamic>? metrics;

  /// Last measured round-trip time in milliseconds, or null when nothing has
  /// been measured yet. The dashboard renders "Latency: —" rather than a
  /// placeholder number in that case.
  final int? latencyMs;

  @override
  Widget build(BuildContext context) {
    final metrics = this.metrics;
    if (metrics == null) {
      return const Center(child: Text('No metrics available. Click refresh.'));
    }
    final tblCounts = metrics['table_counts'] as Map? ?? {};
    final ws = metrics['websocket'] as Map? ?? {};
    final dbOk = metrics['database_quick_check_ok'] == true;

    final rawDbBytes = metrics['database_bytes'] ?? metrics['db_bytes'];
    final dbBytes = rawDbBytes is int
        ? rawDbBytes
        : (int.tryParse(rawDbBytes?.toString() ?? '') ?? 0);

    final totalRows = tblCounts.values.fold<int>(
      0,
      (sum, count) => sum + (count is int ? count : 0),
    );

    final String dbSizeLabel;
    if (dbBytes > 0) {
      if (dbBytes < 1024) {
        dbSizeLabel = '$dbBytes B SQLite DB';
      } else if (dbBytes < 1024 * 1024) {
        dbSizeLabel = '${(dbBytes / 1024).toStringAsFixed(1)} KB SQLite DB';
      } else if (dbBytes < 1024 * 1024 * 1024) {
        dbSizeLabel = '${(dbBytes / (1024 * 1024)).toStringAsFixed(2)} MB SQLite DB';
      } else {
        dbSizeLabel = '${(dbBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB SQLite DB';
      }
    } else {
      dbSizeLabel = '$totalRows Records SQLite';
    }

    final tiles = <_Metric>[
      _Metric(
        title: 'Active Devices Connections',
        value: '${ws['connected_devices'] ?? 0}',
        icon: Icons.phone_android_outlined,
        accent: const Color(0xFF10B981),
      ),
      _Metric(
        title: 'Registered User Accounts',
        value: '${tblCounts['accounts'] ?? 0}',
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
        title: 'Database Status Check',
        value: dbOk ? 'HEALTHY' : 'UNHEALTHY',
        subtitle: dbSizeLabel,
        icon: Icons.dns_outlined,
        accent: dbOk ? const Color(0xFF10B981) : const Color(0xFFEF4444),
      ),
    ];

    return SingleChildScrollView(
      padding: HelixInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopBanner(context),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width > 1200 ? 3 : 2;
              // A two-column tile on a 320dp phone is about 138dp wide. At a
              // 1.35 ratio that leaves ~102dp of height for a card whose
              // content (12dp padding, a two-line 12dp title beside a 28dp
              // icon, a 22dp value, an 11dp subtitle) needs a little more,
              // and the subtitle row clipped. 1.25 gives the content the room
              // it actually requires.
              final aspectRatio = width <= 600
                  ? 1.25
                  : (width > 1200 ? 1.8 : 1.6);
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: aspectRatio,
                children: [for (final tile in tiles) _metricCard(context, tile)],
              );
            },
          ),
          _buildServiceIntegrations(context),
        ],
      ),
    );
  }

  Widget _buildTopBanner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Flexible so the title yields space to the status pill on a
              // narrow phone instead of overflowing the row.
              const Flexible(
                child: Text(
                  'Dashboard',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              const SizedBox(width: 8),
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
                    Text(
                      latencyMs != null
                          ? 'Latency: ${latencyMs}ms'
                          : 'Latency: —',
                      style: const TextStyle(
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: metric.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(metric.icon, color: metric.accent, size: 16),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    metric.value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: metric.value == 'HEALTHY'
                          ? const Color(0xFF059669)
                          : (metric.value == 'UNHEALTHY'
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF0F172A)),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                if (metric.subtitle != null)
                  Text(
                    metric.subtitle!,
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
          ],
        ),
      ),
    );
  }

  Widget _buildServiceIntegrations(BuildContext context) {
    final metrics = this.metrics ?? const <String, dynamic>{};
    final push = metrics['push_provider'] as Map?;
    final sms = metrics['sms_provider'] as Map?;
    final turn = metrics['turn'] as Map?;

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
        _pushHealthCard(push),
        const SizedBox(height: 10),
        _smsHealthCard(sms),
        const SizedBox(height: 10),
        _turnHealthCard(turn),
        const SizedBox(height: 24),
        _buildCrashTelemetry(metrics['telemetry'] as Map?),
      ],
    );
  }

  /// Crash-sink counters, straight from `metrics.telemetry`.
  ///
  /// Before this the dashboard carried a hardcoded "Background message waking
  /// OK" note while the counters sat unused. Rejections are the signal to
  /// look at: they mean a client is trying to report and the server is
  /// refusing, which is either the flag being off or a client on a build
  /// that predates the consent prompt.
  Widget _buildCrashTelemetry(Map? telemetry) {
    final accepted = telemetry?['crash_reports_accepted'] as int? ?? 0;
    final rejected = telemetry?['crash_reports_rejected'] as int? ?? 0;
    final lastRaw = telemetry?['last_crash_report_at'] as String?;
    final last = lastRaw == null ? null : DateTime.tryParse(lastRaw);
    final lastLabel = last == null
        ? 'No report has ever been accepted'
        : 'Last accepted ${last.toLocal().toString().split('.').first}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Client Crash Reports',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 12),
        Container(
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
                  color: rejected > 0 ? _warn : _ok,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$accepted accepted • $rejected rejected',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lastLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    if (rejected > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        rejected == 1
                            ? '1 report was refused. Clients must have crash '
                                  'reporting enabled and consent granted; the '
                                  'server flag must also be on.'
                            : '$rejected reports were refused. Clients must '
                                  'have crash reporting enabled and consent '
                                  'granted; the server flag must also be on.',
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// FCM: green only when the provider reports itself available. "Configured
  /// but unavailable" is a distinct, actionable state from "not configured",
  /// so it gets its own colour rather than being folded into either.
  Widget _pushHealthCard(Map? push) {
    final configured = push?['configured'] == true;
    final available = push?['available'] == true;

    final Color dot;
    final String status;
    final String note;
    if (available) {
      dot = _ok;
      status = 'Firebase Cloud Messaging • Available';
      note = 'Background message waking is active.';
    } else if (configured) {
      dot = _warn;
      status = 'Firebase Cloud Messaging • Configured but unavailable';
      note = 'The server has FCM credentials but the provider is not '
          'responding. Background delivery will not work until it is.';
    } else {
      dot = _off;
      status = 'Firebase Cloud Messaging • Not configured';
      note = 'No FCM credentials on this server. Push notifications are '
          'unavailable; messages arrive over the WebSocket only.';
    }
    return _integrationContainer(
      title: 'FCM Push Notification Service',
      subtitle: status,
      note: note,
      dotColor: dot,
    );
  }

  /// SMS: the server reports whether a gateway is wired up and which one. It
  /// cannot report whether the credential is valid - BulkSMSBD answers HTTP
  /// 200 for a rejected key - so the copy says so rather than claiming health.
  Widget _smsHealthCard(Map? sms) {
    final configured = sms?['configured'] == true;
    final name = sms?['name'] as String? ?? 'None';

    return _integrationContainer(
      title: 'SMS Gateway',
      subtitle: configured
          ? '$name • Configured'
          : 'No SMS provider configured',
      note: configured
          ? 'A gateway is wired up. Credential validity is not reported by '
              'the server - a rejected API key still returns success at the '
              'HTTP layer, so a failed signup is the first real signal.'
          : 'One-time sign-in codes cannot be delivered on this server.',
      dotColor: configured ? _ok : _off,
    );
  }

  /// TURN: `configured` comes from the server; `url_count` is real. Live
  /// reachability is explicitly not probed, and the copy says so instead of
  /// implying a relay handshake succeeded.
  Widget _turnHealthCard(Map? turn) {
    final configured = turn?['configured'] == true;
    final urlCount = turn?['url_count'];

    return _integrationContainer(
      title: 'TURN Relay Server',
      subtitle: configured
          ? 'STUN/TURN peer connection • $urlCount URL${urlCount == 1 ? '' : 's'} configured'
          : 'STUN/TURN peer connection • Not configured',
      note: configured
          ? 'Voice and video relay credentials are available. Live '
              'reachability is not probed by the server.'
          : 'Calls can place but will not relay media through TURN.',
      dotColor: configured ? _ok : _off,
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
    required this.icon,
    required this.accent,
    this.subtitle,
  });

  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color accent;
}
