import 'package:flutter/material.dart';
import 'package:helix_admin/src/features/accounts/account_detail_screen.dart';
import 'package:helix_admin/src/features/common/format.dart';
import 'package:helix_admin/src/features/reports/reports_controller.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
import 'package:helix_admin/src/widgets/dialogs.dart';
import 'package:helix_admin/src/widgets/paged_list.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The moderation queue: open reports first, resolve or dismiss each, and
/// jump to the reported account. The [controller] belongs to the caller (the
/// Ops screen reads its open count for the tab badge).
class ReportsView extends StatelessWidget {
  const ReportsView({
    super.key,
    required this.controller,
    required this.adminContext,
  });

  final ReportsController controller;
  final AdminContext adminContext;

  Future<void> _resolve(
    BuildContext context,
    AdminReport report,
    ReportStatus outcome,
  ) async {
    final problem = await controller.resolve(report.reportId, outcome);
    if (!context.mounted) return;
    showMessage(
      context,
      problem ??
          (outcome == ReportStatus.resolved
              ? 'Report resolved.'
              : 'Report dismissed.'),
    );
  }

  void _openAccount(BuildContext context, AdminReport report) {
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AccountDetailScreen(
          adminContext: adminContext,
          accountId: report.subject,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final open = controller.status == ReportStatus.open;
        return PagedListView<AdminReport>(
          controller: controller,
          emptyIcon: Icons.shield_outlined,
          emptyTitle: open ? 'No open reports' : 'No reports',
          emptyMessage: open
              ? 'Nothing is waiting for you. Reports people file about '
                    'accounts on this server appear here.'
              : 'Reports people file about accounts on this server appear '
                    'here.',
          gap: 12,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ConsoleHeading('User Reports & Moderation'),
              const SizedBox(height: 14),
              ConsoleChipRow(
                children: [
                  for (final (label, value) in const [
                    ('Open', ReportStatus.open),
                    ('Resolved', ReportStatus.resolved),
                    ('Dismissed', ReportStatus.dismissed),
                    ('All', null),
                  ])
                    ConsoleChip(
                      label:
                          value == ReportStatus.open &&
                              controller.status == value &&
                              controller.loaded &&
                              controller.items.isNotEmpty
                          ? '$label (${controller.items.length}'
                                '${controller.hasMore ? '+' : ''})'
                          : label,
                      selected: controller.status == value,
                      tone:
                          value == ReportStatus.open &&
                              controller.items.isNotEmpty &&
                              controller.status == value
                          ? ConsoleTone.danger
                          : null,
                      onTap: () => controller.filterByStatus(value),
                    ),
                ],
              ),
            ],
          ),
          itemBuilder: (context, report) => _ReportCard(
            report: report,
            busy: controller.isResolving(report.reportId),
            onResolve: () => _resolve(context, report, ReportStatus.resolved),
            onDismiss: () => _resolve(context, report, ReportStatus.dismissed),
            onOpenAccount: () => _openAccount(context, report),
          ),
        );
      },
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
    final note = report.note;
    final isOpen = report.status == ReportStatus.open;
    final (icon, tone) = switch (report.status) {
      ReportStatus.open => (Icons.priority_high_rounded, ConsoleTone.warn),
      ReportStatus.resolved => (Icons.check, ConsoleTone.ok),
      ReportStatus.dismissed => (Icons.close, ConsoleTone.neutral),
      ReportStatus.unknown => (Icons.help_outline, ConsoleTone.neutral),
    };
    return ConsoleCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tone.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: tone.text, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _category(report.category),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: HelixConsoleColors.text,
                  ),
                ),
              ),
              ConsolePill(
                label: switch (report.status) {
                  ReportStatus.open => 'Open',
                  ReportStatus.resolved => 'Resolved',
                  ReportStatus.dismissed => 'Dismissed',
                  ReportStatus.unknown => 'Unknown',
                },
                tone: tone,
                upper: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Account ${shortId(report.subject)} reported by '
            '${shortId(report.reporter)}',
            style: const TextStyle(
              fontSize: 13,
              color: HelixConsoleColors.textBody,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            formatTime(report.createdAt),
            style: const TextStyle(
              fontSize: 12,
              color: HelixConsoleColors.textMuted,
            ),
          ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              note,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: HelixConsoleColors.textBody,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (isOpen) ...[
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : onResolve,
                    style: ConsoleButtons.filled,
                    child: const Text('Resolve'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onDismiss,
                    style: ConsoleButtons.outlined,
                    child: const Text('Dismiss'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onOpenAccount,
              style: ConsoleButtons.outlined,
              child: const Text('Open account'),
            ),
          ),
        ],
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
