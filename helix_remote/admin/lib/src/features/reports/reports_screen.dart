import 'package:flutter/material.dart';
import 'package:helix_admin/src/features/accounts/account_detail_screen.dart';
import 'package:helix_admin/src/features/common/format.dart';
import 'package:helix_admin/src/features/reports/reports_controller.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/widgets/dialogs.dart';
import 'package:helix_admin/src/widgets/paged_list.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The moderation queue: open reports first, resolve or dismiss each, and
/// jump to the reported account.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.adminContext, this.pageSize});

  final AdminContext adminContext;
  final int? pageSize;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final ReportsController _reports;

  @override
  void initState() {
    super.initState();
    _reports = ReportsController(
      widget.adminContext,
      pageSize: widget.pageSize ?? PageRequest.defaultLimit,
    )..refresh();
  }

  @override
  void dispose() {
    _reports.dispose();
    super.dispose();
  }

  Future<void> _resolve(AdminReport report, ReportStatus outcome) async {
    final problem = await _reports.resolve(report.reportId, outcome);
    if (!mounted) return;
    showMessage(
      context,
      problem ??
          (outcome == ReportStatus.resolved
              ? 'Report resolved.'
              : 'Report dismissed.'),
    );
  }

  void _openAccount(AdminReport report) {
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AccountDetailScreen(
          adminContext: widget.adminContext,
          accountId: report.subject,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _reports,
      builder: (context, _) => PagedListView<AdminReport>(
        controller: _reports,
        emptyIcon: Icons.flag_outlined,
        emptyTitle: _reports.status == ReportStatus.open
            ? 'No open reports'
            : 'No reports',
        emptyMessage: _reports.status == ReportStatus.open
            ? 'Nothing is waiting for you.'
            : null,
        header: Padding(
          padding: const EdgeInsets.all(HelixSpace.md),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: HelixSpace.xs,
              children: [
                for (final (label, value) in const [
                  ('Open', ReportStatus.open),
                  ('Resolved', ReportStatus.resolved),
                  ('Dismissed', ReportStatus.dismissed),
                  ('All', null),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _reports.status == value,
                    onSelected: (_) => _reports.filterByStatus(value),
                  ),
              ],
            ),
          ),
        ),
        itemBuilder: (context, report) => _ReportCard(
          report: report,
          busy: _reports.isResolving(report.reportId),
          onResolve: () => _resolve(report, ReportStatus.resolved),
          onDismiss: () => _resolve(report, ReportStatus.dismissed),
          onOpenAccount: () => _openAccount(report),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.busy,
    required this.onResolve,
    required this.onDismiss,
    required this.onOpenAccount,
  });

  final AdminReport report;
  final bool busy;
  final VoidCallback onResolve;
  final VoidCallback onDismiss;
  final VoidCallback onOpenAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = report.note;
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: HelixSpace.md,
        vertical: HelixSpace.xxs,
      ),
      child: Padding(
        padding: const EdgeInsets.all(HelixSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _category(report.category),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                _StatusBadge(status: report.status),
              ],
            ),
            const SizedBox(height: HelixSpace.xxs),
            Text(
              'Account ${shortId(report.subject)} reported by '
              '${shortId(report.reporter)} · ${formatTime(report.createdAt)}',
              style: theme.textTheme.bodySmall,
            ),
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: HelixSpace.xs),
              Text(note),
            ],
            const SizedBox(height: HelixSpace.xs),
            Wrap(
              spacing: HelixSpace.xs,
              children: [
                TextButton(
                  onPressed: onOpenAccount,
                  child: const Text('Open account'),
                ),
                if (report.status == ReportStatus.open) ...[
                  FilledButton.tonal(
                    onPressed: busy ? null : onResolve,
                    child: const Text('Resolve'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : onDismiss,
                    child: const Text('Dismiss'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _category(ReportCategory category) => switch (category) {
    ReportCategory.spam => 'Spam',
    ReportCategory.abuse => 'Abuse',
    ReportCategory.impersonation => 'Impersonation',
    ReportCategory.other => 'Other',
  };
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ReportStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
    ReportStatus.open => const HelixStatusBadge(
      label: 'Open',
      color: HelixStatusColors.caution,
    ),
    ReportStatus.resolved => const HelixStatusBadge(
      label: 'Resolved',
      color: HelixStatusColors.positive,
    ),
    ReportStatus.dismissed => const HelixStatusBadge(
      label: 'Dismissed',
      color: HelixStatusColors.neutral,
    ),
    ReportStatus.unknown => const HelixStatusBadge(
      label: 'Unknown',
      color: HelixStatusColors.neutral,
    ),
  };
}
