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

  List<Map<String, dynamic>> _reports = [];
  bool _loading = false;
  String? _error;
  int _offset = 0;
  static const int _pageSize = 50;
  bool _hasMore = false;
  String? _actioningReportId;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadReports({int offset = 0}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await widget.client.getReports(limit: _pageSize, offset: offset);
      final mapped = raw.map((r) {
        final rawStatus = (r['status'] as String? ?? 'PENDING').toUpperCase();
        final displayStatus = switch (rawStatus) {
          'PENDING' => 'Pending',
          'ACTIONED' => 'Actioned',
          'RESOLVED' => 'Resolved',
          'DISMISSED' => 'Dismissed',
          _ => rawStatus.substring(0, 1) + rawStatus.substring(1).toLowerCase(),
        };

        return {
          'id': (r['report_id'] ?? r['id'] ?? '').toString(),
          'reported_user': (r['subject_display_name'] ?? r['reported_user'] ?? r['subject_account_id'] ?? 'Unknown').toString(),
          'reported_account_id': (r['subject_account_id'] ?? r['reported_account_id'] ?? '').toString(),
          'reporter': (r['reporter_display_name'] ?? r['reporter'] ?? r['reporter_account_id'] ?? 'Anonymous').toString(),
          'reporter_account_id': (r['reporter_account_id'] ?? '').toString(),
          'reason': (r['category'] ?? r['reason'] ?? 'Report').toString(),
          'details': (r['context_hash'] ?? r['details'] ?? r['reason_code'] ?? 'No additional details provided.').toString(),
          'created_at': r['created_at'] is int
              ? r['created_at']
              : (DateTime.tryParse(r['created_at']?.toString() ?? '')?.millisecondsSinceEpoch ?? 0),
          'status': displayStatus,
        };
      }).toList();

      if (!mounted) return;
      setState(() {
        _reports = mapped;
        _offset = offset;
        _hasMore = mapped.length == _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _resolveReport(String reportId) async {
    setState(() => _actioningReportId = reportId);
    try {
      await widget.client.resolveReport(reportId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report marked as Resolved')),
        );
      }
      await _loadReports(offset: _offset);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resolve report: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _actioningReportId = null);
    }
  }

  Future<void> _dismissReport(String reportId) async {
    setState(() => _actioningReportId = reportId);
    try {
      await widget.client.dismissReport(reportId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report dismissed')),
        );
      }
      await _loadReports(offset: _offset);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to dismiss report: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _actioningReportId = null);
    }
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
    final reportId = report['id'] as String;
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
              _detailRow('Report ID', reportId),
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
              Navigator.pop(ctx);
              _dismissReport(reportId);
            },
            child: const Text('Dismiss'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _resolveReport(reportId);
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
    final actionedCount = _reports.where((r) => r['status'] == 'Actioned').length;
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
                        onPressed: () => _loadReports(offset: _offset),
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
                        label: 'Actioned',
                        count: actionedCount,
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
                    children: ['All', 'Pending', 'Actioned', 'Resolved', 'Dismissed']
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

                  if (_loading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    )
                  else if (filtered.isEmpty)
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
                              _reports.isEmpty
                                  ? 'No reports submitted yet.'
                                  : 'No reports matching current filter.',
                              style: TextStyle(color: context.textFaint),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        for (final report in filtered) _buildReportCard(report),
                      ],
                    ),

                  if (!_loading && (_reports.isNotEmpty || _offset > 0)) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _offset > 0
                              ? () => _loadReports(offset: (_offset - _pageSize).clamp(0, 1 << 30))
                              : null,
                          child: const Text('Previous'),
                        ),
                        TextButton(
                          onPressed: _hasMore
                              ? () => _loadReports(offset: _offset + _pageSize)
                              : null,
                          child: const Text('Next'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    final reportId = report['id'] as String;
    final status = report['status'] as String;
    final isBusy = _actioningReportId == reportId;
    final reason = report['reason'] as String;
    final reportedUser = report['reported_user'] as String;
    final reporter = report['reporter'] as String;
    final details = report['details'] as String;
    final isPending = status == 'Pending';
    final isResolved = status == 'Resolved';

    final Color iconColor = isResolved
        ? const Color(0xFF059669)
        : (reason.toLowerCase().contains('spam')
            ? const Color(0xFF2563EB)
            : const Color(0xFFD97706));
    final IconData icon = isResolved
        ? Icons.check_circle_outline
        : (reason.toLowerCase().contains('spam')
            ? Icons.search
            : Icons.warning_amber_rounded);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            reason,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        _statusChip(status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Target: $reportedUser',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Reported by: $reporter • ${_formatTimestamp(report['created_at'])}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (details.isNotEmpty && details != 'No additional details provided.') ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                details,
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.info_outline, size: 20),
                tooltip: 'Investigate details',
                onPressed: () => _showReportDetails(report),
              ),
              const SizedBox(width: 8),
              if (isPending) ...[
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF64748B),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                  onPressed: isBusy ? null : () => _dismissReport(reportId),
                  child: const Text('Dismiss', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                  onPressed: isBusy ? null : () => _resolveReport(reportId),
                  child: isBusy
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Resolve', style: TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final (Color color, Color bg) = switch (status) {
      'Pending' => (Colors.amber.shade900, Colors.amber.withValues(alpha: 0.15)),
      'Actioned' => (Colors.purple, Colors.purple.withValues(alpha: 0.15)),
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
