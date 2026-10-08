import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/calls/application/call_copy.dart';
import 'package:helix_remote/features/calls/application/call_log.dart';
import 'package:helix_remote/shared/navigation/people_paths.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// One person's calls: who it was and every call with them, newest first,
/// with buttons to call again. Opened from a Calls row and from a
/// `helix://call/…` link.
class CallDetailScreen extends ConsumerWidget {
  const CallDetailScreen({super.key, required this.callId});

  final String callId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(callDetailProvider(callId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call details'),
        actions: [
          if (detail.value != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete from call history',
              onPressed: () => _deleteAll(context, ref, detail.value!),
            ),
        ],
      ),
      body: switch (detail) {
        AsyncError() => HelixErrorState(
          message: 'This call could not be loaded.',
          onRetry: () => ref.invalidate(callDetailProvider(callId)),
        ),
        AsyncData(:final value) when value == null => const HelixEmptyState(
          icon: Icons.call_outlined,
          title: 'Call not found',
          message: 'This call is no longer in your call history.',
        ),
        AsyncData(:final value) => _Body(detail: value!),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Future<void> _deleteAll(
    BuildContext context,
    WidgetRef ref,
    CallDetail detail,
  ) async {
    final sure = await showHelixDestructiveDialog(
      context,
      title: 'Delete from call history?',
      message:
          'All ${detail.rows.length} calls with ${detail.title} will be '
          'removed from your call history.',
      action: 'Delete',
    );
    if (!sure) return;
    await ref.read(callLogActionsProvider).delete([
      for (final row in detail.rows) row.callId,
    ]);
    if (context.mounted) Navigator.of(context).maybePop();
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.detail});

  final CallDetail detail;

  Future<void> _call(
    BuildContext context,
    WidgetRef ref, {
    required bool video,
  }) async {
    final outcome = await ref
        .read(callLogActionsProvider)
        .callBack(detail.peer, video: video);
    if (!context.mounted || outcome.started) return;
    showHelixSnackBar(
      context,
      outcome.message ?? 'The call could not be placed.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(HelixSpace.lg),
          child: Column(
            children: [
              HelixAvatar(
                model: detail.avatar,
                size: HelixAvatarSize.xl,
                semanticLabel: 'Picture of ${detail.title}',
              ),
              const SizedBox(height: HelixSpace.md),
              Semantics(
                header: true,
                child: Text(
                  detail.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (detail.subtitle != null)
                Text(
                  detail.subtitle!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: HelixSpace.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _DetailAction(
                    icon: Icons.call_outlined,
                    label: 'Voice call',
                    onTap: () => _call(context, ref, video: false),
                  ),
                  _DetailAction(
                    icon: Icons.videocam_outlined,
                    label: 'Video call',
                    onTap: () => _call(context, ref, video: true),
                  ),
                  _DetailAction(
                    icon: Icons.person_outline,
                    label: 'Contact',
                    onTap: () => context.push(PeoplePaths.person(detail.peer)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const HelixSectionHeader(title: 'Calls'),
        for (final row in detail.rows) _CallRow(row: row),
      ],
    );
  }
}

/// One round action under the name: an icon in a tinted circle and its label.
class _DetailAction extends StatelessWidget {
  const _DetailAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HelixSpace.sm),
      child: Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(32),
          onTap: onTap,
          child: SizedBox(
            width: 84,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(height: HelixSpace.xs),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallRow extends StatelessWidget {
  const _CallRow({required this.row});

  final CallDetailRow row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bad =
        row.direction == CallLogDirection.missed ||
        row.direction == CallLogDirection.failed;
    final icon = switch (row.direction) {
      CallLogDirection.incoming => Icons.call_received,
      CallLogDirection.outgoing => Icons.call_made,
      CallLogDirection.missed => Icons.call_missed,
      CallLogDirection.declined => Icons.call_end,
      CallLogDirection.failed => Icons.error_outline,
      CallLogDirection.cancelled => Icons.call_made,
      CallLogDirection.noAnswer => Icons.call_made,
    };
    final kind = row.video ? 'video call' : 'voice call';
    final trailing = row.durationLabel;
    return Semantics(
      container: true,
      label:
          '${row.directionLabel} $kind, ${row.timeLabel}'
          '${row.spokenDuration == null ? '' : ', ${row.spokenDuration}'}',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: HelixSpace.md,
              vertical: HelixSpace.xs,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: bad ? scheme.error : HelixStatusColors.positive,
                ),
                const SizedBox(width: HelixSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row.directionLabel} $kind',
                        style: TextStyle(
                          fontSize: 16,
                          color: bad ? scheme.error : scheme.onSurface,
                        ),
                      ),
                      Text(
                        row.timeLabel,
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing,
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
