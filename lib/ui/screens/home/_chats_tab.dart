part of 'home_screen.dart';

// ---------------------------------------------------------------------------
// Tab 2 — Chats list
// ---------------------------------------------------------------------------

class _ChatsTab extends ConsumerStatefulWidget {
  const _ChatsTab();

  @override
  ConsumerState<_ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends ConsumerState<_ChatsTab> {
  final _searchController = TextEditingController();
  String _query = '';

  // Archived IDs tracked locally against the DB.
  final Set<String> _archivedIds = {};
  bool _archivedExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadArchivedIds();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadArchivedIds() async {
    final db = await ref.read(databaseProvider.future);
    final archived = db.getArchivedThreads();
    if (mounted) {
      setState(() {
        _archivedIds
          ..clear()
          ..addAll(archived.map((t) => t.threadId));
      });
    }
  }

  Future<void> _setArchived(String threadId, {required bool archive}) async {
    final db = await ref.read(databaseProvider.future);
    db.archiveThread(threadId, archive: archive);
    if (mounted) {
      setState(() {
        if (archive) {
          _archivedIds.add(threadId);
        } else {
          _archivedIds.remove(threadId);
        }
      });
    }
  }

  Future<void> _confirmWipe() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Emergency wipe'),
        content: const Text(
          'This will instantly destroy all messages on this device and signal connected peers to do the same. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Wipe everything'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(messagingServiceProvider).wipeAll();
    }
  }

  bool _matches(ChatThread t) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return t.peerDisplayName.toLowerCase().contains(q) ||
        t.peerDeviceSuffix.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final threads = ref.watch(threadsProvider);
    final theme = Theme.of(context);

    final allSorted = threads.values.toList()
      ..sort((a, b) {
        final aTime = a.lastMessage?.timestamp ?? DateTime(0);
        final bTime = b.lastMessage?.timestamp ?? DateTime(0);
        return bTime.compareTo(aTime);
      });

    final active = allSorted
        .where((t) => !_archivedIds.contains(t.threadId) && _matches(t))
        .toList();
    final archived = allSorted
        .where((t) => _archivedIds.contains(t.threadId) && _matches(t))
        .toList();

    if (threads.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 48,
                color: theme.colorScheme.onSurface.withAlpha(80),
              ),
              const SizedBox(height: 12),
              Text(
                'No active chats.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(160),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Accept a connection request to start a conversation.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: SearchBar(
            controller: _searchController,
            leading: const Icon(Icons.search),
            hintText: 'Search chats',
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 16),
            ),
            trailing: [
              if (_query.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Clear',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined),
                tooltip: 'Emergency wipe',
                color: Theme.of(context).colorScheme.error,
                onPressed: _confirmWipe,
              ),
            ],
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              ...active.map(
                (t) => _ChatThreadTile(
                  thread: t,
                  isArchived: false,
                  onArchiveToggle: () =>
                      _setArchived(t.threadId, archive: true),
                ),
              ),
              if (archived.isNotEmpty) ...[
                InkWell(
                  onTap: () =>
                      setState(() => _archivedExpanded = !_archivedExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _archivedExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 18,
                          color: theme.colorScheme.onSurface.withAlpha(160),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Archived (${archived.length})',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withAlpha(160),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_archivedExpanded)
                  ...archived.map(
                    (t) => _ChatThreadTile(
                      thread: t,
                      isArchived: true,
                      onArchiveToggle: () =>
                          _setArchived(t.threadId, archive: false),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatThreadTile extends StatelessWidget {
  const _ChatThreadTile({
    required this.thread,
    required this.isArchived,
    required this.onArchiveToggle,
  });
  final ChatThread thread;
  final bool isArchived;
  final VoidCallback onArchiveToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = thread.lastMessage;
    final timeStr = last != null ? _formatTime(last.timestamp) : '';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primary.withAlpha(30),
        child: Text(
          thread.peerDisplayName.isNotEmpty
              ? thread.peerDisplayName[0].toUpperCase()
              : '?',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              thread.peerDisplayName,
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (timeStr.isNotEmpty)
            Text(timeStr, style: theme.textTheme.labelSmall),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                if (thread.draftText.isNotEmpty)
                  Text(
                    'Draft  ',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                Expanded(
                  child: Text(
                    last?.text ?? 'No messages yet.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          if (thread.unreadCount > 0)
            Badge(label: Text('${thread.unreadCount}')),
        ],
      ),
      trailing: StatusBadge(status: thread.status),
      onTap: () => Navigator.of(
        context,
      ).pushNamed('${AppRoutes.chat}/${thread.threadId}'),
      onLongPress: () => _showContextMenu(context),
    );
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
              ),
              title: Text(isArchived ? 'Unarchive' : 'Archive'),
              onTap: () {
                Navigator.pop(ctx);
                onArchiveToggle();
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day}';
  }
}
