import 'package:helix_remote/services/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_attachment_service.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/presentation/calls/calls_tab_view_model.dart';
import 'package:helix_remote/screens/conversation_screen.dart';
import 'package:helix_remote/screens/scheduled_calls_screen.dart';
import 'package:helix_remote_domain/models.dart'
    show RemoteContact, ScheduledCall;
import 'package:helix_remote_calls/helix_remote_calls.dart';
import 'package:helix_remote_groups/helix_remote_groups.dart';

part 'calls_tab/widgets_primary.dart';
part 'calls_tab/widgets_secondary.dart';
part 'calls_tab/new_call_sheet.dart';

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
  late final CallsTabViewModel _viewModel;
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
    _viewModel = CallsTabViewModel(widget.messagingService);
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
      final convId = _viewModel.conversationIdForPeer(peerId);
      if (convId != null) {
        final name = _viewModel.peerDisplayName(convId);
        if (name != null && name.isNotEmpty) return name;
      }
    } catch (e) {
      // Falls through to the contact-list lookup below, so the UI still
      // resolves a name where it can.
      AppLogger.instance.warn('calls_tab', 'peer name lookup failed: \$e');
    }
    for (final contact in _viewModel.acceptedContacts()) {
      if (contact.peerAccountId == peerId && contact.nickname.isNotEmpty) {
        return contact.nickname;
      }
    }
    return peerId;
  }

  String _peerIdentifier(String peerId) {
    try {
      final contact = _viewModel.acceptedContacts().firstWhere(
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
                  contacts: _viewModel.acceptedContacts(),
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
    final conversationId = _viewModel.conversationIdForPeer(
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
    final contacts = _viewModel.acceptedContacts();
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
          myAccountId: _viewModel.currentAccountId,
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
