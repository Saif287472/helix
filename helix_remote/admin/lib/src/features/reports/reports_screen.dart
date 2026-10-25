import 'package:flutter/material.dart';
import 'package:helix_admin/src/features/accounts/account_detail_screen.dart';
import 'package:helix_admin/src/features/common/format.dart';
import 'package:helix_admin/src/features/reports/reports_controller.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
import 'package:helix_admin/src/widgets/console_sheet.dart';
import 'package:helix_admin/src/widgets/dialogs.dart';
import 'package:helix_admin/src/widgets/paged_list.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The Reports place: the moderation queue, with the state that belongs to it.
/// [onOpenCount] passes what is waiting up to the shell, so the count on the
/// navigation item and the queue the operator is looking at always agree.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    required this.adminContext,
    this.onOpenCount,
    this.pageSize,
  });

  final AdminContext adminContext;
  final void Function(int count, {bool more})? onOpenCount;
  final int? pageSize;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final ReportsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ReportsController(
      widget.adminContext,
      pageSize: widget.pageSize ?? PageRequest.defaultLimit,
    )..addListener(_tellShellWhatIsOpen);
    _controller.refresh();
  }

  void _tellShellWhatIsOpen() {
    final c = _controller;
    if (c.status != ReportStatus.open || !c.loaded || c.loading) return;
    widget.onOpenCount?.call(c.items.length, more: c.hasMore);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_tellShellWhatIsOpen)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ReportsView(controller: _controller, adminContext: widget.adminContext);
}

/// The moderation queue: open reports first, and each one worked on in a
/// sheet of its own. The [controller] belongs to the caller
/// ([ReportsScreen]), which reads the open count from it for the badge.
class ReportsView extends StatelessWidget {
  const ReportsView({
    super.key,
    required this.controller,
    required this.adminContext,
  });

  final ReportsController controller;
  final AdminContext adminContext;

  /// Opens one report and says plainly what came back from it.
  Future<void> _open(BuildContext context, AdminReport report) async {
    final outcome = await showConsoleSheet<ReportStatus>(
      context: context,
      child: _ReportSheet(
        report: report,
        controller: controller,
        adminContext: adminContext,
      ),
    );
    if (outcome == null || !context.mounted) return;
    showMessage(
      context,
      outcome == ReportStatus.resolved
          ? 'Report resolved.'
          : 'Report dismissed.',
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
          itemBuilder: (context, report) =>
              _ReportTile(report: report, onTap: () => _open(context, report)),
        );
      },
    );
  }
}

/// One report in the queue: what was filed, against whom and by whom - enough
/// to pick which one to work on. The two people are named and numbered the way
/// the account list names them (ADR-030); their note and the ways to work the
/// report are inside, in the sheet.
class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report, required this.onTap});

  final AdminReport report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: ConsoleCard(
        radius: 12,
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Row(
          children: [
            _StatusMark(status: report.status),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _category(report.category),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: HelixConsoleColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _Party(
                    name: reportSubjectName(report),
                    phone: reportSubjectPhone(report),
                    lead: null,
                    strong: true,
                  ),
                  const SizedBox(height: 4),
                  _Party(
                    name: reportReporterName(report),
                    phone: reportReporterPhone(report),
                    lead: 'by',
                    strong: false,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatTime(report.createdAt),
                    style: const TextStyle(
                      fontSize: 11,
                      color: HelixConsoleColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // The open queue needs no word on every row; the ones already
            // decided say how they ended.
            if (report.status == ReportStatus.open)
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: HelixConsoleColors.textFaint,
              )
            else
              _StatusPill(status: report.status),
          ],
        ),
      ),
    );
  }
}

/// One of the two people in a queue row: the name, and their number under it.
/// The number is left out when this server has none to show, and [lead] keeps
/// the reporter apart from the account reported about.
class _Party extends StatelessWidget {
  const _Party({
    required this.name,
    required this.phone,
    required this.lead,
    required this.strong,
  });

  final String name;
  final String? phone;
  final String? lead;
  final bool strong;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          if (lead != null)
            Text(
              '$lead ',
              style: const TextStyle(
                fontSize: 12,
                color: HelixConsoleColors.textBody,
              ),
            ),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                color: strong
                    ? HelixConsoleColors.text
                    : HelixConsoleColors.textBody,
              ),
            ),
          ),
        ],
      ),
      if (phone != null) ...[
        const SizedBox(height: 1),
        Text(
          phone!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11.5,
            fontFamily: 'monospace',
            color: HelixConsoleColors.textMuted,
          ),
        ),
      ],
    ],
  );
}

/// One report in full and the two ways to close it. It pops with the outcome
/// the operator worked it to, so the queue can say what happened.
class _ReportSheet extends StatelessWidget {
  const _ReportSheet({
    required this.report,
    required this.controller,
    required this.adminContext,
  });

  final AdminReport report;
  final ReportsController controller;
  final AdminContext adminContext;

