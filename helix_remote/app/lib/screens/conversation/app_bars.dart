part of '../conversation_screen.dart';

extension _ConversationAppBars on _ConversationScreenState {
  AppBar _buildNormalAppBar(
    ColorScheme cs,
    String displayName,
    String initials,
  ) {
    final theme = Theme.of(context);
    final palette = conversationPalette(theme);
    return AppBar(
      toolbarHeight: 64,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: palette.appBar,
      foregroundColor: palette.onAppBar,
      titleSpacing: 0,
      leadingWidth: 44,
      leading: BackButton(color: palette.onAppBar),
      title: InkWell(
        onTap: _showContactInfo,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Hero(
              tag: 'conversation_avatar_${widget.conversationId}',
              child: CircleAvatar(
                radius: 21,
                backgroundColor: cs.primaryContainer,
                child: Text(
                  initials,
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.onAppBar,
                      fontSize: 20,
                      height: 1.06,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _headerSubtitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.onAppBar.withAlpha(185),
                      fontSize: 13,
                      height: 1,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Video call',
          icon: const Icon(Icons.videocam_outlined, size: 29),
          color: palette.onAppBar,
          onPressed: () => _startConversationCall(video: true),
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          tooltip: 'Voice call',
          icon: const Icon(Icons.call_outlined, size: 27),
          color: palette.onAppBar,
          onPressed: () => _startConversationCall(video: false),
          visualDensity: VisualDensity.compact,
        ),
        PopupMenuButton<String>(
          tooltip: 'More options',
          icon: Icon(Icons.more_vert, color: palette.onAppBar, size: 28),
          position: PopupMenuPosition.under,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          constraints: const BoxConstraints(minWidth: 280),
          onSelected: _handleConversationMenu,
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'view', child: Text('View contact')),
            PopupMenuItem(
              value: 'search',
              child: Text(_searching ? 'Close search' : 'Search'),
            ),
            const PopupMenuItem(
              value: 'media',
              child: Text('Media, links, and docs'),
            ),
            const PopupMenuItem(
              value: 'mute',
              child: Text('Mute notifications'),
            ),
            const PopupMenuItem(
              value: 'disappearing',
              child: Text('Disappearing messages'),
            ),
            const PopupMenuItem(value: 'theme', child: Text('Chat theme')),
            PopupMenuItem(
              value: 'more',
              child: Row(
                children: [
                  const Expanded(child: Text('More')),
                  Icon(Icons.arrow_right, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _handleConversationMenu(String value) {
    switch (value) {
      case 'view':
        _showContactInfo();
      case 'search':
        _update(() {
          _searching = !_searching;
          if (!_searching) _searchController.clear();
        });
        _loadMessages();
      case 'media':
        _showPlaceholder('Media, links, and docs');
      case 'mute':
        _showPlaceholder('Mute notifications');
      case 'disappearing':
        unawaited(_showDisappearingPolicyDialog());
      case 'theme':
        _showPlaceholder('Chat theme');
      case 'more':
        unawaited(_showMoreMenu());
    }
  }

  String _headerSubtitle() {
    if (_typingActive) return 'typing...';
    if (_messages.isEmpty) return 'Helix Remote';
    final latest = DateTime.fromMillisecondsSinceEpoch(
      _messages.first.timestamp,
    );
    return _formatHeaderTime(latest);
  }

  String _formatHeaderTime(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(value.year, value.month, value.day);
    final time = _formatClock(value);
    if (day == today) return time;
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${_monthName(value.month)} ${value.day}, ${value.year}';
  }

  String _formatClock(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  String _monthName(int month) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[month - 1];
  }

  void _startConversationCall({required bool video}) {
    if (widget.callsAvailable) {
      if (video) {
        widget.onStartVideoCall?.call();
      } else {
        widget.onStartAudioCall?.call();
      }
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Calls require TURN relay configuration')),
    );
  }

  void _showContactInfo() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContactInfoScreen(
          conversationId: widget.conversationId,
          messagingService: widget.messagingService,
          groupService: widget.groupService,
          callsAvailable: widget.callsAvailable,
          onStartAudioCall: widget.onStartAudioCall,
          onStartVideoCall: widget.onStartVideoCall,
          onStartSearch: () {
            _update(() {
              _searching = true;
              _searchController.clear();
            });
          },
        ),
      ),
    );
  }

  Future<void> _showMoreMenu() async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(overlay.size.width - 236, 78, 12, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      constraints: const BoxConstraints(minWidth: 220),
      items: const [
        PopupMenuItem(value: 'report', child: Text('Report')),
        PopupMenuItem(value: 'block', child: Text('Block')),
        PopupMenuItem(value: 'clear', child: Text('Clear chat')),
        PopupMenuItem(value: 'export', child: Text('Export chat')),
        PopupMenuItem(value: 'shortcut', child: Text('Add shortcut')),
        PopupMenuItem(value: 'list', child: Text('Add to list')),
      ],
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case 'block':
        _blockPeer();
      case 'clear':
        _model.clearChat();
        await _loadMessages();
      default:
        _showPlaceholder(switch (selected) {
          'report' => 'Report',
          'export' => 'Export chat',
          'shortcut' => 'Add shortcut',
          'list' => 'Add to list',
          _ => selected,
        });
    }
  }

  void _showPlaceholder(String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label is not available yet')));
  }

  Future<void> _showDisappearingPolicyDialog() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Disappearing messages'),
        children: [
          for (final option in const {
            0: 'Off',
            86400: '24 hours',
            604800: '7 days',
            7776000: '90 days',
          }.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, option.key),
              child: Text(option.value),
            ),
        ],
      ),
    );
    if (selected == null) return;
    _model.setDisappearingPolicy(selected);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(selected == 0 ? 'Disappearing off' : 'Timer updated'),
      ),
    );
  }

  AppBar _buildSelectionAppBar(ColorScheme cs) {
    final count = _selectedIds.length;
    final singleSelected = count == 1;
    final palette = conversationPalette(Theme.of(context));
    return AppBar(
      toolbarHeight: 64,
      elevation: 0,
      backgroundColor: palette.appBar,
      foregroundColor: palette.onAppBar,
      leading: IconButton(
        tooltip: 'Exit selection',
        icon: Icon(Icons.close, color: palette.onAppBar),
        onPressed: _exitSelectionMode,
      ),
      title: Text('$count', style: TextStyle(color: palette.onAppBar)),
      actions: [
        if (singleSelected)
          IconButton(
            tooltip: 'Reply',
            icon: Icon(Icons.reply, color: palette.onAppBar),
            onPressed: _replyToSelected,
          ),
        IconButton(
          tooltip: 'Copy',
          icon: Icon(Icons.copy, color: palette.onAppBar),
          onPressed: _copySelected,
        ),
        IconButton(
          tooltip: 'Delete',
          icon: Icon(Icons.delete_outline, color: palette.onAppBar),
          onPressed: _deleteSelected,
        ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: palette.onAppBar),
          onSelected: (v) {
            if (v == 'delete_everyone') _deleteEveryoneSelected();
          },
          itemBuilder: (_) => [
            if (_allSelectedAreMine)
              const PopupMenuItem(
                value: 'delete_everyone',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_forever_outlined,
                      size: 20,
                      color: HelixStatusColors.danger,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Delete for everyone',
                      style: TextStyle(color: HelixStatusColors.danger),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
