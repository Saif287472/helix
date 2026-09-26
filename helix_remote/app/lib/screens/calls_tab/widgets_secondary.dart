part of '../calls_tab_screen.dart';

class _CallInfoHistoryRow extends StatelessWidget {
  const _CallInfoHistoryRow({required this.row});

  final _CallHistoryRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final warning = row.isMissed;
    return Padding(
      padding: HelixInsets.fromLTRB(54, 13, 32, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            row.directionIcon,
            color: warning ? cs.error : cs.primary,
            size: 20,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.infoTitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _CallsTabScreenState._formatClock(row.dateTime),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (row.isMissed || row.isNotAnswered) ...[
                  const SizedBox(height: 4),
                  Text(
                    HelixLocalizations.of(context).notAnswered,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (row.durationLabel.isNotEmpty)
            Text(
              row.durationLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickContactCard extends StatelessWidget {
  const _QuickContactCard({
    required this.row,
    required this.onMessage,
    required this.onAudio,
    required this.onVideo,
    required this.onInfo,
  });

  final _CallHistoryRow row;
  final VoidCallback onMessage;
  final VoidCallback onAudio;
  final VoidCallback onVideo;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 64,
            alignment: Alignment.centerLeft,
            padding: HelixInsets.symmetric(horizontal: 16),
            color: cs.primaryContainer.withAlpha(170),
            child: Text(
              row.peerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: cs.onPrimaryContainer,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            height: 416,
            alignment: Alignment.center,
            color: cs.primaryContainer.withAlpha(120),
            child: Text(
              _initials(row.peerName),
              style: theme.textTheme.displayLarge?.copyWith(
                color: cs.primary,
                fontSize: 80,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            height: 90,
            color: cs.surface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _PopupAction(
                  icon: Icons.chat_bubble_outline,
                  label: 'Message',
                  onTap: onMessage,
                ),
                _PopupAction(
                  icon: Icons.call_outlined,
                  label: 'Audio call',
                  onTap: onAudio,
                ),
                _PopupAction(
                  icon: Icons.videocam_outlined,
                  label: 'Video call',
                  onTap: onVideo,
                ),
                _PopupAction(
                  icon: Icons.info_outline,
                  label: 'Call info',
                  onTap: onInfo,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PopupAction extends StatelessWidget {
  const _PopupAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;

  /// Required rather than optional: this widget renders an icon with no text,
  /// so without a label a screen reader announces only "button". Making it a
  /// required parameter means a new action cannot be added unlabelled.
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      icon: Icon(icon),
      iconSize: 28,
      color: Theme.of(context).colorScheme.primary,
      onPressed: onTap,
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({
    required this.name,
    required this.size,
    this.selected = false,
  });

  final String name;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: size / 2,
          backgroundColor: _avatarColor(name, cs),
          child: Text(
            _initials(name),
            style: TextStyle(
              color: cs.primary,
              fontSize: size * 0.42,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (selected)
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
    );
  }
}

class _CallSearchField extends StatelessWidget {
  const _CallSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      height: 54,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search calls',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClear,
                  tooltip: 'Clear search',
                ),
          filled: true,
          fillColor: cs.surfaceContainerHighest.withAlpha(105),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          contentPadding: HelixInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}
