import 'package:flutter/material.dart';
import 'package:helix_admin/src/features/audit/audit_screen.dart';
import 'package:helix_admin/src/features/dashboard/server_controller.dart';
import 'package:helix_admin/src/features/logs/logs_screen.dart';
import 'package:helix_admin/src/features/reports/reports_controller.dart';
import 'package:helix_admin/src/features/reports/reports_screen.dart';
import 'package:helix_admin/src/features/settings/settings_screen.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// "Operations & System": the four things an operator does about the server
/// itself, behind one segmented bar: Reports, Audit, Logs and Config.
class OpsScreen extends StatefulWidget {
  const OpsScreen({
    super.key,
    required this.adminContext,
    required this.server,
    this.pageSize,
    this.pollInterval,
  });

  final AdminContext adminContext;
  final ServerController server;
  final int? pageSize;
  final Duration? pollInterval;

  @override
  State<OpsScreen> createState() => _OpsScreenState();
}

class _OpsScreenState extends State<OpsScreen> {
  static const _reports = 0;
  static const _audit = 1;
  static const _logs = 2;

  late final ReportsController _reportsController;
  int _tab = _reports;

  /// The last count of open reports seen, kept while the Reports filter is
  /// on something else so the badge does not flicker away.
  int _openCount = 0;

  @override
  void initState() {
    super.initState();
    _reportsController = ReportsController(
      widget.adminContext,
      pageSize: widget.pageSize ?? PageRequest.defaultLimit,
    )..addListener(_onReports);
    _reportsController.refresh();
  }

  void _onReports() {
    final c = _reportsController;
    if (c.status == ReportStatus.open && c.loaded && !c.loading) {
      final count = c.items.length;
      if (count != _openCount && mounted) setState(() => _openCount = count);
    }
  }

  @override
  void dispose() {
    _reportsController
      ..removeListener(_onReports)
      ..dispose();
    super.dispose();
  }

  Widget _body() => switch (_tab) {
    _reports => ReportsView(
      controller: _reportsController,
      adminContext: widget.adminContext,
    ),
    _audit => AuditScreen(
      adminContext: widget.adminContext,
      pageSize: widget.pageSize,
    ),
    _logs => LogsScreen(
      adminContext: widget.adminContext,
      pollInterval: widget.pollInterval,
    ),
    _ => ConfigView(server: widget.server),
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ConsoleTitle('Operations & System'),
              const SizedBox(height: 12),
              ConsoleSegmented(
                segments: [
                  ConsoleSegment('Reports', badge: _openCount),
                  const ConsoleSegment('Audit'),
                  const ConsoleSegment('Logs'),
                  const ConsoleSegment('Config'),
                ],
                selected: _tab,
                onSelected: (i) => setState(() => _tab = i),
              ),
            ],
          ),
        ),
        Expanded(
          child: KeyedSubtree(key: ValueKey(_tab), child: _body()),
        ),
      ],
    );
  }
}
