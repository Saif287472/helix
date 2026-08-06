part of '../conversation_list_screen.dart';

extension _ConversationListBody on _ConversationListScreenState {
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
