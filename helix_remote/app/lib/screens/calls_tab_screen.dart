import 'package:helix_remote/services/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_attachment_service.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/screens/conversation_screen.dart';
import 'package:helix_remote/screens/scheduled_calls_screen.dart';
import 'package:helix_remote_domain/models.dart'
    show RemoteContact, ScheduledCall;
import 'package:helix_remote_calls/helix_remote_calls.dart';
import 'package:helix_remote_groups/helix_remote_groups.dart';

class CallsTabScreen extends StatefulWidget {
  const CallsTabScreen({
    super.key,
    required this.root,
    required this.messagingService,
  });

  final RemoteCompositionRoot root;
  final RemoteMessagingService messagingService;

  @override
  State<CallsTabScreen> createState() => _CallsTabScreenState();
}

class _CallsTabScreenState extends State<CallsTabScreen> {
  final _searchController = TextEditingController();
  final Set<String> _selectedCallIds = {};
  List<_CallHistoryRow> _history = [];
  bool _loaded = false;
  bool _showSearch = false;
  String _query = '';

  bool get _selectionMode => _selectedCallIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _load() {
    try {
      final history = widget.root.callService.getCallHistory(limit: 100);
      final rawRows = history.map(_rowFromHistory).toList(growable: false);
      final counts = <String, int>{};
      for (final row in rawRows) {
        counts[row.peerId] = (counts[row.peerId] ?? 0) + 1;
      }
      final rows = rawRows
          .map((row) => row.copyWith(repeatCount: counts[row.peerId] ?? 1))
          .toList(growable: false);
      if (mounted) {
        setState(() {
          _history = rows;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  _CallHistoryRow _rowFromHistory(Map<String, dynamic> entry) {
    final peerId =
        entry['peer_account_id'] as String? ??
        entry['peer_id'] as String? ??
        'unknown';
    final timestamp = entry['timestamp'] as int? ?? 0;
    final duration = entry['duration'] as int? ?? 0;
    final isVideo = (entry['is_video'] as int? ?? 0) != 0;
    return _CallHistoryRow(
      callId: entry['call_id'] as String? ?? '$peerId-$timestamp',
      peerId: peerId,
      peerName: _peerName(peerId),
      identifier: _peerIdentifier(peerId),
      direction: entry['direction'] as String? ?? kCallDirectionIncoming,
      outcome: entry['outcome'] as String? ?? '',
      isVideo: isVideo,
      timestamp: timestamp,
      dateTime: DateTime.fromMillisecondsSinceEpoch(timestamp),
      timeLabel: _formatListTime(timestamp),
      durationSeconds: duration,
      durationLabel: _formatDuration(duration),
      mediaLabel: _estimatedMediaLabel(duration, isVideo: isVideo),
    );
  }

  String _peerName(String peerId) {
    try {
      final convId = widget.messagingService.conversationIdForPeer(peerId);
      if (convId != null) {
        final name = widget.messagingService.peerDisplayName(convId);
        if (name != null && name.isNotEmpty) return name;
      }
    } catch (e) {
      // Falls through to the contact-list lookup below, so the UI still
      // resolves a name where it can.
      AppLogger.instance.warn('calls_tab', 'peer name lookup failed: \$e');
    }
    for (final contact in widget.messagingService.acceptedContacts()) {
      if (contact.peerAccountId == peerId && contact.nickname.isNotEmpty) {
        return contact.nickname;
      }
    }
    return peerId;
  }

  String _peerIdentifier(String peerId) {
    try {
      final contact = widget.messagingService.acceptedContacts().firstWhere(
        (c) => c.peerAccountId == peerId,
      );
      if (contact.nickname.isNotEmpty) return contact.peerAccountId;
    } catch (_) {}
    return peerId;
  }

  List<_CallHistoryRow> get _filteredHistory {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _history;
    return _history
        .where(
          (row) =>
              row.peerName.toLowerCase().contains(q) ||
              row.peerId.toLowerCase().contains(q) ||
              row.directionLabel.toLowerCase().contains(q) ||
              row.timeLabel.toLowerCase().contains(q),
        )
        .toList(growable: false);
  }

  void _toggleSelection(_CallHistoryRow row) {
    setState(() {
      if (!_selectedCallIds.remove(row.callId)) {
        _selectedCallIds.add(row.callId);
      }
    });
  }

  void _clearSelection() => setState(_selectedCallIds.clear);

  void _selectAllVisible() {
    setState(() {
      _selectedCallIds
        ..clear()
        ..addAll(_filteredHistory.map((row) => row.callId));
    });
  }

  void _deleteSelected() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Deleting selected calls is not available yet'),
      ),
    );
  }

  void _favoriteSelected() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _selectedCallIds.length == 1
              ? 'Favorite shortcut is ready for this contact'
              : 'Favorite shortcuts are ready for selected contacts',
        ),
      ),
    );
  }

  Future<void> _clearCallLog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear call log'),
        content: const Text('Clear all recent calls from this device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      widget.root.callService.clearCallHistory();
    } catch (_) {}
    _clearSelection();
    _load();
  }

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
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Exit selection',
                onPressed: _clearSelection,
              )
            : null,
        title: Text(
          _selectionMode ? '${_selectedCallIds.length}' : 'Calls',
          style: theme.textTheme.titleLarge?.copyWith(
            color: cs.onSurface,
            fontSize: 20,
            fontWeight: _selectionMode ? FontWeight.w400 : FontWeight.w500,
            height: 1,
          ),
        ),
        actions: _selectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: _deleteSelected,
                ),
                IconButton(
                  icon: const Icon(Icons.favorite_border),
                  tooltip: 'Favorite',
                  onPressed: _favoriteSelected,
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'select_all') _selectAllVisible();
                    if (value == 'clear_selection') _clearSelection();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'select_all',
                      child: Text('Select all'),
                    ),
                    PopupMenuItem(
                      value: 'clear_selection',
                      child: Text('Clear selection'),
                    ),
                  ],
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Search calls',
                  onPressed: () => setState(() => _showSearch = !_showSearch),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    switch (value) {
                      case 'clear':
                        _clearCallLog();
                      case 'scheduled':
                        _openScheduledCalls();
                      case 'settings':
                        _showPlaceholder(
                          'Call settings are available from Settings',
                        );
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'clear',
                      child: Text('Clear call log'),
                    ),
                    PopupMenuItem(
                      value: 'scheduled',
                      child: Text('Scheduled calls'),
                    ),
                    PopupMenuItem(value: 'settings', child: Text('Settings')),
                  ],
                ),
              ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_showSearch)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 2, 24, 12),
                    child: _CallSearchField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                      onClear: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
                  ),
                _QuickActions(
                  contacts: widget.messagingService.acceptedContacts(),
                  recentRows: _history,
                  onNewCall: () => _showNewCallPicker(context),
                  onSchedule: _openScheduledCalls,
                  onKeypad: () =>
                      _showPlaceholder('Keypad is not available yet'),
                  onFavorites: () => _showPlaceholder(
                    'Favorite calls are ready for Helix shortcuts',
                  ),
                  onContactShortcut: (peerId, name) =>
                      _callBack(peerId, isVideo: false, peerDisplayName: name),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 22, 32, 14),
                  child: Text(
                    'Recent',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: cs.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
                Expanded(child: _buildHistory(theme, cs)),
              ],
            ),
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'new_call_fab',
        onPressed: () => _showNewCallPicker(context),
        tooltip: 'New call',
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: const Icon(Icons.add_call),
      ),
    );
  }

  Widget _buildHistory(ThemeData theme, ColorScheme cs) {
    final visible = _filteredHistory;
    if (visible.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async => _load(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 56),
          children: [
            Icon(Icons.call_outlined, size: 64, color: cs.outline),
            const SizedBox(height: 16),
            Text(
              _history.isEmpty ? 'No calls yet' : 'No matching calls',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _history.isEmpty
                  ? 'Start your first call from Helix contacts.'
                  : 'Try a different search.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _load(),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 112),
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final row = visible[index];
          final selected = _selectedCallIds.contains(row.callId);
          return _CallHistoryTile(
            row: row,
            isSelected: selected,
            isSelectionMode: _selectionMode,
            onTap: () {
              if (_selectionMode) {
                _toggleSelection(row);
              } else {
                _openCallInfo(row);
              }
            },
            onLongPress: () => _toggleSelection(row),
            onAvatarTap: () => _showQuickContactPopup(row),
            onQuickCall: () => _callBack(
              row.peerId,
              isVideo: row.isVideo,
              peerDisplayName: row.peerName,
            ),
          );
        },
      ),
    );
  }

  Future<void> _callBack(
    String peerId, {
    bool isVideo = false,
    String? peerDisplayName,
  }) async {
    try {
      // Awaited on purpose. `startOutgoingCall` is async and rethrows after
      // it has cleaned up, so without the await its error bypassed this
      // catch entirely and surfaced as an uncaught zone error seconds after
      // the UI had already given up - which is how a plain "TURN is not
      // configured" 503 ended up in the logs as a crash report.
      await widget.root.callService.startOutgoingCall(
        peerId: peerId,
        isVideo: isVideo,
        peerDisplayName: peerDisplayName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Call failed: $e')));
      }
    }
  }

  void _messagePeer(_CallHistoryRow row) {
    final conversationId = widget.messagingService.conversationIdForPeer(
      row.peerId,
    );
    if (conversationId == null) {
      _showPlaceholder('No Helix chat exists for this contact yet');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
          conversationId: conversationId,
          messagingService: widget.messagingService,
          attachmentService: _tryAttachmentService(),
          groupService: _tryGroupService(),
          callsAvailable: _tryCallsAvailable(),
          onStartAudioCall: () => _callBack(
            row.peerId,
            isVideo: false,
            peerDisplayName: row.peerName,
          ),
          onStartVideoCall: () => _callBack(
            row.peerId,
            isVideo: true,
            peerDisplayName: row.peerName,
          ),
        ),
      ),
    );
  }

  RemoteAttachmentService? _tryAttachmentService() {
    try {
      return widget.root.attachmentService;
    } catch (_) {
      return null;
    }
  }

  RemoteGroupService? _tryGroupService() {
    try {
      return widget.root.groupService;
    } catch (_) {
      return null;
    }
  }

  bool _tryCallsAvailable() {
    try {
      return widget.root.callsAvailable;
    } catch (_) {
      return false;
    }
  }

  void _openCallInfo(_CallHistoryRow row) {
    final related = _history
        .where((entry) => entry.peerId == row.peerId)
        .toList(growable: false);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CallInfoScreen(
          row: row,
          relatedRows: related,
          onMessage: () => _messagePeer(row),
          onAudio: () => _callBack(
            row.peerId,
            isVideo: false,
            peerDisplayName: row.peerName,
          ),
          onVideo: () => _callBack(
            row.peerId,
            isVideo: true,
            peerDisplayName: row.peerName,
          ),
        ),
      ),
    );
  }

  void _showQuickContactPopup(_CallHistoryRow row) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(120),
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 60),
        alignment: Alignment.center,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: _QuickContactCard(
          row: row,
          onMessage: () {
            Navigator.of(ctx).pop();
            _messagePeer(row);
          },
          onAudio: () {
            Navigator.of(ctx).pop();
            _callBack(
              row.peerId,
              isVideo: false,
              peerDisplayName: row.peerName,
            );
          },
          onVideo: () {
            Navigator.of(ctx).pop();
            _callBack(row.peerId, isVideo: true, peerDisplayName: row.peerName);
          },
          onInfo: () {
            Navigator.of(ctx).pop();
            _openCallInfo(row);
          },
        ),
      ),
    );
  }

  void _showNewCallPicker(BuildContext context) {
    final contacts = widget.messagingService.acceptedContacts();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _NewCallSheet(
        contacts: contacts,
        onCall: (peerId, {required isVideo, peerDisplayName}) {
          Navigator.of(ctx).pop();
          _callBack(peerId, isVideo: isVideo, peerDisplayName: peerDisplayName);
        },
      ),
    );
  }

  void _openScheduledCalls() {
    final calls = _upcomingScheduledCalls();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScheduledCallsScreen(
          calls: calls,
          myAccountId: widget.messagingService.currentAccountId ?? '',
          onCreateNew: () =>
              _showPlaceholder('Scheduling UI is not available yet'),
          onJoin: (_) =>
              _showPlaceholder('Scheduled call join is not available yet'),
        ),
      ),
    );
  }

  List<ScheduledCall> _upcomingScheduledCalls() {
    try {
      return widget.root.callService.db.getUpcomingScheduledCalls();
    } catch (_) {
      return const [];
    }
  }

  void _showPlaceholder(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _formatDuration(int seconds) {
    if (seconds <= 0) return '';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  static String _formatListTime(int timestampMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    final time = _formatClock(dt);
    if (diff == 0) return time;
    if (diff == 1) return 'Yesterday, $time';
    if (diff < 7) {
      final weekday = const [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ][dt.weekday - 1];
      return '$weekday, $time';
    }
    return '${_monthName(dt.month)} ${dt.day}, $time';
  }

  static String _formatClock(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  static String _estimatedMediaLabel(int seconds, {required bool isVideo}) {
    if (seconds <= 0) return '';
    final bytes = seconds * (isVideo ? 220 * 1024 : 32 * 1024);
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).round()} kB';
  }

  static String _monthName(int month) => const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][month - 1];
}

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
        padding: const EdgeInsets.fromLTRB(46, 16, 24, 0),
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
      padding: const EdgeInsets.only(right: 32),
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
        padding: const EdgeInsets.fromLTRB(30, 9, 30, 9),
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
        padding: const EdgeInsets.only(bottom: 28),
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
            padding: const EdgeInsets.symmetric(horizontal: 32),
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
            padding: const EdgeInsets.symmetric(horizontal: 32),
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
            padding: const EdgeInsets.symmetric(horizontal: 30),
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

