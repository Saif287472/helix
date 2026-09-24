import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';
import '../admin_client.dart';
import '../theme/app_theme.dart';

/// Reports tab for reviewing user-submitted safety, abuse, and content reports.
/// Provides moderation tools for reviewing reports, resolving cases, or taking action.
class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key, required this.client});

  final AdminClient client;

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  String _selectedFilter = 'All';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Sample/placeholder reports data for preview and demonstration
  late List<Map<String, dynamic>> _reports;

  @override
  void initState() {
    super.initState();
    _reports = [
      {
        'id': 'rep_001',
        'reported_user': 'SpamBot99',
        'reported_account_id': '8f12a34b',
        'reporter': 'Alice Miller',
        'reporter_account_id': '4c3d2e1f',
        'reason': 'Spam / Advertising',
        'details':
            'Sending repeated unsolicited phishing links to multiple members in private chat.',
        'created_at': DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
        'status': 'Pending',
      },
      {
        'id': 'rep_002',
        'reported_user': 'UnknownSender',
        'reported_account_id': 'a7b8c9d0',
        'reporter': 'Bob Vance',
        'reporter_account_id': '1b2c3d4e',
        'reason': 'Harassment / Abuse',
        'details':
            'Inappropriate language and persistent unsolicited messages after being asked to stop.',
        'created_at': DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        'status': 'Under Review',
      },
      {
        'id': 'rep_003',
        'reported_user': 'FakeSupport',
        'reported_account_id': '33aa44bb',
        'reporter': 'Charlie Day',
        'reporter_account_id': '55cc66dd',
        'reason': 'Impersonation',
        'details':
            'Claiming to be an official Helix server admin requesting account recovery keys.',
        'created_at': DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch,
        'status': 'Resolved',
      },
    ];
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredReports {
    return _reports.where((r) {
      if (_selectedFilter != 'All' && r['status'] != _selectedFilter) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final reported = (r['reported_user'] as String).toLowerCase();
        final reporter = (r['reporter'] as String).toLowerCase();
        final reason = (r['reason'] as String).toLowerCase();
        final details = (r['details'] as String).toLowerCase();
        return reported.contains(q) ||
            reporter.contains(q) ||
            reason.contains(q) ||
            details.contains(q);
      }
      return true;
    }).toList();
  }

  void _showReportDetails(Map<String, dynamic> report) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.flag_outlined, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Report: ${report['reason']}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('Report ID', report['id'] as String),
              const SizedBox(height: 8),
              _detailRow('Reported User', '${report['reported_user']} (${report['reported_account_id']})'),
              const SizedBox(height: 8),
              _detailRow('Reporter', '${report['reporter']} (${report['reporter_account_id']})'),
              const SizedBox(height: 8),
              _detailRow('Submitted', _formatTimestamp(report['created_at'])),
              const SizedBox(height: 8),
              _detailRow('Current Status', report['status'] as String),
              const SizedBox(height: 16),
              const Text(
                'Report Details & Evidence:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: HelixInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(ctx).colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  report['details'] as String,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          OutlinedButton(
            onPressed: () {
              setState(() {
                report['status'] = 'Dismissed';
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Report dismissed')),
              );
            },
            child: const Text('Dismiss'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                report['status'] = 'Resolved';
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Report marked as Resolved')),
              );
            },
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: Theme.of(context).textTheme.bodyMedium?.color,
          fontSize: 13,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic value) {
    if (value is! int || value == 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(value);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredReports;
    final pendingCount = _reports.where((r) => r['status'] == 'Pending').length;
    final reviewCount = _reports.where((r) => r['status'] == 'Under Review').length;
    final resolvedCount = _reports.where((r) => r['status'] == 'Resolved').length;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card
          Card(
            child: Padding(
              padding: HelixInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'User Reports',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh reports',
                        icon: const Icon(Icons.refresh),
                        onPressed: () => setState(() {}),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Review and moderate safety, abuse, and harassment reports submitted by server members.',
                    style: TextStyle(color: context.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  // Summary Badges / Stats
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _StatBadge(
                        label: 'Total Reports',
                        count: _reports.length,
                        icon: Icons.flag,
                        color: Colors.blue,
                      ),
                      _StatBadge(
                        label: 'Pending Review',
                        count: pendingCount,
                        icon: Icons.pending_actions,
                        color: Colors.amber.shade800,
                      ),
                      _StatBadge(
                        label: 'Under Review',
                        count: reviewCount,
                        icon: Icons.search,
                        color: Colors.purple,
                      ),
                      _StatBadge(
                        label: 'Resolved',
                        count: resolvedCount,
                        icon: Icons.check_circle_outline,
                        color: Colors.green,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Main Table & Filters Card
          Card(
            child: Padding(
              padding: HelixInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Search & Filter Row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search by user, reporter, or reason…',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onChanged: (v) => setState(() => _searchQuery = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Filter Chips
                  Wrap(
                    spacing: 8,
                    children: ['All', 'Pending', 'Under Review', 'Resolved', 'Dismissed']
                        .map(
                          (filter) => ChoiceChip(
                            label: Text(filter),
                            selected: _selectedFilter == filter,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _selectedFilter = filter);
                              }
                            },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 20),

                  if (filtered.isEmpty)
                    Padding(
                      padding: HelixInsets.all(32),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.verified_outlined,
                              size: 48,
                              color: context.textFaint,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No reports matching current filter.',
                              style: TextStyle(color: context.textFaint),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Report ID')),
                          DataColumn(label: Text('Reported User')),
                          DataColumn(label: Text('Reporter')),
                          DataColumn(label: Text('Reason')),
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: filtered.map((report) {
                          final status = report['status'] as String;
                          return DataRow(
                            cells: [
                              DataCell(Text(report['id'] as String)),
                              DataCell(Text('${report['reported_user']} (${report['reported_account_id']})')),
                              DataCell(Text(report['reporter'] as String)),
                              DataCell(Text(report['reason'] as String)),
                              DataCell(Text(_formatTimestamp(report['created_at']))),
                              DataCell(_statusChip(status)),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.visibility_outlined, size: 20),
                                      tooltip: 'View details & investigate',
                                      onPressed: () => _showReportDetails(report),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.check, size: 20, color: Colors.green),
                                      tooltip: 'Mark resolved',
                                      onPressed: () {
                                        setState(() => report['status'] = 'Resolved');
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Report marked as Resolved')),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final (Color color, Color bg) = switch (status) {
      'Pending' => (Colors.amber.shade900, Colors.amber.withValues(alpha: 0.15)),
      'Under Review' => (Colors.purple, Colors.purple.withValues(alpha: 0.15)),
      'Resolved' => (Colors.green, Colors.green.withValues(alpha: 0.15)),
      'Dismissed' => (Colors.grey, Colors.grey.withValues(alpha: 0.15)),
      _ => (Colors.blue, Colors.blue.withValues(alpha: 0.15)),
    };

    return Chip(
      label: Text(
        status,
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
      ),
      backgroundColor: bg,
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      padding: EdgeInsets.zero,
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 12, color: context.textSecondary),
          ),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
