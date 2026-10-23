import 'package:flutter/material.dart';
import 'package:helix_admin/src/features/audit/audit_screen.dart';
import 'package:helix_admin/src/features/dashboard/server_controller.dart';
import 'package:helix_admin/src/features/logs/logs_screen.dart';
import 'package:helix_admin/src/features/settings/settings_screen.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';

/// What an operator does about the server itself, behind one segmented bar:
/// the audit trail, the live log and the configuration. Moderation reports are
/// a place of their own; on a phone these three are reached from the system
/// drawer, and [tab] is where the drawer sent the operator.
class OpsScreen extends StatelessWidget {
  const OpsScreen({
    super.key,
    required this.adminContext,
    required this.server,
    required this.tab,
    required this.onTabChanged,
    this.pageSize,
    this.pollInterval,
  });

  final AdminContext adminContext;
  final ServerController server;
  final OpsTab tab;
  final ValueChanged<OpsTab> onTabChanged;
  final int? pageSize;
  final Duration? pollInterval;

  Widget _body() => switch (tab) {
    OpsTab.audit => AuditScreen(adminContext: adminContext, pageSize: pageSize),
    OpsTab.logs => LogsScreen(
      adminContext: adminContext,
      pollInterval: pollInterval,
    ),
    OpsTab.config => ConfigView(server: server),
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
                  for (final t in OpsTab.values) ConsoleSegment(t.label),
                ],
                selected: tab.index,
                onSelected: (i) => onTabChanged(OpsTab.values[i]),
              ),
            ],
          ),
        ),
        Expanded(
          child: KeyedSubtree(key: ValueKey(tab), child: _body()),
        ),
      ],
    );
  }
}

/// The three things [OpsScreen] shows, in the order the bar draws them.
enum OpsTab {
  audit('Audit'),
  logs('Logs'),
  config('Config');

  const OpsTab(this.label);

  /// The word on its segment.
  final String label;
}
