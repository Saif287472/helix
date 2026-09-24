import 'package:flutter/material.dart';
import '../admin_client.dart';
import 'backup_tab.dart';
import 'config_tab.dart';
import 'logs_tab.dart';
import 'reports_tab.dart';

/// Unified "Operations & System" screen matching demo Images 4 & 5.
/// Provides a 4-segmented tab selector: [Reports], [Audit], [Logs], [Config].
class OpsTab extends StatefulWidget {
  const OpsTab({
    super.key,
    required this.client,
    required this.logs,
    required this.onRefreshLogs,
    required this.autoRefreshLogs,
    required this.onAutoRefreshLogsChanged,
    required this.config,
    required this.onSetWorldwideMode,
    required this.onSaveServerName,
    required this.serverHost,
    required this.isLoading,
    required this.onTriggerBackup,
    this.initialSubTab = 'reports',
  });

  final AdminClient client;
  final ServerLogs logs;
  final VoidCallback onRefreshLogs;
  final bool autoRefreshLogs;
  final ValueChanged<bool>? onAutoRefreshLogsChanged;
  final Map<String, dynamic>? config;
  final ValueChanged<bool> onSetWorldwideMode;
  final Future<String> Function(String name) onSaveServerName;
  final String? serverHost;
  final bool isLoading;
  final Future<void> Function() onTriggerBackup;
  final String initialSubTab;

  @override
  State<OpsTab> createState() => _OpsTabState();
}

class _OpsTabState extends State<OpsTab> {
  late String _currentSubTab;
  String _auditFilter = 'All';

  // Sample live audit log events matching demo Image 5
  final List<_AuditEvent> _auditEvents = [
    const _AuditEvent(
      code: 'ADMIN_USER_RECOVERY_ISSUED',
      details: 'Admin issued recovery token for user +1 555 019 2831',
      time: '14:22:08',
      ip: '192.168.1.42',
      session: '#8821',
      badge: 'SUCCESS',
      badgeColor: Color(0xFF059669),
      badgeBg: Color(0xFFECFDF5),
      category: 'Auth & Recovery',
    ),
    const _AuditEvent(
      code: 'DEVICE_AUTHORIZATION_REVOKED',
      details: 'Revoked session key for Android Device ID #4092',
      time: '13:58:11',
      ip: '192.168.1.42',
      session: '#8821',
      badge: 'AUDITED',
      badgeColor: Color(0xFFD97706),
      badgeBg: Color(0xFFFFFBEB),
      category: 'Security & Mod',
    ),
    const _AuditEvent(
      code: 'SYSTEM_BACKUP_COMPLETED',
      details: 'Encrypted SQLite snapshot generated (1.24 GB)',
      time: '12:00:00',
      ip: 'SYSTEM AUTOMATION',
      session: '#cron-00',
      badge: 'SYSTEM',
      badgeColor: Color(0xFF2563EB),
      badgeBg: Color(0xFFEFF6FF),
      category: 'System',
    ),
    const _AuditEvent(
      code: 'USER_ACCOUNT_SUSPENDED',
      details: 'Admin temporarily suspended account user_m_vance',
      time: '11:15:42',
      ip: '192.168.1.42',
      session: '#8821',
      badge: 'AUDITED',
      badgeColor: Color(0xFFD97706),
      badgeBg: Color(0xFFFFFBEB),
      category: 'Security & Mod',
    ),
    const _AuditEvent(
      code: 'FEDERATION_MODE_UPDATED',
      details: 'Worldwide Peer Network Mode set to ENABLED',
      time: '09:40:12',
      ip: '192.168.1.42',
      session: '#8820',
      badge: 'SUCCESS',
      badgeColor: Color(0xFF059669),
      badgeBg: Color(0xFFECFDF5),
      category: 'System',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _currentSubTab = widget.initialSubTab;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Node Header
          _buildNodeBanner(context),
          const SizedBox(height: 12),

          // 4-Segmented Tab Bar
          _buildSegmentedTabBar(context),
          const SizedBox(height: 16),

          // Subtab view
          switch (_currentSubTab) {
            'reports' => ReportsTab(client: widget.client),
            'audit' => _buildAuditView(context),
            'logs' => LogsTab(
                logs: widget.logs,
                onRefresh: widget.onRefreshLogs,
                autoRefreshEnabled: widget.autoRefreshLogs,
                onAutoRefreshChanged: widget.onAutoRefreshLogsChanged,
              ),
            'config' => ConfigTab(
                config: widget.config,
                federationDomainController: TextEditingController(
                  text: widget.config?['federation']?['domain'] ?? '',
                ),
                federationAddressController: TextEditingController(
                  text: widget.config?['federation']?['address'] ?? '',
                ),
                federationDirectoryController: TextEditingController(
                  text: widget.config?['federation']?['directory_url'] ?? '',
                ),
                onSetWorldwideMode: widget.onSetWorldwideMode,
                onSaveServerName: widget.onSaveServerName,
                serverHost: widget.serverHost,
                isLoading: widget.isLoading,
                onTriggerBackup: widget.onTriggerBackup,
              ),
            _ => ReportsTab(client: widget.client),
          },
        ],
      ),
    );
  }

  Widget _buildNodeBanner(BuildContext context) {
    return Column(
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
        const Text(
          'Operations & System',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentedTabBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          _segmentItem('Reports (3)', 'reports'),
          _segmentItem('Audit', 'audit'),
          _segmentItem('Logs', 'logs'),
          _segmentItem('Config', 'config'),
        ],
      ),
    );
  }

  Widget _segmentItem(String label, String tabKey) {
    final isSelected = _currentSubTab == tabKey;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentSubTab = tabKey),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF2563EB) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              color: isSelected ? Colors.white : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuditView(BuildContext context) {
    final filtered = _auditEvents.where((e) {
      if (_auditFilter == 'All') return true;
      return e.category == _auditFilter;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header Row with Live Stream Badge
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Live Administrative Audit Stream',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
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
                        'LIVE STREAM ACTIVE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF059669),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _auditChip('All Logs (${_auditEvents.length})', 'All'),
              const SizedBox(width: 8),
              _auditChip('Auth & Recovery', 'Auth & Recovery'),
              const SizedBox(width: 8),
              _auditChip('Security & Mod', 'Security & Mod'),
              const SizedBox(width: 8),
              _auditChip('System', 'System'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Audit Event Cards
        for (final event in filtered) ...[
          _buildAuditEventCard(context, event),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _auditChip(String label, String filterKey) {
    final isSelected = _auditFilter == filterKey;
    return GestureDetector(
      onTap: () => setState(() => _auditFilter = filterKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildAuditEventCard(BuildContext context, _AuditEvent event) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  event.code,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: event.badgeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  event.badge,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: event.badgeColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            event.details,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.access_time, size: 13, color: const Color(0xFF94A3B8)),
              const SizedBox(width: 4),
              Text(
                '${event.time} • IP: ${event.ip} • Session: ${event.session}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AuditEvent {
  const _AuditEvent({
    required this.code,
    required this.details,
    required this.time,
    required this.ip,
    required this.session,
    required this.badge,
    required this.badgeColor,
    required this.badgeBg,
    required this.category,
  });

  final String code;
  final String details;
  final String time;
  final String ip;
  final String session;
  final String badge;
  final Color badgeColor;
  final Color badgeBg;
  final String category;
}
