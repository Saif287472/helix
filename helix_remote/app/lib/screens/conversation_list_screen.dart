import 'dart:async';

import 'package:flutter/material.dart';
import 'package:helix_remote/services/screen_security.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_attachment_service.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/app/remote_runtime_coordinator.dart';
import 'package:helix_remote/screens/conversation_screen.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_groups/helix_remote_groups.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';

class ConversationListScreen extends StatefulWidget {
  const ConversationListScreen({
    super.key,
    required this.messagingService,
    required this.root,
    this.onChangeServerUrl,
  });

  final RemoteMessagingService messagingService;
  final RemoteCompositionRoot root;
  final Future<void> Function()? onChangeServerUrl;

  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

enum _ChatFilter { all, unread, favorites, groups, custom }

class _ConversationListScreenState extends State<ConversationListScreen>
    with SecureScreenStateMixin {
  List<RemoteConversation> _conversations = [];
  bool _loaded = false;
  bool _showSearch = false;
  String _searchQuery = '';
  final Map<String, String> _lastMessagePreview = {};
  String? _statusText;
  RemoteRuntimeSnapshot? _runtimeSnapshot;
  RemoteOutboxSummary? _outboxSummary;
  StreamSubscription<RemoteSyncChange>? _changeSub;
  StreamSubscription<RemoteRuntimeSnapshot>? _runtimeSub;
  final _searchController = TextEditingController();
  _ChatFilter _activeFilter = _ChatFilter.all;
  final Set<String> _selectedConversationIds = {};

  bool get _selectionMode => _selectedConversationIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _runtimeSnapshot = _tryRuntimeSnapshot();
    _changeSub = widget.messagingService.changes.listen(_onRemoteChange);
    _runtimeSub = _tryRuntimeCoordinator()?.snapshots.listen((snapshot) {
      if (mounted) setState(() => _runtimeSnapshot = snapshot);
    });
    _outboxSummary = widget.messagingService.outboxSummary();
    _reload();
  }

  void _onRemoteChange(RemoteSyncChange change) {
    if (change.affects(RemoteSyncChangeArea.outbox)) {
      _refreshOutboxSummary();
    }
    if (!change.affects(RemoteSyncChangeArea.conversations) &&
        !change.affects(RemoteSyncChangeArea.contacts) &&
        !change.affects(RemoteSyncChangeArea.groups) &&
        !change.affects(RemoteSyncChangeArea.devices)) {
      return;
    }
    _reload();
  }

  void _refreshOutboxSummary() {
    if (!mounted) return;
    setState(() => _outboxSummary = widget.messagingService.outboxSummary());
  }

  void _reload() {
    try {
      final convos = widget.messagingService.conversationList();
      setState(() {
        _conversations = convos;
        _loaded = true;
      });
      _fetchLastMessages(convos);
    } catch (e) {
      debugPrint('ConversationListScreen._reload error: $e');
      setState(() => _loaded = true);
    }
  }

  void _fetchLastMessages(List<RemoteConversation> convos) {
    for (final conv in convos) {
      widget.messagingService
          .messageHistory(conv.conversationId, limit: 1)
          .then((msgs) {
            if (msgs.isNotEmpty && mounted) {
              setState(() {
                _lastMessagePreview[conv.conversationId] = msgs.first.text;
              });
            }
          })
          .ignore();
    }
  }

  RemoteRuntimeCoordinator? _tryRuntimeCoordinator() {
    try {
      return widget.root.runtimeCoordinator;
    } on StateError {
      return null;
    }
  }

  RemoteRuntimeSnapshot? _tryRuntimeSnapshot() =>
      _tryRuntimeCoordinator()?.snapshot;