class _CallInfoHistoryRow extends StatelessWidget {
  const _CallInfoHistoryRow({required this.row});

  final _CallHistoryRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final warning = row.isMissed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(54, 13, 32, 24),
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
                    'Not answered',
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
          if (row.durationLabel.isNotEmpty || row.mediaLabel.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (row.durationLabel.isNotEmpty)
                  Text(
                    row.durationLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                if (row.mediaLabel.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      row.mediaLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: cs.primaryContainer.withAlpha(
              theme.brightness == Brightness.dark ? 120 : 170,
            ),
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
            color: cs.primaryContainer.withAlpha(
              theme.brightness == Brightness.dark ? 80 : 120,
            ),
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
                _PopupAction(icon: Icons.chat_bubble_outline, onTap: onMessage),
                _PopupAction(icon: Icons.call_outlined, onTap: onAudio),
                _PopupAction(icon: Icons.videocam_outlined, onTap: onVideo),
                _PopupAction(icon: Icons.info_outline, onTap: onInfo),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PopupAction extends StatelessWidget {
  const _PopupAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
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
              : IconButton(icon: const Icon(Icons.close), onPressed: onClear),
          filled: true,
          fillColor: cs.surfaceContainerHighest.withAlpha(
            theme.brightness == Brightness.dark ? 130 : 105,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

class _NewCallSheet extends StatefulWidget {
  const _NewCallSheet({required this.contacts, required this.onCall});

  final List<RemoteContact> contacts;
  final void Function(
    String peerId, {
    required bool isVideo,
    String? peerDisplayName,
  })
  onCall;

  @override
  State<_NewCallSheet> createState() => _NewCallSheetState();
}

class _NewCallSheetState extends State<_NewCallSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final filtered = _query.isEmpty
        ? widget.contacts
        : widget.contacts.where((c) {
            final nick = c.nickname.toLowerCase();
            final id = c.peerAccountId.toLowerCase();
            return nick.contains(_query) || id.contains(_query);
          }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'New call',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search contacts',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
                onChanged: (v) => setState(() => _query = v.toLowerCase()),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        widget.contacts.isEmpty
                            ? 'No contacts yet.\nAdd contacts from the Contacts tab.'
                            : 'No contacts match "$_query"',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.outline,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final contact = filtered[i];
                        final name = contact.nickname.isNotEmpty
                            ? contact.nickname
                            : contact.peerAccountId;
                        return ListTile(
                          leading: _InitialAvatar(name: name, size: 44),
                          title: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: contact.nickname.isNotEmpty
                              ? Text(
                                  contact.peerAccountId,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.videocam_outlined),
                            tooltip: 'Video call',
                            onPressed: () => widget.onCall(
                              contact.peerAccountId,
                              isVideo: true,
                              peerDisplayName: name,
                            ),
                          ),
                          onTap: () => widget.onCall(
                            contact.peerAccountId,
                            isVideo: false,
                            peerDisplayName: name,
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _CallHistoryRow {
  const _CallHistoryRow({
    required this.callId,
    required this.peerId,
    required this.peerName,
    required this.identifier,
    required this.direction,
    required this.outcome,
    required this.isVideo,
    required this.timestamp,
    required this.dateTime,
    required this.timeLabel,
    required this.durationSeconds,
    required this.durationLabel,
    required this.mediaLabel,
    this.repeatCount = 1,
  });

  final String callId;
  final String peerId;
  final String peerName;
  final String identifier;
  final String direction;
  final String outcome;
  final bool isVideo;
  final int timestamp;
  final DateTime dateTime;
  final String timeLabel;
  final int durationSeconds;
  final String durationLabel;
  final String mediaLabel;
  final int repeatCount;

  bool get isMissed =>
      direction.toUpperCase() == kCallDirectionMissed ||
      outcome.toLowerCase().contains('missed');

  bool get isNotAnswered =>
      durationSeconds == 0 &&
      (direction.toUpperCase() == kCallDirectionOutgoing ||
          outcome.toLowerCase() == 'declined' ||
          outcome.toLowerCase() == 'failed' ||
          outcome.toLowerCase() == 'busy' ||
          outcome.toLowerCase() == 'ended');

  String get displayTitle =>
      repeatCount > 1 ? '$peerName ($repeatCount)' : peerName;

  _CallHistoryRow copyWith({int? repeatCount}) {
    return _CallHistoryRow(
      callId: callId,
      peerId: peerId,
      peerName: peerName,
      identifier: identifier,
      direction: direction,
      outcome: outcome,
      isVideo: isVideo,
      timestamp: timestamp,
      dateTime: dateTime,
      timeLabel: timeLabel,
      durationSeconds: durationSeconds,
      durationLabel: durationLabel,
      mediaLabel: mediaLabel,
      repeatCount: repeatCount ?? this.repeatCount,
    );
  }

  String get directionLabel {
    if (isMissed) return 'Missed';
    return switch (direction.toUpperCase()) {
      kCallDirectionOutgoing => 'Outgoing',
      _ => 'Incoming',
    };
  }

  String get infoTitle {
    if (isMissed || isNotAnswered) return directionLabel;
    return directionLabel;
  }

  IconData get directionIcon {
    if (isMissed) return Icons.call_missed;
    return switch (direction.toUpperCase()) {
      kCallDirectionOutgoing => Icons.call_made,
      _ => Icons.call_received,
    };
  }
}

Color _avatarColor(String name, ColorScheme cs) {
  final colors = [
    cs.primaryContainer,
    cs.secondaryContainer,
    cs.tertiaryContainer,
    const Color(0xFFD7ECFF),
    const Color(0xFFFFE0CC),
    const Color(0xFFDFF6DE),
  ];
  return colors[name.hashCode.abs() % colors.length];
}

String _initials(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
  return trimmed.substring(0, trimmed.length.clamp(1, 2)).toUpperCase();
}
