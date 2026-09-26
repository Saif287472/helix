import 'package:flutter/material.dart';
import '../admin_client.dart';

/// User Reports & Moderation Flags screen matching reference design.
class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key, required this.client});

  final AdminClient client;

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  static const _pageSize = 50;

  String _selectedFilter = 'Total Reports';
  List<Map<String, dynamic>> _reports = [];
  bool _loading = false;
  String? _error;
  String? _actioningReportId;

  int _offset = 0;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports({int offset = 0}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await widget.client.getReports(
        limit: _pageSize,
        offset: offset,
      );
      final mapped = raw.map(_mapReport).toList();

      if (!mounted) return;
      setState(() {
        _reports = mapped;
        _offset = offset;
        _hasMore = raw.length == _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Surfaced, not swallowed: a transport failure must be
        // distinguishable from "there are no reports".
        _error = e.toString();
      });
    }
  }

  static Map<String, dynamic> _mapReport(Map<String, dynamic> r) {
    final rawStatus = (r['status'] as String? ?? 'PENDING').toUpperCase();
    final displayStatus = switch (rawStatus) {
      'PENDING' => 'Pending',
      'UNDER REVIEW' || 'ACTIONED' => 'Under Review',
      'RESOLVED' => 'Resolved',
      'DISMISSED' => 'Dismissed',
      _ => 'Pending',
    };

    return {
      'id': (r['report_id'] ?? r['id'] ?? '').toString(),
      'reason': (r['category'] ?? r['reason'] ?? 'Report').toString(),
      'reported_user':
          (r['subject_display_name'] ??
                  r['reported_user'] ??
                  r['subject_account_id'] ??
                  'Unknown')
              .toString(),
      'reporter':
          (r['reporter_display_name'] ??
                  r['reporter'] ??
                  r['reporter_account_id'] ??
                  'Anonymous')
              .toString(),
      'details':
          (r['context_hash'] ??
                  r['details'] ??
                  r['reason_code'] ??
                  'No additional details')
              .toString(),
      'status': displayStatus,
      'created_at': r['created_at'] is int
          ? r['created_at']
          : (DateTime.tryParse(
                  r['created_at']?.toString() ?? '',
                )?.millisecondsSinceEpoch ??
                0),
    };
  }

  Future<void> _resolveReport(String reportId) async {
    setState(() => _actioningReportId = reportId);
    try {
      await widget.client.resolveReport(reportId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report marked as Resolved')),
      );
      await _loadReports(offset: _offset);
    } catch (e) {
      // A failed resolution is reported as a failure. The row is left
      // untouched so the screen cannot disagree with the server.
      //
      // `_error` is deliberately NOT set here. It is the load-failure field,
      // and `build` replaces the entire report list with it - so a single
      // refused action used to blank the moderation queue and leave the
      // operator staring at an error page with no way back to the reports they
      // were working through. The snackbar below is the right surface for a
      // per-action failure.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not resolve report: $e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    } finally {
      if (mounted) setState(() => _actioningReportId = null);
    }
  }

  Future<void> _dismissReport(String reportId) async {
    setState(() => _actioningReportId = reportId);
    try {
      await widget.client.dismissReport(reportId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report dismissed')),
      );
      await _loadReports(offset: _offset);
    } catch (e) {
      // See _resolveReport: `_error` blanks the whole list, which is wrong
      // for a single refused action.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not dismiss report: $e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    } finally {
      if (mounted) setState(() => _actioningReportId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reportsList = _reports;

    final pendingCount = reportsList.where((r) => r['status'] == 'Pending').length;
    final underReviewCount = reportsList.where((r) => r['status'] == 'Under Review' || r['status'] == 'Actioned').length;
    final resolvedCount = reportsList.where((r) => r['status'] == 'Resolved' || r['status'] == 'Dismissed').length;

    final filtered = reportsList.where((r) {
      final status = r['status'] as String;
      if (_selectedFilter == 'Pending') return status == 'Pending';
      if (_selectedFilter == 'Under Review') return status == 'Under Review' || status == 'Actioned';
      if (_selectedFilter == 'Resolved') return status == 'Resolved' || status == 'Dismissed';
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section Header
        _buildSectionHeader(),
        const SizedBox(height: 16),

        // Filter Pills Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterPill(
                label: 'Total Reports',
                count: reportsList.length,
                filterKey: 'Total Reports',
              ),
              const SizedBox(width: 8),
              _buildFilterPill(
                label: 'Pending',
                count: pendingCount,
                filterKey: 'Pending',
              ),
              const SizedBox(width: 8),
              _buildFilterPill(
                label: 'Under Review',
                count: underReviewCount,
                filterKey: 'Under Review',
              ),
              const SizedBox(width: 8),
              _buildFilterPill(
                label: 'Resolved',
                count: resolvedCount,
                filterKey: 'Resolved',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Reports Cards List
        if (_loading && _reports.isEmpty)
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
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined, size: 36, color: Color(0xFF94A3B8)),
                  SizedBox(height: 10),
                  Text(
                    'No user reports or moderation flags.',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF334155),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'User reports submitted to this node will appear here.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          )
        else
          Column(
            children: [
              for (final report in filtered) _buildReportCard(report),
              if (!_loading && (_hasMore || _offset > 0)) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: const Key('reports_previous_page'),
                      onPressed: _offset > 0
                          ? () => _loadReports(
                              offset: (_offset - _pageSize).clamp(0, 1 << 30),
                            )
                          : null,
                      child: const Text('Previous'),
                    ),
                    TextButton(
                      key: const Key('reports_next_page'),
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
      ],
    );
  }

  Widget _buildSectionHeader() {
    return const Text(
      'User Reports & Moderation Flags',
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF0F172A),
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _buildFilterPill({
    required String label,
    required int count,
    required String filterKey,
  }) {
    final isSelected = _selectedFilter == filterKey;
    final text = '$label ($count)';
    final isPendingWithItems = filterKey == 'Pending' && count > 0;

    Color bgColor = isSelected ? const Color(0xFF2563EB) : Colors.white;
    Color borderClr = isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0);
    Color textClr = isSelected ? Colors.white : const Color(0xFF475569);

    if (isPendingWithItems) {
      if (isSelected) {
        bgColor = const Color(0xFFDC2626);
        borderClr = const Color(0xFFDC2626);
        textClr = Colors.white;
      } else {
        bgColor = const Color(0xFFFEF2F2);
        borderClr = const Color(0xFFFCA5A5);
        textClr = const Color(0xFFDC2626);
      }
    }

    return InkWell(
      onTap: () => setState(() => _selectedFilter = filterKey),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderClr),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: bgColor.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: textClr,
          ),
        ),
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
    final isUnderReview = status == 'Under Review' || status == 'Actioned';
    final isResolved = status == 'Resolved' || status == 'Dismissed';

    final IconData icon = isResolved
        ? Icons.check
        : (isUnderReview ? Icons.search : Icons.priority_high_rounded);

    final Color iconColor = isResolved
        ? const Color(0xFF059669)
        : (isUnderReview ? const Color(0xFF2563EB) : const Color(0xFFD97706));

    final Color iconBg = isResolved
        ? const Color(0xFFECFDF5)
        : (isUnderReview ? const Color(0xFFEFF6FF) : const Color(0xFFFEF3C7));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Icon + Title + Status Badge (for Under Review / Resolved)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
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
              if (isUnderReview)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Text(
                    'UNDER REVIEW',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFD97706),
                      letterSpacing: 0.5,
                    ),
                  ),
                )
              else if (isResolved)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: const Text(
                    'RESOLVED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF059669),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Details Body
          Text(
            reportedUser.startsWith('Anonymous') || reportedUser.startsWith('Node') || reportedUser.startsWith('Account')
                ? (reportedUser.contains('Node') || reportedUser.contains('Peer') ? 'Reported node: $reportedUser' : 'Reported user: $reportedUser')
                : 'Reported user: $reportedUser',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            reporter.startsWith('Master') || reporter.startsWith('System')
                ? 'Investigator: $reporter • $details'
                : 'Reporter: $reporter • Reason: $details',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              height: 1.3,
            ),
          ),

          // Action buttons bar spanning the bottom of the card if Pending
          if (isPending) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    onPressed: isBusy ? null : () => _resolveReport(reportId),
                    child: isBusy
                        ? const SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'Resolve',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1E293B),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: isBusy ? null : () => _dismissReport(reportId),
                    child: const Text(
                      'Dismiss',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
