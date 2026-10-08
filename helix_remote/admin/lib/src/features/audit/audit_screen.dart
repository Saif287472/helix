import 'package:flutter/material.dart';
import 'package:helix_admin/src/features/audit/audit_controller.dart';
import 'package:helix_admin/src/features/common/format.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
import 'package:helix_admin/src/widgets/paged_list.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// What the audit trail's chips filter by. The server records an action code
/// (`account.suspend`, `admin.sign_in`, `config.update`); the console groups
/// the codes it knows into three kinds and shows the rest as system events.
enum _AuditKind {
  access('Access', ConsoleTone.ok),
  moderation('Moderation', ConsoleTone.warn),
  system('System', ConsoleTone.info);

  const _AuditKind(this.label, this.tone);

  final String label;
  final ConsoleTone tone;

  static _AuditKind of(String action) {
    final a = action.toLowerCase();
    if (a.startsWith('admin.') ||
        a.contains('invite') ||
        a.contains('recovery')) {
      return access;
    }
    if (a.startsWith('account.') ||
        a.startsWith('report') ||
        a.startsWith('device')) {
      return moderation;
    }
    return system;
  }
}

/// The administrative audit trail, newest first. Every action in this
/// console writes a row; codes, tokens and passwords are never in it.
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key, required this.adminContext, this.pageSize});

  final AdminContext adminContext;
  final int? pageSize;

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  late final AuditController _audit;
  _AuditKind? _kind;

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
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _audit,
      builder: (context, _) {
        final items = _audit.items;
        final shown = _kind == null
            ? items
            : [
                for (final e in items)
                  if (_AuditKind.of(e.action) == _kind) e,
              ];
        return PagedListView<AuditEntry>(
          controller: _audit,
          shown: shown,
          emptyIcon: Icons.verified_user_outlined,
          emptyTitle: items.isEmpty || _kind == null
              ? 'No audit events recorded yet'
              : 'No ${_kind!.label.toLowerCase()} events loaded',
          emptyMessage: items.isEmpty || _kind == null
              ? 'Administrative actions taken on this server will appear '
                    'here. Routine reads are not recorded.'
              : 'Try another filter, or load more events.',
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ConsoleHeading(
                'Administrative Audit Trail',
                subtitle:
                    'Security events, access changes and operator actions '
                    'recorded by the server.',
              ),
              const SizedBox(height: 14),
              ConsoleChipRow(
                children: [
                  ConsoleChip(
                    label: 'All events (${items.length})',
                    selected: _kind == null,
                    onTap: () => setState(() => _kind = null),
                  ),
                  for (final kind in _AuditKind.values)
                    ConsoleChip(
                      label: kind.label,
                      selected: _kind == kind,
                      onTap: () => setState(() => _kind = kind),
                    ),
                ],
              ),
            ],
          ),
          itemBuilder: (context, entry) => _AuditCard(entry: entry),
        );
      },
    );
  }
}

class _AuditCard extends StatelessWidget {
  const _AuditCard({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final kind = _AuditKind.of(entry.action);
    final details = [
      for (final e in entry.details.entries) '${e.key}: ${e.value}',
    ];
    return ConsoleCard(
      radius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.action,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: HelixConsoleColors.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConsolePill(label: kind.label, tone: kind.tone, upper: true),
            ],
          ),
          if (entry.target != null || details.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (entry.target != null) 'Target ${shortId(entry.target!)}',
                ...details,
              ].join(' · '),
              style: const TextStyle(
                fontSize: 13,
                color: HelixConsoleColors.textBody,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.access_time,
                size: 13,
                color: HelixConsoleColors.textFaint,
              ),
              const SizedBox(width: 4),
              Text(
                formatTime(entry.at),
                style: const TextStyle(
                  fontSize: 11,
                  color: HelixConsoleColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
