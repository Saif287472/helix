import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:flutter/material.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote/l10n/helix_localizations.dart';

class ScheduledCallsScreen extends StatelessWidget {
  const ScheduledCallsScreen({
    super.key,
    required this.calls,
    required this.myAccountId,
    this.onRsvp,
    this.onCancel,
    this.onJoin,
    this.onCreateNew,
  });

  final List<ScheduledCall> calls;
  final String myAccountId;
  final void Function(String scheduledCallId, String rsvp)? onRsvp;
  final void Function(String scheduledCallId)? onCancel;
  final void Function(ScheduledCall call)? onJoin;
  final VoidCallback? onCreateNew;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(HelixLocalizations.of(context).scheduledCalls),
        actions: [
          if (onCreateNew != null)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: onCreateNew,
              tooltip: 'Schedule a call',
            ),
        ],
      ),
      body: calls.isEmpty
          ? HelixEmptyState(
              icon: Icons.event_available_outlined,
              title: 'No upcoming scheduled calls',
              message: 'Schedule a call so everyone has a clear time to join.',
              action: onCreateNew == null
                  ? null
                  : FilledButton.icon(
                      onPressed: onCreateNew,
                      icon: const Icon(Icons.add),
                      label: Text(HelixLocalizations.of(context).scheduleCall),
                    ),
            )
          : ListView.separated(
              padding: HelixInsets.all(16),
              itemCount: calls.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _ScheduledCallCard(
                call: calls[i],
                myAccountId: myAccountId,
                onRsvp: onRsvp,
                onCancel: onCancel,
                onJoin: onJoin,
              ),
            ),
    );
  }
}

class _ScheduledCallCard extends StatelessWidget {
  const _ScheduledCallCard({
    required this.call,
    required this.myAccountId,
    this.onRsvp,
    this.onCancel,
    this.onJoin,
  });

  final ScheduledCall call;
  final String myAccountId;
  final void Function(String, String)? onRsvp;
  final void Function(String)? onCancel;
  final void Function(ScheduledCall)? onJoin;

  bool get _isHost => call.hostAccountId == myAccountId;

  RsvpStatus? get _myRsvp {
    try {
      return call.attendees
          .firstWhere((a) => a.accountId == myAccountId)
          .rsvpStatus;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheduledAt = call.scheduledAt;
    final now = DateTime.now();
    final diff = scheduledAt.difference(now);
    final isImminent = diff.inMinutes <= 15 && diff.isNegative == false;
    final isStartable = diff.inMinutes <= 5 && diff.isNegative == false;
    final hasRoom = call.roomId != null;

    final timeLabel = _formatScheduledTime(scheduledAt);
    final myRsvp = _myRsvp;

    return Card(
      margin: HelixInsets.zero,
      child: Padding(
        padding: HelixInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    call.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isImminent)
                  Container(
                    padding: HelixInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: HelixStatusColors.caution.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      HelixLocalizations.of(context).startingSoon,
                      style: const TextStyle(
                        fontSize: 11,
                        color: HelixStatusColors.caution,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.schedule,
                  size: 14,
                  color: HelixStatusColors.neutral,
                ),
                const SizedBox(width: 4),
                Text(
                  timeLabel,
                  style: const TextStyle(
                    color: HelixStatusColors.neutral,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(
                  Icons.people,
                  size: 14,
                  color: HelixStatusColors.neutral,
                ),
                const SizedBox(width: 4),
                Text(
                  '${call.attendees.length} attendee${call.attendees.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: HelixStatusColors.neutral,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            // Attendee RSVP chips
            if (call.attendees.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: call.attendees.map((a) {
                  final color = switch (a.rsvpStatus) {
                    RsvpStatus.yes => HelixStatusColors.positive,
                    RsvpStatus.no => HelixStatusColors.danger,
                    RsvpStatus.pending => HelixStatusColors.neutral,
                  };
                  return Chip(
                    label: Text(
                      a.accountId,
                      style: const TextStyle(fontSize: 11),
                    ),
                    avatar: Icon(
                      switch (a.rsvpStatus) {
                        RsvpStatus.yes => Icons.check,
                        RsvpStatus.no => Icons.close,
                        RsvpStatus.pending => Icons.schedule,
                      },
                      size: 14,
                      color: color,
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: HelixInsets.zero,
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 12),
            // Action row
            Row(
              children: [
                // RSVP buttons (non-host attendees)
                if (!_isHost && myRsvp != RsvpStatus.yes && onRsvp != null)
                  TextButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: Text(HelixLocalizations.of(context).accept),
                    onPressed: () => onRsvp!(call.scheduledCallId, 'YES'),
                  ),
                if (!_isHost && myRsvp != RsvpStatus.no && onRsvp != null)
                  TextButton.icon(
                    icon: const Icon(Icons.close, size: 16),
                    label: Text(HelixLocalizations.of(context).decline),
                    style: TextButton.styleFrom(
                      foregroundColor: HelixStatusColors.danger,
                    ),
                    onPressed: () => onRsvp!(call.scheduledCallId, 'NO'),
                  ),
                const Spacer(),
                // Host cancel
                if (_isHost && onCancel != null)
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: HelixStatusColors.danger,
                    ),
                    onPressed: () => _confirmCancel(context),
                    child: Text(HelixLocalizations.of(context).cancel),
                  ),
                // Join button (room already live, or time is now)
                if ((hasRoom || isStartable) && onJoin != null)
                  FilledButton.icon(
                    icon: const Icon(Icons.video_call, size: 16),
                    label: Text(HelixLocalizations.of(context).join),
                    onPressed: () => onJoin!(call),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmCancel(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(HelixLocalizations.of(context).cancelScheduledCall),
        content: Text(HelixLocalizations.of(context).allAttendeesWillNotified),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(HelixLocalizations.of(context).keep),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: HelixStatusColors.danger,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              onCancel!(call.scheduledCallId);
            },
            child: Text(HelixLocalizations.of(context).cancelCall),
          ),
        ],
      ),
    );
  }

  static String _formatScheduledTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final callDay = DateTime(dt.year, dt.month, dt.day);
    final diff = callDay.difference(today).inDays;

    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return switch (diff) {
      0 => 'Today $time',
      1 => 'Tomorrow $time',
      _ => '${dt.day}/${dt.month} $time',
    };
  }
}