  Future<void> _showNewChatPicker() async {
    final contacts = widget.messagingService.acceptedContacts();
    if (!mounted) return;
    final peerAccountId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ContactPickerSheet(contacts: contacts),
    );
    if (peerAccountId == null || !mounted) return;
    final derivedId = widget.messagingService.conversationIdForPeer(
      peerAccountId,
    );
    if (derivedId == null) return;
    // conversationIdForPeer only derives the ID string - it never creates
    // the conversation row/membership. Without this, picking a contact
    // here who has no prior chat opened a ConversationScreen for a
    // conversation that doesn't exist in the database at all. Guarded by
    // an existence check because createDirectConversation's upsert resets
    // last_sequence to 0, which would corrupt an already-existing
    // conversation's unread/sort state if called again for someone
    // already chatted with.
    final alreadyExists = widget.messagingService
        .conversationMemberIds(derivedId)
        .isNotEmpty;
    final conversationId = alreadyExists
        ? derivedId
        : widget.messagingService.createDirectConversation(
            peerAccountId: peerAccountId,
          );
    _openConversation(conversationId);
  }

  void _openConversation(String conversationId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
          conversationId: conversationId,
          messagingService: widget.messagingService,
          attachmentService: _tryAttachmentService(),
          groupService: _tryGroupService(),
          callsAvailable: _tryCallsAvailable(),
          onStartAudioCall: () => _initiateCall(conversationId, isVideo: false),
          onStartVideoCall: () => _initiateCall(conversationId, isVideo: true),
        ),
      ),
    );
  }

  bool _tryCallsAvailable() {
    try {
      return widget.root.callsAvailable;
    } catch (_) {
      return false;
    }
  }

  Future<void> _initiateCall(
    String conversationId, {
    required bool isVideo,
  }) async {
    final accountId = widget.messagingService.currentAccountId;
    final members = widget.messagingService.conversationMemberIds(
      conversationId,
    );
    final peer = members.where((id) => id != accountId).firstOrNull;
    if (peer == null) return;
    final contact = widget.messagingService
        .acceptedContacts()
        .where((c) => c.peerAccountId == peer)
        .firstOrNull;
    final displayName = contact == null || contact.nickname.isEmpty
        ? peer
        : contact.nickname;
    try {
      // Awaited on purpose. `startOutgoingCall` is async and rethrows after
      // it has cleaned up, so without the await its error bypassed this
      // catch entirely and surfaced as an uncaught zone error seconds after
      // the UI had already given up - which is how a plain "TURN is not
      // configured" 503 ended up in the logs as a crash report.
      await widget.root.callService.startOutgoingCall(
        peerId: peer,
        isVideo: isVideo,
        peerDisplayName: displayName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Call failed: $e')));
      }
    }
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

  Future<void> _forceSync() async {
    final coordinator = _tryRuntimeCoordinator();
    if (coordinator != null) {
      await coordinator.softSync();
    }
    _reload();
  }

  List<RemoteConversation> get _filteredConversations {
    var list = _conversations;

    switch (_activeFilter) {
      case _ChatFilter.groups:
        list = list.where(_isGroupConversation).toList();
      case _ChatFilter.unread:
        list = list
            .where(
              (c) =>
                  widget.messagingService
                      .unreadSummary(c.conversationId)
                      .unreadCount >
                  0,
            )
            .toList();
      case _ChatFilter.favorites:
        list = list.where((c) => c.isFavorite).toList();
      case _ChatFilter.custom:
        list = widget.messagingService.conversationListByKind(
          'custom',
          listId: _defaultListId,
        );
      case _ChatFilter.all:
        break;
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((c) => c.title.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  static const _defaultListId = 'helix_quick_list';

  bool _isGroupConversation(RemoteConversation conversation) =>
      conversation.type.toLowerCase().contains('group');

  List<RemoteConversation> get _selectedConversations => _conversations
      .where((c) => _selectedConversationIds.contains(c.conversationId))
      .toList();

  bool _hasUnread(RemoteConversation conversation) =>
      widget.messagingService
          .unreadSummary(conversation.conversationId)
          .unreadCount >
      0;

  String _resolvedTitle(RemoteConversation conv) => conv.title.isNotEmpty
      ? conv.title
      : widget.messagingService.peerDisplayName(conv.conversationId) ??
            conv.conversationId;

  void _toggleSelection(RemoteConversation conversation) {
    setState(() {
      if (!_selectedConversationIds.remove(conversation.conversationId)) {
        _selectedConversationIds.add(conversation.conversationId);
      }
    });
  }

  void _clearSelection() => setState(_selectedConversationIds.clear);

  void _selectAllVisible() {
    setState(() {
      _selectedConversationIds
        ..clear()
        ..addAll(_filteredConversations.map((c) => c.conversationId));
    });
  }

  void _markSelectedRead() {
    for (final conv in _selectedConversations) {
      widget.messagingService.markConversationRead(conv.conversationId);
    }
    _clearSelection();
  }

  void _markSelectedUnread() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mark as unread is not available yet')),
    );
  }

  void _pinSelected() {
    for (final conv in _selectedConversations) {
      widget.messagingService.pinConversation(
        conv.conversationId,
        pinned: true,
      );
    }
    _clearSelection();
  }

  void _muteSelected() {
    for (final conv in _selectedConversations) {
      widget.messagingService.muteConversation(
        conv.conversationId,
        muted: true,
      );
    }
    _clearSelection();
  }

  void _archiveSelected() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Archive is not available in Helix yet')),
    );
  }

  void _lockSelected() {
    for (final conv in _selectedConversations) {
      widget.messagingService.db.setConversationLocked(
        conv.conversationId,
        locked: true,
        hidden: false,
      );
    }
    _clearSelection();
    _reload();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Selected chats locked')));
  }

  void _favoriteSelected() {
    for (final conv in _selectedConversations) {
      widget.messagingService.favoriteConversation(
        conv.conversationId,
        favorite: true,
      );
    }
    _clearSelection();
  }

  void _addSelectedToList() {
    widget.messagingService.createCustomConversationList(
      listId: _defaultListId,
      name: 'Quick list',
      sortOrder: 0,
    );
    var sort = 0;
    for (final conv in _selectedConversations) {
      widget.messagingService.addConversationToCustomList(
        listId: _defaultListId,
        conversationId: conv.conversationId,
        sortOrder: sort++,
      );
    }
    _clearSelection();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Added to Quick list')));
  }

  Future<void> _clearSelectedChats() async {
    final count = _selectedConversationIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear chats'),
        content: Text(
          'Clear messages in $count selected ${count == 1 ? 'chat' : 'chats'} from this device?',
        ),
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
    for (final conv in _selectedConversations) {
      widget.messagingService.clearChat(conv.conversationId);
      _lastMessagePreview.remove(conv.conversationId);
    }
    _clearSelection();
  }

  Future<void> _deleteSelected() async {
    final count = _selectedConversationIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete chats'),
        content: Text(
          'Delete $count selected ${count == 1 ? 'conversation' : 'conversations'} from this device?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    for (final conv in _selectedConversations) {
      widget.messagingService.deleteConversation(conv.conversationId);
    }
    _clearSelection();
  }

  @override
  void dispose() {
    _changeSub?.cancel();
    _runtimeSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      final cs = Theme.of(context).colorScheme;
      return Scaffold(
        backgroundColor: cs.surface,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Exit selection',
                onPressed: _clearSelection,
              )
            : null,
        title: _selectionMode
            ? Text(
                '${_selectedConversationIds.length}',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                  fontSize: 22,
                ),
              )
            : _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: colorScheme.onSurface),
                cursorColor: colorScheme.primary,
                decoration: InputDecoration(
                  hintText: 'Search chats…',
                  hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : Text(
                'Helix Remote',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
        actions: _selectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.push_pin_outlined),
                  onPressed: _pinSelected,
                  tooltip: 'Pin',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _deleteSelected,
                  tooltip: 'Delete',
                ),
                IconButton(
                  icon: const Icon(Icons.notifications_off_outlined),
                  onPressed: _muteSelected,
                  tooltip: 'Mute',
                ),
                IconButton(
                  icon: const Icon(Icons.archive_outlined),
                  onPressed: _archiveSelected,
                  tooltip: 'Archive',
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    switch (value) {
                      case 'mark_read':
                        _markSelectedRead();
                      case 'mark_unread':
                        _markSelectedUnread();
                      case 'select_all':
                        _selectAllVisible();
                      case 'lock':
                        _lockSelected();
                      case 'favorite':
                        _favoriteSelected();
                      case 'list':
                        _addSelectedToList();
                      case 'clear':
                        _clearSelectedChats();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'mark_read',
                      child: Text('Mark as read'),
                    ),
                    PopupMenuItem(
                      value: 'mark_unread',
                      child: Text('Mark as unread'),
                    ),
                    PopupMenuItem(
                      value: 'select_all',
                      child: Text('Select all'),
                    ),
                    PopupMenuItem(value: 'lock', child: Text('Lock chats')),
                    PopupMenuItem(
                      value: 'favorite',
                      child: Text('Add to Favorites'),
                    ),
                    PopupMenuItem(value: 'list', child: Text('Add to list')),
                    PopupMenuItem(value: 'clear', child: Text('Clear chats')),
                  ],
                ),
              ]
            : [
                IconButton(
                  icon: Icon(Icons.sync, color: colorScheme.onSurface),
                  onPressed: _forceSync,
                  tooltip: 'Sync now',
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: colorScheme.onSurface),
                  onSelected: (v) {
                    if (v == 'refresh') _forceSync();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'refresh', child: Text('Refresh')),
                  ],
                ),
              ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
            child: _SearchField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              onClear: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _showSearch = false;
                });
              },
            ),
          ),
          if (_runtimeSnapshot != null)
            _ConnectionBanner(
              stateLabel: _runtimeSnapshot!.state.name,
              onRetry: () => _tryRuntimeCoordinator()?.start(),
            ),
          if (_statusText != null)
            MaterialBanner(
              content: Text(_statusText!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _statusText = null),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          if (_outboxSummary?.hasVisibleWork ?? false)
            _OutboxBanner(
              summary: _outboxSummary!,
              onRetry: () async {
                await widget.messagingService.retryFailedOutbox();
                if (mounted) _refreshOutboxSummary();
              },
            ),
          _FilterChipsRow(
            active: _activeFilter,
            unreadCount: _conversations.where(_hasUnread).length,
            groupCount: _conversations.where(_isGroupConversation).length,
            onSelect: (_ChatFilter f) => setState(() => _activeFilter = f),
          ),
          Expanded(child: _buildConversationList()),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'new_chat_fab',
        onPressed: _showNewChatPicker,
        tooltip: 'New chat',
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: const Icon(Icons.add_comment),
      ),
    );
  }

  Widget _buildConversationList() {
    final list = _filteredConversations;
    if (list.isEmpty) {
      final emptyLabel = _activeFilter == _ChatFilter.unread
          ? 'No unread conversations'
          : _activeFilter == _ChatFilter.groups
          ? 'No group conversations yet'
          : _searchQuery.isNotEmpty
          ? 'No chats match "$_searchQuery"'
          : 'No conversations yet';
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              emptyLabel,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 18, bottom: 112),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final conv = list[index];
        final resolvedTitle = _resolvedTitle(conv);
        return _ConversationTile(
          conversation: conv,
          title: resolvedTitle,
          lastMessagePreview: _lastMessagePreview[conv.conversationId],
          unreadCount: widget.messagingService
              .unreadSummary(conv.conversationId)
              .unreadCount,
          isSelected: _selectedConversationIds.contains(conv.conversationId),
          isSelectionMode: _selectionMode,
          isGroup: _isGroupConversation(conv),
          onTap: () {
            if (_selectionMode) {
              _toggleSelection(conv);
              return;
            }
            _openConversation(conv.conversationId);
          },
          onLongPress: () => _toggleSelection(conv),
        );
      },
    );
  }
}

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
        padding: const EdgeInsets.fromLTRB(22, 8, 20, 8),
        constraints: const BoxConstraints(minHeight: 72),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _Avatar(name: title, size: 56),
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
                          padding: const EdgeInsets.symmetric(horizontal: 7),
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
        color: Color(0xFFE91E63),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

