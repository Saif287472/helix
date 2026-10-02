import 'package:flutter/material.dart';
import 'package:helix_admin/src/features/audit/audit_controller.dart';
import 'package:helix_admin/src/features/common/format.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/widgets/paged_list.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key, required this.adminContext, this.pageSize});

  final AdminContext adminContext;
  final int? pageSize;

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  late final AuditController _audit;

  @override
  void initState() {
    super.initState();
    _audit = AuditController(
      widget.adminContext,
      pageSize: widget.pageSize ?? PageRequest.defaultLimit,
    )..refresh();
  }

  @override
  void dispose() {
    _audit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PagedListView<AuditEntry>(
    controller: _audit,
    emptyIcon: Icons.history,
    emptyTitle: 'Nothing recorded yet',
    emptyMessage: 'Actions taken in this console appear here.',
    itemBuilder: (context, entry) => _AuditTile(entry: entry),
  );
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final details = [
      for (final e in entry.details.entries) '${e.key}: ${e.value}',
    ];
    return ListTile(
      title: Text(entry.action),
      subtitle: Text(
        [
          formatTime(entry.at),
          if (entry.target != null) 'target ${shortId(entry.target!)}',
          ...details,
        ].join(' · '),
      ),
      isThreeLine: details.isNotEmpty,
      contentPadding: const EdgeInsets.symmetric(horizontal: HelixSpace.md),
    );
  }
}
