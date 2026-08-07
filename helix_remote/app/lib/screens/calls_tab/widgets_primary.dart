part of '../calls_tab_screen.dart';

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.contacts,
    required this.recentRows,
    required this.onNewCall,
    required this.onSchedule,
    required this.onKeypad,
    required this.onFavorites,
    required this.onContactShortcut,
  });

  final List<RemoteContact> contacts;
  final List<_CallHistoryRow> recentRows;
  final VoidCallback onNewCall;
  final VoidCallback onSchedule;
  final VoidCallback onKeypad;
  final VoidCallback onFavorites;
  final void Function(String peerId, String name) onContactShortcut;

  @override
  Widget build(BuildContext context) {
    final shortcuts = _shortcuts();
    return SizedBox(
      height: 128,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: HelixInsets.fromLTRB(46, 16, 24, 0),
        children: [
          _QuickActionBubble(
            icon: Icons.call_outlined,
            label: 'Call',
            onTap: onNewCall,
          ),
          _QuickActionBubble(
            icon: Icons.calendar_month_outlined,
            label: 'Schedule',
            onTap: onSchedule,
          ),
          _QuickActionBubble(
            icon: Icons.dialpad,
            label: 'Keypad',
            onTap: onKeypad,
          ),
          if (shortcuts.isNotEmpty)
            _QuickActionBubble(
              icon: Icons.person,
              label: _shortLabel(shortcuts.first.$2),
              onTap: () =>
                  onContactShortcut(shortcuts.first.$1, shortcuts.first.$2),
            ),
          _QuickActionBubble(
            icon: Icons.favorite_border,
            label: 'Favorites',
            onTap: onFavorites,
          ),
        ],
      ),
    );
  }

  List<(String, String)> _shortcuts() {
    final byPeer = <String, String>{};
    for (final row in recentRows) {
      byPeer.putIfAbsent(row.peerId, () => row.peerName);
    }
    for (final contact in contacts) {
      byPeer.putIfAbsent(
        contact.peerAccountId,
        () =>
            contact.nickname.isEmpty ? contact.peerAccountId : contact.nickname,
      );
    }
    return byPeer.entries.map((e) => (e.key, e.value)).take(2).toList();
  }

  String _shortLabel(String value) {
    final parts = value.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? 'Contact' : parts.first;
  }
}

class _QuickActionBubble extends StatelessWidget {
  const _QuickActionBubble({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: HelixInsets.only(right: 32),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withAlpha(
                  theme.brightness == Brightness.dark ? 120 : 95,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: cs.onSurface, size: 26),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 72,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallHistoryTile extends StatelessWidget {
  const _CallHistoryTile({
    required this.row,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onAvatarTap,
    required this.onQuickCall,
  });

  final _CallHistoryRow row;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onAvatarTap;
  final VoidCallback onQuickCall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final warning = row.isMissed;
    final selectedColor = Color.alphaBlend(
      cs.primary.withAlpha(theme.brightness == Brightness.dark ? 60 : 42),
      cs.surface,
    );
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: const BoxConstraints(minHeight: 86),
        color: isSelected ? selectedColor : cs.surface,
        padding: HelixInsets.fromLTRB(30, 9, 30, 9),
        child: Row(
          children: [
            GestureDetector(
              onTap: onAvatarTap,
              child: _InitialAvatar(
                name: row.peerName,
                size: 56,
                selected: isSelectionMode && isSelected,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    row.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: warning ? cs.error : cs.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Icon(
                        row.directionIcon,
                        size: 18,
                        color: warning ? cs.error : cs.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          row.timeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 14,
                            height: 1.08,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: Icon(
                row.isVideo ? Icons.videocam_outlined : Icons.call_outlined,
              ),
              iconSize: 24,
              color: cs.onSurface,
              tooltip: row.isVideo ? 'Video call' : 'Audio call',
              onPressed: onQuickCall,
            ),
          ],
        ),
      ),
    );
  }
}

class _CallInfoScreen extends StatelessWidget {
  const _CallInfoScreen({
    required this.row,
    required this.relatedRows,
    required this.onMessage,
    required this.onAudio,
    required this.onVideo,
  });

  final _CallHistoryRow row;
  final List<_CallHistoryRow> relatedRows;
  final VoidCallback onMessage;
  final VoidCallback onAudio;
  final VoidCallback onVideo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Call info',
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 20,
            color: cs.onSurface,
            fontWeight: FontWeight.w400,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clear', child: Text('Clear this log')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: HelixInsets.only(bottom: 28),
        children: [
          const SizedBox(height: 22),
          Center(child: _InitialAvatar(name: row.peerName, size: 80)),
          const SizedBox(height: 20),
          Text(
            row.peerName,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: cs.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: HelixInsets.symmetric(horizontal: 32),
            child: Text(
              row.identifier,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(height: 34),
          Padding(
            padding: HelixInsets.symmetric(horizontal: 32),
            child: Row(
              children: [
                Expanded(
                  child: _CallInfoAction(
                    icon: Icons.chat_bubble_outline,
                    label: 'Message',
                    onTap: onMessage,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _CallInfoAction(
                    icon: Icons.call_outlined,
                    label: 'Audio',
                    onTap: onAudio,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _CallInfoAction(
                    icon: Icons.videocam_outlined,
                    label: 'Video',
                    onTap: onVideo,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 56),
          Divider(height: 1, color: cs.outlineVariant.withAlpha(90)),
          const SizedBox(height: 34),
          Padding(
            padding: HelixInsets.symmetric(horizontal: 30),
            child: Text(
              _sectionLabel(row.dateTime),
              style: theme.textTheme.titleLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(height: 22),
          ...relatedRows.map((entry) => _CallInfoHistoryRow(row: entry)),
        ],
      ),
    );
  }

  static String _sectionLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${_CallsTabScreenState._monthName(dt.month)} ${dt.day}';
  }
}

class _CallInfoAction extends StatelessWidget {
  const _CallInfoAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        height: 112,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: cs.primary, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
