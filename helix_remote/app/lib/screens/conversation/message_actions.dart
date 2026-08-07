part of '../conversation_screen.dart';

extension _ConversationMessageActions on _ConversationScreenState {
  // ---------------------------------------------------------------------------
  // Selection mode
  // ---------------------------------------------------------------------------

  void _enterSelectionMode(RemoteDecryptedMessage msg, Offset globalPos) {
    _update(() {
      _selectionMode = true;
      _selectedIds.add(msg.messageId);
    });
    _showMessageOverlay(msg, globalPos);
  }

  void _toggleSelection(String msgId) {
    _update(() {
      if (_selectedIds.contains(msgId)) {
        _selectedIds.remove(msgId);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(msgId);
      }
    });
  }

  void _exitSelectionMode() {
    _update(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _replyToSelected() {
    final msg = _messages.firstWhere((m) => _selectedIds.contains(m.messageId));
    _update(() {
      _replyTo = msg;
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _copySelected() async {
    final text = _messages
        .where((m) => _selectedIds.contains(m.messageId))
        .map((m) => m.text)
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(HelixLocalizations.of(context).copied)),
    );
    _exitSelectionMode();
  }

  Future<void> _deleteSelected() async {
    final toDelete = _messages
        .where((m) => _selectedIds.contains(m.messageId))
        .toList();
    _exitSelectionMode();
    for (final msg in toDelete) {
      _model.deleteForSelf(msg.messageId);
    }
    await _loadMessages();
  }

  Future<void> _deleteEveryoneSelected() async {
    final myId = _model.currentAccountId;
    final toDelete = _messages
        .where(
          (m) =>
              _selectedIds.contains(m.messageId) && m.senderAccountId == myId,
        )
        .toList();
    _exitSelectionMode();
    for (final msg in toDelete) {
      _model.deleteForEveryone(msg);
    }
    await _loadMessages();
  }

  bool get _allSelectedAreMine {
    final myId = _model.currentAccountId;
    return _messages
        .where((m) => _selectedIds.contains(m.messageId))
        .every((m) => m.senderAccountId == myId);
  }

  // ---------------------------------------------------------------------------
  // Message overlay (emoji + actions)
  // ---------------------------------------------------------------------------

  void _showMessageOverlay(RemoteDecryptedMessage message, Offset globalPos) {
    final isMine = message.senderAccountId == _model.currentAccountId;
    showDialog<void>(
      context: context,
      barrierColor: HelixScrimColors.barrier,
      barrierDismissible: true,
      builder: (ctx) {
        final screen = MediaQuery.of(ctx).size;
        final emojiTop = (globalPos.dy - 76).clamp(8.0, screen.height - 80.0);
        final menuTop = (globalPos.dy + 8).clamp(60.0, screen.height - 280.0);

        Widget actionItem(
          IconData icon,
          String label,
          VoidCallback fn, {
          Color? color,
        }) {
          final c = color ?? HelixScrimColors.onBackdrop;
          return InkWell(
            onTap: fn,
            child: Padding(
              padding: HelixInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, color: c, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c, fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              // Dismiss on background tap
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
              // Emoji bar
              Positioned(
                top: emojiTop,
                left: 8,
                right: 8,
                child: Container(
                  padding: HelixInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: HelixColorTokens.cFF2A2A2A,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: const [
                      BoxShadow(
                        color: HelixScrimColors.barrierSoft,
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final emoji in _kReactionEmojis)
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(ctx);
                            _addReaction(message, emoji);
                            _exitSelectionMode();
                          },
                          child: Padding(
                            padding: HelixInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                        ),
                      const VerticalDivider(
                        width: 16,
                        color: HelixScrimColors.onBackdropSubtle,
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Padding(
                          padding: HelixInsets.all(6),
                          child: const Icon(
                            Icons.add_reaction_outlined,
                            color: HelixScrimColors.onBackdropMuted,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Action menu
              Positioned(
                top: menuTop,
                right: isMine ? 8 : null,
                left: isMine ? null : 8,
                width: 230,
                child: Material(
                  borderRadius: BorderRadius.circular(12),
                  color: HelixColorTokens.cFF2A2A2A,
                  elevation: 8,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      actionItem(Icons.reply, 'Reply', () {
                        Navigator.pop(ctx);
                        _update(() => _replyTo = message);
                        _exitSelectionMode();
                      }),
                      actionItem(Icons.copy, 'Copy', () {
                        Navigator.pop(ctx);
                        _exitSelectionMode();
                        Clipboard.setData(ClipboardData(text: message.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              HelixLocalizations.of(context).copied,
                            ),
                          ),
                        );
                      }),
                      if (isMine)
                        actionItem(Icons.edit_outlined, 'Edit message', () {
                          Navigator.pop(ctx);
                          _exitSelectionMode();
                          _editMessage(message);
                        }),
                      const Divider(
                        height: 1,
                        color: HelixScrimColors.controlSurface,
                      ),
                      actionItem(
                        Icons.delete_outline,
                        'Delete for me',
                        () {
                          Navigator.pop(ctx);
                          _exitSelectionMode();
                          _deleteForSelf(message);
                        },
                        color: HelixColorTokens.cFFFF6B6B,
                      ),
                      if (isMine)
                        actionItem(
                          Icons.delete_forever_outlined,
                          'Delete for everyone',
                          () {
                            Navigator.pop(ctx);
                            _exitSelectionMode();
                            _deleteForEveryone(message);
                          },
                          color: HelixColorTokens.cFFFF6B6B,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _publishTyping(bool isTyping) async {
    if (_typingActive == isTyping) return;
    _typingActive = isTyping;
    try {
      await _model.publishTyping(isTyping);
    } catch (_) {}
  }

  Future<void> _editMessage(RemoteDecryptedMessage message) async {
    var draft = message.text;
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(HelixLocalizations.of(context).editMessage),
        content: TextFormField(
          initialValue: draft,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onChanged: (v) => draft = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(HelixLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, draft.trim()),
            child: Text(HelixLocalizations.of(context).save),
          ),
        ],
      ),
    );
    if (updated == null || updated.isEmpty || updated == message.text) return;
    await _model.editMessage(message, updated);
    await _loadMessages();
  }

  Future<void> _addReaction(
    RemoteDecryptedMessage message,
    String emoji,
  ) async {
    _model.addReaction(message, emoji);
    await _loadMessages();
  }

  Future<void> _quickReact(RemoteDecryptedMessage message) =>
      _addReaction(message, _kReactionEmojis.first);

  void _showReactionDetails(RemoteDecryptedMessage message) {
    final details = _model.reactionDetails(message.messageId);
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: HelixInsets.symmetric(vertical: 8),
            children: [
              ListTile(
                leading: const Icon(Icons.add_reaction_outlined),
                title: Text('${details.length} reaction participants'),
              ),
              for (final detail in details)
                ListTile(
                  leading: CircleAvatar(child: Text(detail.reaction)),
                  title: Text(detail.accountId),
                  subtitle: Text(
                    DateTime.fromMillisecondsSinceEpoch(
                      detail.timestamp,
                    ).toLocal().toString(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteForSelf(RemoteDecryptedMessage message) async {
    _model.deleteForSelf(message.messageId);
    await _loadMessages();
  }

  Future<void> _deleteForEveryone(RemoteDecryptedMessage message) async {
    _model.deleteForEveryone(message);
    await _loadMessages();
  }

  void _blockPeer() {
    if (_model.conversationMemberIds.length < 2) return;
    _model.blockPeer();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(HelixLocalizations.of(context).contactBlocked)),
    );
  }
}
