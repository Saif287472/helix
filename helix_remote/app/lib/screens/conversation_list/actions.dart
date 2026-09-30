part of '../conversation_list_screen.dart';

extension _ConversationListBody on _ConversationListScreenState {
  /// People matching the search who are not already among the chats found.
  Widget _peopleResults(List<RemoteConversation> chats) {
    final me = _viewModel.currentAccountId;
    final shown = <String>{
      for (final chat in chats)
        if (!_isGroupConversation(chat))
          ..._viewModel.memberIds(chat.conversationId).where((id) => id != me),
    };
    return PeopleSearchResults(
      root: widget.root,
      messagingService: widget.messagingService,
      query: _searchQuery,
      excludeAccountIds: shown,
      showInvites: false,
      onPick: _onPersonPicked,
    );
  }

  Widget _buildConversationList() {
    final list = _filteredConversations;
    if (_searchQuery.isNotEmpty) {
      // Like a phone's messages app: one search finds chats and people -
      // and any number typed can be messaged directly.
      return ListView(
        padding: HelixInsets.only(top: 8, bottom: 112),
        children: [
          if (list.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Chats',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          for (final conv in list)
            _ConversationTile(
              conversation: conv,
              title: _resolvedTitle(conv),
              lastMessagePreview: _lastMessagePreview[conv.conversationId],
              unreadCount: widget.messagingService
                  .unreadSummary(conv.conversationId)
                  .unreadCount,
              isSelected: false,
              isSelectionMode: false,
              isGroup: _isGroupConversation(conv),
              onTap: () => _openConversation(conv.conversationId),
              onLongPress: () {},
            ),
          _peopleResults(list),
        ],
      );
    }
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
                        label: const Text('New chat'),
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
