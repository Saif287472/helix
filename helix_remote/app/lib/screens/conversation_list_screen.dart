import 'dart:async';

import 'package:flutter/material.dart';
import 'package:helix_remote/services/screen_security.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_attachment_service.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/app/remote_runtime_coordinator.dart';
import 'package:helix_remote/presentation/conversation_list/conversation_list_view_model.dart';
import 'package:helix_remote/screens/conversation_screen.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_groups/helix_remote_groups.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

part 'conversation_list/actions.dart';
part 'conversation_list/widgets_primary.dart';
part 'conversation_list/widgets_secondary.dart';
part 'conversation_list/widgets_status.dart';

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
  late final ConversationListViewModel _viewModel;
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
  String? _desktopConversationId;

  bool get _selectionMode => _selectedConversationIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _viewModel = ConversationListViewModel(widget.messagingService);
    _runtimeSnapshot = _tryRuntimeSnapshot();
    _changeSub = _viewModel.changes.listen(_onRemoteChange);
    _runtimeSub = _tryRuntimeCoordinator()?.snapshots.listen((snapshot) {
      if (mounted) setState(() => _runtimeSnapshot = snapshot);
    });
    _outboxSummary = _viewModel.outboxSummary();
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
    setState(() => _outboxSummary = _viewModel.outboxSummary());
  }

  void _reload() {
    try {
      final convos = _viewModel.conversations();
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
      _viewModel.preview(conv.conversationId).then((msgs) {
        if (msgs.isNotEmpty && mounted) {
          setState(() {
            _lastMessagePreview[conv.conversationId] = msgs.first.text;
          });
        }
      }).ignore();
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
    final contacts = _viewModel.acceptedContacts();
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
    final derivedId = _viewModel.conversationIdForPeer(peerAccountId);
    if (derivedId == null) return;
    // conversationIdForPeer only derives the ID string - it never creates
    // the conversation row/membership. Without this, picking a contact
    // here who has no prior chat opened a ConversationScreen for a
    // conversation that doesn't exist in the database at all. Guarded by
    // an existence check because createDirectConversation's upsert resets
    // last_sequence to 0, which would corrupt an already-existing
    // conversation's unread/sort state if called again for someone
    // already chatted with.
    final alreadyExists = _viewModel.memberIds(derivedId).isNotEmpty;
    final conversationId = alreadyExists
        ? derivedId
        : _viewModel.createDirectConversation(peerAccountId);
    _openConversation(conversationId);
  }

  void _openConversation(String conversationId) {
    if (HelixBreakpoints.isTablet(context)) {
      setState(() => _desktopConversationId = conversationId);
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
    final accountId = _viewModel.currentAccountId;
    final members = _viewModel.memberIds(conversationId);
    final peer = members.where((id) => id != accountId).firstOrNull;
    if (peer == null) return;
    final contact = _viewModel
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
            .where((c) => _viewModel.unreadCount(c.conversationId) > 0)
            .toList();
      case _ChatFilter.favorites:
        list = list.where((c) => c.isFavorite).toList();
      case _ChatFilter.custom:
        list = _viewModel.customList(_defaultListId);
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
      _viewModel.unreadCount(conversation.conversationId) > 0;

  String _resolvedTitle(RemoteConversation conv) => conv.title.isNotEmpty
      ? conv.title
      : _viewModel.peerDisplayName(conv.conversationId) ?? conv.conversationId;

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
      _viewModel.markRead(conv.conversationId);
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
      _viewModel.pin(conv.conversationId);
    }
    _clearSelection();
  }

  void _muteSelected() {
    for (final conv in _selectedConversations) {
      _viewModel.mute(conv.conversationId);
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
      _viewModel.lock(conv.conversationId);
    }
    _clearSelection();
    _reload();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Selected chats locked')));
  }

  void _favoriteSelected() {
    for (final conv in _selectedConversations) {
      _viewModel.favorite(conv.conversationId);
    }
    _clearSelection();
  }

  void _addSelectedToList() {
    _viewModel.createQuickList(_defaultListId);
    var sort = 0;
    for (final conv in _selectedConversations) {
      _viewModel.addToList(
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
      _viewModel.clearChat(conv.conversationId);
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
      _viewModel.deleteConversation(conv.conversationId);
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
        body: const Center(child: HelixSkeleton(width: 180, height: 24)),
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final listPane = Column(
            children: [
              Padding(
                padding: HelixInsets.fromLTRB(22, 4, 22, 14),
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
                    await _viewModel.retryFailedOutbox();
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
          );
          if (constraints.maxWidth < HelixBreakpoints.medium) return listPane;
          final selectedConversationId = _desktopConversationId;
          return Row(
            children: [
              SizedBox(width: 380, child: listPane),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: colorScheme.outlineVariant,
              ),
              Expanded(
                child: selectedConversationId == null
                    ? const HelixEmptyState(
                        icon: Icons.forum_outlined,
                        title: 'Select a conversation',
                        message:
                            'Choose a chat to open it alongside your list.',
                      )
                    : ConversationScreen(
                        conversationId: selectedConversationId,
                        messagingService: widget.messagingService,
                        attachmentService: _tryAttachmentService(),
                        groupService: _tryGroupService(),
                        callsAvailable: _tryCallsAvailable(),
                        onStartAudioCall: () => _initiateCall(
                          selectedConversationId,
                          isVideo: false,
                        ),
                        onStartVideoCall: () => _initiateCall(
                          selectedConversationId,
                          isVideo: true,
                        ),
                      ),
              ),
            ],
          );
        },
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
}
