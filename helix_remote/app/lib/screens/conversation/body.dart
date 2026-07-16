part of '../conversation_screen.dart';

extension _ConversationBody on _ConversationScreenState {
  // ---------------------------------------------------------------------------
  // Reply preview
  // ---------------------------------------------------------------------------

  Widget _buildReplyPreview(ColorScheme cs) {
    final reply = _replyTo!;
    final isMine =
        reply.senderAccountId == widget.messagingService.currentAccountId;
    final senderLabel = isMine
        ? 'You'
        : (widget.messagingService.peerDisplayName(widget.conversationId) ??
              reply.senderAccountId);

    return Container(
      color: cs.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(width: 3, height: 40, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  senderLabel,
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reply.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface.withAlpha(180),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => _update(() => _replyTo = null),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Message list
  // ---------------------------------------------------------------------------

  Widget _buildSearchField() {
    final theme = Theme.of(context);
    final palette = _chatPalette(theme);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: 'Search this conversation',
          filled: true,
          fillColor: palette.input,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (_) => _loadMessages(),
      ),
    );
  }

  Widget _buildLoadEarlierButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: _loadingMore
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton.icon(
                onPressed: _loadMore,
                icon: const Icon(Icons.expand_less, size: 18),
                label: const Text('Load earlier messages'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHigh,
                  shape: const StadiumBorder(),
                ),
              ),
      ),
    );
  }

  GlobalKey _keyForMessage(String messageId) {
    return _messageKeys.putIfAbsent(
      messageId,
      () => GlobalKey(debugLabel: 'message_$messageId'),
    );
  }

  Future<void> _jumpToMessage(String messageId) async {
    if (_searching) {
      _update(() {
        _searching = false;
        _searchController.clear();
      });
      await _loadMessages();
    }

    while (!_messages.any((m) => m.messageId == messageId) && _hasMore) {
      await _loadMore();
    }

    final index = _messages.indexWhere((m) => m.messageId == messageId);
    if (index < 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Original message not found')),
      );
      return;
    }

    _update(() => _highlightedMessageId = messageId);

    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      final roughOffset = (index * 72.0).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      await _scrollController.animateTo(
        roughOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (!mounted) return;
    final targetContext = _messageKeys[messageId]?.currentContext;
    if (targetContext != null) {
      if (!targetContext.mounted) return;
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.45,
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (mounted && _highlightedMessageId == messageId) {
      _update(() => _highlightedMessageId = null);
    }
  }

  Widget _buildMessageList() {
    if (!_loaded) {
      return const _ChatWallpaper(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_errorMessage != null) {
      return _ChatWallpaper(
        child: Center(
          child: GestureDetector(
            onTap: _loadMessages,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 8),
                Text(_errorMessage!, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return _ChatWallpaper(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _chatPalette(Theme.of(context)).dateChip,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              _searching ? 'No matching messages' : 'No messages yet',
              style: TextStyle(
                color: _chatPalette(Theme.of(context)).dateChipText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }
    final currentAccountId = widget.messagingService.currentAccountId;
    // In a reverse list, the last index renders at the visual top.
    // We add one extra slot there for the "load earlier" button when applicable.
    final hasHeader = _hasMore && !_searching;
    return _ChatWallpaper(
      child: ListView.builder(
        controller: _scrollController,
        reverse: true,
        padding: const EdgeInsets.fromLTRB(0, 7, 0, 8),
        itemCount: _messages.length + (hasHeader ? 1 : 0),
        itemBuilder: (context, index) {
          if (hasHeader && index == _messages.length) {
            return _buildLoadEarlierButton();
          }

          final msg = _messages[index];
          final showDate = _shouldShowDateChip(index);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showDate) _DateChip(timestamp: msg.timestamp),
              _MessageTile(
                key: _keyForMessage(msg.messageId),
                message: msg,
                currentAccountId: currentAccountId,
                isSelected: _selectedIds.contains(msg.messageId),
                isHighlighted: _highlightedMessageId == msg.messageId,
                selectionMode: _selectionMode,
                onLongPress: (pos) {
                  if (_selectionMode) {
                    _toggleSelection(msg.messageId);
                  } else {
                    _enterSelectionMode(msg, pos);
                  }
                },
                onTap: () {
                  if (_selectionMode) _toggleSelection(msg.messageId);
                },
                onDoubleTap: () => _quickReact(msg),
                onSwipeReply: () => _update(() => _replyTo = msg),
                onTapReply: (messageId) => _jumpToMessage(messageId),
                onReactionTap: () => _showReactionDetails(msg),
                onDownloadAttachment: msg.attachment == null
                    ? null
                    : () => _downloadAttachment(msg.attachment!),
                onExportAttachment: msg.attachment == null
                    ? null
                    : () => _exportAttachment(msg.attachment!),
              ),
            ],
          );
        },
      ),
    );
  }

  bool _shouldShowDateChip(int index) {
    final current = DateTime.fromMillisecondsSinceEpoch(
      _messages[index].timestamp,
    );
    if (index == _messages.length - 1) return true;
    final older = DateTime.fromMillisecondsSinceEpoch(
      _messages[index + 1].timestamp,
    );
    return current.year != older.year ||
        current.month != older.month ||
        current.day != older.day;
  }

  Widget _buildAttachmentBanner() {
    return MaterialBanner(
      content: Text(_attachmentStatus!),
      actions: [
        TextButton(
          onPressed: () => _update(() => _attachmentStatus = null),
          child: const Text('Dismiss'),
        ),
      ],
    );
  }

  Widget _buildInput() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final palette = _chatPalette(theme);

    return SafeArea(
      top: false,
      child: Container(
        color: palette.inputBar,
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: palette.input,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(
                        Icons.emoji_emotions_outlined,
                        color: cs.outline,
                      ),
                      onPressed: null,
                      tooltip: 'Emoji',
                      padding: const EdgeInsets.all(8),
                      visualDensity: VisualDensity.compact,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        maxLines: 5,
                        minLines: 1,
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (value) {
                          _publishTyping(value.trim().isNotEmpty);
                        },
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    if (widget.attachmentService != null)
                      IconButton(
                        icon: _attachmentBusy
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(Icons.attach_file, color: cs.outline),
                        onPressed: _attachmentBusy ? null : _attachFile,
                        tooltip: 'Attach file',
                        padding: const EdgeInsets.all(8),
                        visualDensity: VisualDensity.compact,
                      ),
                    IconButton(
                      icon: Icon(
                        Icons.photo_camera_outlined,
                        color: cs.outline,
                      ),
                      onPressed:
                          widget.attachmentService == null || _attachmentBusy
                          ? null
                          : () => _attachFile(
                              initialKind: RemoteMediaContent.cameraCaptureKind,
                            ),
                      tooltip: 'Camera',
                      padding: const EdgeInsets.all(8),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                final hasText = _controller.text.trim().isNotEmpty;
                return SizedBox(
                  width: 48,
                  height: 48,
                  child: FloatingActionButton(
                    onPressed: hasText ? _send : _showVoiceNoteUnavailable,
                    tooltip: hasText ? 'Send' : 'Voice message',
                    mini: true,
                    elevation: 2,
                    backgroundColor: palette.accent,
                    foregroundColor: Colors.black,
                    child: Icon(hasText ? Icons.send : Icons.mic),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showVoiceNoteUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Voice messages are not available yet')),
    );
  }
}

class _ChatWallpaper extends StatelessWidget {
  const _ChatWallpaper({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = _chatPalette(Theme.of(context));
    return ColoredBox(
      color: palette.page,
      child: CustomPaint(
        painter: _ChatWallpaperPainter(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withAlpha(16)
              : Colors.black.withAlpha(18),
        ),
        child: child,
      ),
    );
  }
}

class _ChatWallpaperPainter extends CustomPainter {
  const _ChatWallpaperPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    const step = 86.0;
    for (double y = -20; y < size.height + step; y += step) {
      for (double x = -18; x < size.width + step; x += step) {
        final shift = ((y / step).round().isEven ? 0 : 34).toDouble();
        final cx = x + shift;
        canvas.drawCircle(Offset(cx + 18, y + 18), 12, paint);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx + 46, y + 8, 22, 18),
            const Radius.circular(4),
          ),
          paint,
        );
        canvas.drawLine(Offset(cx + 2, y + 58), Offset(cx + 32, y + 38), paint);
        canvas.drawCircle(Offset(cx + 62, y + 58), 5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChatWallpaperPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.timestamp});

  final int timestamp;

  @override
  Widget build(BuildContext context) {
    final palette = _chatPalette(Theme.of(context));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: palette.dateChip,
            borderRadius: BorderRadius.circular(9),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(16),
                blurRadius: 1.5,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            _label(DateTime.fromMillisecondsSinceEpoch(timestamp)),
            style: TextStyle(
              color: palette.dateChipText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }

  static String _label(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(value.year, value.month, value.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    const names = [
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
    ];
    return '${names[value.month - 1]} ${value.day}, ${value.year}';
  }
}
