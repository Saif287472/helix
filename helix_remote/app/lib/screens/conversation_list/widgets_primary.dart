part of '../conversation_list_screen.dart';

class _PreviewStyle {
  const _PreviewStyle({required this.text, this.icon, this.color});

  final String text;
  final IconData? icon;
  final Color? color;
}

// ---------------------------------------------------------------------------
// WhatsApp-style conversation tile
// ---------------------------------------------------------------------------

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.title,
    required this.onTap,
    required this.onLongPress,
    required this.unreadCount,
    required this.isSelected,
    required this.isSelectionMode,
    required this.isGroup,
    this.lastMessagePreview,
  });

  final RemoteConversation conversation;
  final String title;
  final String? lastMessagePreview;
  final int unreadCount;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isGroup;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final preview = lastMessagePreview ?? '';
    final timeStr = _formatTime(conversation.createdAt);
    final unread = unreadCount > 0;
    final previewStyle = _previewStyle(preview);
    final selectedColor = Color.alphaBlend(
      cs.primary.withAlpha(theme.brightness == Brightness.dark ? 60 : 42),
      cs.surface,
    );

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: isSelected ? selectedColor : cs.surface,
        padding: HelixInsets.fromLTRB(22, 8, 20, 8),
        constraints: const BoxConstraints(minHeight: 72),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _Avatar(
                  name: title,
                  size: 56,
                  heroTag: 'conversation_avatar_${conversation.conversationId}',
                ),
                if (isSelectionMode && isSelected)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.surface, width: 2),
                      ),
                      child: Icon(Icons.check, size: 16, color: cs.onPrimary),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            height: 1.15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeStr,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: unread ? cs.primary : cs.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: unread
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (previewStyle.icon != null) ...[
                        Icon(
                          previewStyle.icon,
                          size: 18,
                          color: previewStyle.color ?? cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 3),
                      ],
                      Expanded(
                        child: Text(
                          previewStyle.text.isNotEmpty
                              ? previewStyle.text
                              : preview.isNotEmpty
                              ? preview
                              : isGroup
                              ? 'Group conversation'
                              : 'Helix conversation',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: previewStyle.color ?? cs.onSurfaceVariant,
                            fontSize: 13,
                            height: 1.15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conversation.isMuted) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                      if (conversation.isPinned) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.push_pin, size: 15, color: cs.primary),
                      ],
                      if (unread) ...[
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          height: 22,
                          padding: HelixInsets.symmetric(horizontal: 7),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            unreadCount > 999 ? '999+' : '$unreadCount',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _PreviewStyle _previewStyle(String preview) {
    final value = preview.trim();
    final lower = value.toLowerCase();
    if (lower.contains('missed') && lower.contains('call')) {
      return const _PreviewStyle(
        text: 'Missed voice call',
        icon: Icons.call_missed,
        color: HelixColorTokens.cFFE91E63,
      );
    }
    if (lower.contains('video call')) {
      return const _PreviewStyle(text: 'Video call', icon: Icons.videocam);
    }
    if (lower.contains('voice call') || lower == 'call') {
      return const _PreviewStyle(text: 'Voice call', icon: Icons.call_made);
    }
    return _PreviewStyle(text: value);
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    if (diff == 1) return 'Yesterday';
    if (diff < 7) {
      return const [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ][dt.weekday - 1];
    }
    return '${dt.day}/${dt.month}/${dt.year % 100}';
  }
}

// ---------------------------------------------------------------------------
// Redacted outbox status banner
// ---------------------------------------------------------------------------

class _OutboxBanner extends StatelessWidget {
  const _OutboxBanner({required this.summary, required this.onRetry});

  final RemoteOutboxSummary summary;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final parts = <String>[
      '${summary.queuedCount} queued',
      if (summary.retryScheduledCount > 0)
        '${summary.retryScheduledCount} retry scheduled',
      if (summary.failedCount > 0) '${summary.failedCount} failed',
    ];

    return Material(
      color: cs.tertiaryContainer,
      child: Padding(
        padding: HelixInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.outbox_outlined, color: cs.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Outbox: ${parts.join(', ')}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onTertiaryContainer,
                ),
              ),
            ),
            if (summary.failedCount > 0)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// WhatsApp-style contact tile
// ---------------------------------------------------------------------------