  Future<void> _resolve(BuildContext context, ReportStatus outcome) async {
    final problem = await controller.resolve(report.reportId, outcome);
    if (!context.mounted) return;
    if (problem != null) {
      showMessage(context, problem);
      return;
    }
    Navigator.of(context).pop(outcome);
  }

  /// One of the two people behind this report, in a sheet over this one. The
  /// name is the link an operator follows to look at the person; banning or
  /// deleting there is worth a line back here, because that sheet closes and
  /// this one is what the operator is looking at.
  Future<void> _openAccount(BuildContext context, String accountId) async {
    final outcome = await showConsoleSheet<String>(
      context: context,
      child: AccountDetailView(
        adminContext: adminContext,
        accountId: accountId,
        onRemoved: (outcome) => Navigator.of(context).pop(outcome),
      ),
    );
    if (outcome == null || !context.mounted) return;
    showMessage(context, outcome);
  }

  @override
  Widget build(BuildContext context) {
    final note = report.note;
    final isOpen = report.status == ReportStatus.open;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final busy = controller.isResolving(report.reportId);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: [
            Row(
              children: [
                _StatusMark(status: report.status),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _category(report.category),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: HelixConsoleColors.text,
                    ),
                  ),
                ),
                _StatusPill(status: report.status),
              ],
            ),
            const SizedBox(height: 16),
            ConsoleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ConsoleCardLabel('What was filed'),
                  const SizedBox(height: 12),
                  _ReportParty(
                    label: 'Reported account',
                    name: reportSubjectName(report),
                    phone: reportSubjectPhone(report),
                    accountId: report.subject,
                    onTap: () => _openAccount(context, report.subject),
                  ),
                  const SizedBox(height: 8),
                  _ReportParty(
                    label: 'Filed by',
                    name: reportReporterName(report),
                    phone: reportReporterPhone(report),
                    accountId: report.reporter,
                    onTap: () => _openAccount(context, report.reporter),
                  ),
                  const SizedBox(height: 8),
                  ConsoleProperty(
                    label: 'Filed',
                    value: formatTime(report.createdAt),
                    mono: false,
                  ),
                  if (note != null && note.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const ConsoleCardLabel('Their note'),
                    const SizedBox(height: 6),
                    Text(
                      note,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: HelixConsoleColors.textBody,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isOpen) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: busy
                          ? null
                          : () => _resolve(context, ReportStatus.resolved),
                      style: ConsoleButtons.filled,
                      child: const Text('Resolve'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => _resolve(context, ReportStatus.dismissed),
                      style: ConsoleButtons.outlined,
                      child: const Text('Dismiss'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// One of the two people behind a report: their own name and number (ADR-030),
/// in a row that opens their account. The name is what an operator recognises,
/// so the whole row is the link; the id goes to the clipboard for the ticket
/// they write, and falls back to the id prefix on screen when the server joined
/// no name in.
class _ReportParty extends StatelessWidget {
  const _ReportParty({
    required this.label,
    required this.name,
    required this.phone,
    required this.accountId,
    required this.onTap,
  });

  final String label;
  final String name;
  final String? phone;
  final String accountId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ConsoleCard(
    radius: 10,
    color: HelixConsoleColors.sunken,
    padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
    onTap: onTap,
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: HelixConsoleColors.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: HelixConsoleColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.open_in_new,
                    size: 14,
                    color: HelixConsoleColors.textFaint,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                phone ?? 'No number reported',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: HelixConsoleColors.textBody,
                ),
              ),
            ],
          ),
        ),
        ConsoleCopyButton(label: '$label id', value: accountId),
      ],
    ),
  );
}

/// The status glyph in its coloured circle.
class _StatusMark extends StatelessWidget {
  const _StatusMark({required this.status});

  final ReportStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, tone) = _statusMark(status);
    return ExcludeSemantics(
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: tone.surface, shape: BoxShape.circle),
        child: Icon(icon, color: tone.text, size: 18),
      ),
    );
  }
}

/// The status in a word: `OPEN`, `RESOLVED`, `DISMISSED`.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final ReportStatus status;

  @override
  Widget build(BuildContext context) => ConsolePill(
    label: switch (status) {
      ReportStatus.open => 'Open',
      ReportStatus.resolved => 'Resolved',
      ReportStatus.dismissed => 'Dismissed',
      ReportStatus.unknown => 'Unknown',
    },
    tone: _statusMark(status).$2,
    upper: true,
  );
}

(IconData, ConsoleTone) _statusMark(ReportStatus status) => switch (status) {
  ReportStatus.open => (Icons.priority_high_rounded, ConsoleTone.warn),
  ReportStatus.resolved => (Icons.check, ConsoleTone.ok),
  ReportStatus.dismissed => (Icons.close, ConsoleTone.neutral),
  ReportStatus.unknown => (Icons.help_outline, ConsoleTone.neutral),
};

String _category(ReportCategory category) => switch (category) {
  ReportCategory.spam => 'Spam',
  ReportCategory.abuse => 'Abuse',
  ReportCategory.impersonation => 'Impersonation',
  ReportCategory.other => 'Other',
};
