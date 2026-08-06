part of '../conversation_list_screen.dart';

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.stateLabel, this.onRetry});

  final String stateLabel;
  final VoidCallback? onRetry;

  static bool _isError(String state) =>
      state == 'failed' || state == 'retryScheduled';

  @override
  Widget build(BuildContext context) {
    final text = bannerTextFor(stateLabel);
    if (text == null) return const SizedBox.shrink();
    final isError = _isError(stateLabel);
    return Container(
      color: isError ? Colors.red.shade100 : Colors.orange.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(
            isError ? Icons.cloud_off_outlined : Icons.info_outline,
            size: 16,
            color: isError ? Colors.red.shade700 : null,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
          if (isError && onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Retry', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  static String? bannerTextFor(String state) {
    final copy = switch (state) {
      'offline' => 'Network unavailable - messages will be sent when connected',
      'connecting' => 'Connecting...',
      'syncing' => 'Syncing...',
      'authRequired' =>
        'Sign in required - your session expired or this device was revoked',
      'retryScheduled' => 'Reconnecting after connection loss...',
      'degraded' => 'Connection degraded',
      'failed' => 'Connection failed. Check the server URL and try again',
      _ => null,
    };
    if (copy != null) return copy;
    switch (state) {
      case 'offline':
        return 'Offline — messages will be sent when connected';
      case 'connecting':
        return 'Connecting…';
      case 'syncing':
        return 'Syncing…';
      case 'authRequired':
        return 'Sign in required';
      case 'retryScheduled':
        return 'Connection lost — reconnecting…';
      case 'degraded':
        return 'Connection degraded';
      case 'failed':
        return 'Could not reach server';
      default:
        return null;
    }
  }
}

/// Connection status banner shared across screens.
class RemoteRuntimeStateBanner extends StatelessWidget {
  const RemoteRuntimeStateBanner({
    super.key,
    required this.stateLabel,
    this.onRetry,
  });

  final String stateLabel;
  final VoidCallback? onRetry;

  static String? bannerTextFor(String state) =>
      _ConnectionBanner.bannerTextFor(state);

  @override
  Widget build(BuildContext context) =>
      _ConnectionBanner(stateLabel: stateLabel, onRetry: onRetry);
}

// ---------------------------------------------------------------------------
// WhatsApp-style filter chip row (All / Unread / Groups)
// ---------------------------------------------------------------------------

class _SearchField extends StatelessWidget {
  const _SearchField({
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
    final fill = theme.brightness == Brightness.dark
        ? cs.surfaceContainerHighest.withAlpha(150)
        : cs.surfaceContainerHighest.withAlpha(120);

    return SizedBox(
      height: 56,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: theme.textTheme.titleMedium?.copyWith(
          color: cs.onSurface,
          fontSize: 18,
        ),
        decoration: InputDecoration(
          hintText: 'Search chats',
          hintStyle: theme.textTheme.titleMedium?.copyWith(
            color: cs.onSurfaceVariant,
            fontSize: 18,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant, size: 30),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Clear search',
                  onPressed: onClear,
                ),
          filled: true,
          fillColor: fill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

class _FilterChipsRow extends StatelessWidget {
  const _FilterChipsRow({
    required this.active,
    required this.unreadCount,
    required this.groupCount,
    required this.onSelect,
  });

  final _ChatFilter active;
  final int unreadCount;
  final int groupCount;
  final void Function(_ChatFilter filter) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final chips = [
      const (_ChatFilter.all, 'All'),
      (_ChatFilter.unread, unreadCount > 0 ? 'Unread $unreadCount' : 'Unread'),
      const (_ChatFilter.favorites, 'Favorites'),
      (_ChatFilter.groups, groupCount > 0 ? 'Groups $groupCount' : 'Groups'),
      const (_ChatFilter.custom, '+'),
    ];

    return Container(
      color: cs.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(30, 0, 16, 12),
        child: Row(
          children: chips.map((entry) {
            final (filter, label) = entry;
            final selected = active == filter;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onSelect(filter),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  height: 34,
                  padding: EdgeInsets.symmetric(
                    horizontal: label == '+' ? 12 : 16,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.primaryContainer
                        : cs.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected
                          ? cs.primary.withAlpha(80)
                          : cs.outlineVariant.withAlpha(190),
                    ),
                  ),
                  child: Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: selected
                          ? cs.onPrimaryContainer
                          : cs.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
