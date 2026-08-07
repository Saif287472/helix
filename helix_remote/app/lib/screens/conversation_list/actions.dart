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
      return RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * .65,
              child: HelixEmptyState(
                icon: Icons.chat_bubble_outline,
                title: emptyLabel,
                message: _searchQuery.isNotEmpty
                    ? 'Try a different search or filter.'
                    : 'Start an encrypted conversation with a contact.',
                action: _searchQuery.isEmpty
                    ? FilledButton.icon(
                        onPressed: _showNewChatPicker,
                        icon: const Icon(Icons.add_comment),
                        label: Text(HelixLocalizations.of(context).newChat),
                      )
                    : null,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => _forceSync(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: HelixInsets.only(top: 18, bottom: 112),
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
      ),
    );
  }
}