class ContactTile extends StatelessWidget {
  const ContactTile({
    super.key,
    required this.contact,
    required this.onTap,
    this.request,
    this.onAccept,
    this.onReject,
    this.onCancel,
    this.onRemove,
  });

  final RemoteContact contact;
  final RemoteContactRequest? request;
  final VoidCallback onTap;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onCancel;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = contact.nickname.isNotEmpty
        ? contact.nickname
        : contact.peerAccountId;

    Widget trailing = const SizedBox.shrink();
    if (contact.status == 'PendingReceived' &&
        onAccept != null &&
        onReject != null) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Accept request',
            icon: const Icon(Icons.check_circle_outline, color: Colors.green),
            onPressed: onAccept,
          ),
          IconButton(
            tooltip: 'Reject request',
            icon: const Icon(Icons.cancel_outlined, color: Colors.red),
            onPressed: onReject,
          ),
          if (onRemove != null) _MoreMenu(onRemove: onRemove!),
        ],
      );
    } else if (contact.status == 'PendingSent' && onCancel != null) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
          if (onRemove != null) _MoreMenu(onRemove: onRemove!),
        ],
      );
    } else if (contact.status == 'Accepted') {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chevron_right, color: theme.colorScheme.outline),
          if (onRemove != null) _MoreMenu(onRemove: onRemove!),
        ],
      );
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _Avatar(name: name, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    contact.status,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.onRemove});
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'remove') onRemove();
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'remove',
          child: Row(
            children: [
              Icon(Icons.person_remove_outlined, color: Colors.red),
              SizedBox(width: 8),
              Text('Remove contact', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared avatar widget with color-coded initials
// ---------------------------------------------------------------------------

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.size = 48});

  final String name;
  final double size;

  static const _palette = [
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFF3F51B5),
    Color(0xFF2196F3),
    Color(0xFF009688),
    Color(0xFF4CAF50),
    Color(0xFFFF9800),
    Color(0xFFF44336),
    Color(0xFF00BCD4),
    Color(0xFF795548),
  ];

  Color _color() => _palette[name.hashCode.abs() % _palette.length];

  String _initials() {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return trimmed.substring(0, trimmed.length.clamp(1, 2)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: _color(),
      child: Text(
        _initials(),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.35,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contact picker bottom sheet for "New chat"
// ---------------------------------------------------------------------------

class _ContactPickerSheet extends StatefulWidget {
  const _ContactPickerSheet({required this.contacts});
  final List<RemoteContact> contacts;

  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RemoteContact> get _filtered {
    if (_query.isEmpty) return widget.contacts;
    final q = _query.toLowerCase();
    return widget.contacts.where((c) {
      return c.nickname.toLowerCase().contains(q) ||
          c.peerAccountId.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final filtered = _filtered;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) {
        return Column(
          children: [
            // Handle bar
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
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'New chat',
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
            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchController,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'Search contacts…',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 4),
            // Contact list
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
                          leading: _Avatar(name: name, size: 44),
                          title: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: contact.nickname.isNotEmpty
                              ? Text(
                                  contact.peerAccountId,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          onTap: () =>
                              Navigator.of(context).pop(contact.peerAccountId),
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

// ---------------------------------------------------------------------------
// Connection status banner (reused across screens)
// ---------------------------------------------------------------------------

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
