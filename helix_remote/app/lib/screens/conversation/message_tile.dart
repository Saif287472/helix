import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/screens/conversation/chat_palette.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:path/path.dart' as p;
import 'package:helix_remote/l10n/helix_localizations.dart';

part 'message_tile/content_cards.dart';
part 'message_tile/rich_content_cards.dart';
part 'message_tile/status_and_painters.dart';

// ---------------------------------------------------------------------------

class ConversationMessageTile extends StatefulWidget {
  const ConversationMessageTile({
    super.key,
    required this.message,
    required this.currentAccountId,
    required this.isSelected,
    required this.isHighlighted,
    required this.selectionMode,
    required this.onLongPress,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSwipeReply,
    required this.onTapReply,
    required this.onReactionTap,
    required this.onDownloadAttachment,
    required this.onExportAttachment,
  });

  final RemoteDecryptedMessage message;
  final String? currentAccountId;
  final bool isSelected;
  final bool isHighlighted;
  final bool selectionMode;
  final void Function(Offset globalPosition) onLongPress;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onSwipeReply;
  final void Function(String messageId) onTapReply;
  final VoidCallback onReactionTap;
  final VoidCallback? onDownloadAttachment;
  final VoidCallback? onExportAttachment;

  @override
  State<ConversationMessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<ConversationMessageTile> {
  double _swipeDx = 0;

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (details.delta.dx > 0) {
      setState(() => _swipeDx = (_swipeDx + details.delta.dx).clamp(0.0, 72.0));
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_swipeDx >= 40) widget.onSwipeReply();
    setState(() => _swipeDx = 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = conversationPalette(theme);
    final isMine = widget.message.senderAccountId == widget.currentAccountId;

    final baseBubbleBg = isMine ? palette.outgoing : palette.incoming;
    final bubbleBg = widget.isHighlighted
        ? Color.lerp(baseBubbleBg, HelixColorTokens.cFFFFD54F, 0.45)!
        : baseBubbleBg;
    final hasLargeMedia =
        widget.message.media != null && _isImageLike(widget.message.media!);
    final horizontalInset = hasLargeMedia ? 34.0 : 64.0;

    Widget bubble = AnimatedContainer(
      key: ValueKey('message_bubble_${widget.message.messageId}'),
      duration: const Duration(milliseconds: 180),
      padding: HelixInsets.fromLTRB(
        hasLargeMedia ? 4 : 10,
        hasLargeMedia ? 4 : 6,
        hasLargeMedia ? 4 : 10,
        5,
      ),
      decoration: BoxDecoration(
        color: bubbleBg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(10),
          topRight: const Radius.circular(10),
          bottomLeft: Radius.circular(isMine ? 10 : 3),
          bottomRight: Radius.circular(isMine ? 3 : 10),
        ),
        boxShadow: const [
          BoxShadow(
            color: HelixScrimColors.shadow,
            blurRadius: 1.5,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          _buildMessageBody(theme),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.message.edited) ...[
                Text(
                  HelixLocalizations.of(context).edited,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isMine ? palette.outgoingTime : palette.incomingTime,
                    height: 1.1,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                _formatTime(widget.message.timestamp),
                style: TextStyle(
                  fontSize: 11.5,
                  color: isMine ? palette.outgoingTime : palette.incomingTime,
                  height: 1.2,
                ),
              ),
              if (isMine) ...[
                const SizedBox(width: 3),
                _MessageStatusIcon(
                  status: widget.message.status,
                  readColor: palette.readTick,
                ),
              ],
            ],
          ),
        ],
      ),
    );

    // Selection highlight
    if (widget.isSelected) {
      bubble = ColoredBox(
        color: HelixStatusColors.highlight.withAlpha(30),
        child: bubble,
      );
    }

    return GestureDetector(
      onLongPressStart: (d) => widget.onLongPress(d.globalPosition),
      onTap: widget.onTap,
      onDoubleTap: widget.selectionMode ? null : widget.onDoubleTap,
      onHorizontalDragUpdate: widget.selectionMode
          ? null
          : _onHorizontalDragUpdate,
      onHorizontalDragEnd: widget.selectionMode ? null : _onHorizontalDragEnd,
      child: Padding(
        padding: HelixInsets.only(
          left: isMine ? horizontalInset : 8,
          right: isMine ? 8 : horizontalInset,
          top: 1,
          bottom: 3,
        ),
        child: Stack(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          children: [
            // Reply swipe indicator
            if (_swipeDx > 8)
              Positioned(
                left: 0,
                child: Opacity(
                  opacity: (_swipeDx / 40).clamp(0.0, 1.0),
                  child: const Icon(
                    Icons.reply,
                    color: HelixStatusColors.neutral,
                    size: 20,
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: isMine
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (widget.selectionMode)
                  Padding(
                    padding: HelixInsets.only(right: 8),
                    child: Icon(
                      widget.isSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: widget.isSelected
                          ? HelixColorTokens.cFF25D366
                          : HelixStatusColors.neutral,
                      size: 22,
                    ),
                  ),
                Flexible(
                  child: Transform.translate(
                    offset: Offset(_swipeDx, 0),
                    child: bubble,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBody(ThemeData theme) {
    // A poll, event, location or sticker is carried on the message as a typed
    // field, but nothing rendered it, so it fell through to the `Text` branch
    // and appeared as its own encoded JSON. Falls through to null for ordinary
    // text, which is the overwhelming majority of messages.
    final rich = _RichContent.resolve(widget.message);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.message.replyTo != null) ...[
          _ReplyQuote(
            reply: widget.message.replyTo!,
            currentAccountId: widget.currentAccountId,
            onTap: () => widget.onTapReply(widget.message.replyTo!.messageId),
          ),
          const SizedBox(height: 6),
        ],
        if (_CallEventData.tryParse(widget.message.text) case final call?)
          _CallEventCard(data: call)
        else if (rich != null) ...[
          if (rich.poll case final poll?)
            _PollCard(poll: poll)
          else if (rich.event case final event?)
            _EventCard(event: event)
          else if (rich.location case final location?)
            _LocationCard(location: location)
          else if (rich.sticker case final sticker?)
            _StickerCard(
              sticker: sticker,
              onDownload: widget.onDownloadAttachment,
            ),
        ] else if (widget.message.media != null)
          _MediaPreview(
            media: widget.message.media!,
            onDownload: widget.onDownloadAttachment,
            onExport: widget.onExportAttachment,
          )
        else ...[
          Text(
            widget.message.text,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 17,
              height: 1.22,
              color: theme.colorScheme.onSurface,
              letterSpacing: 0,
            ),
          ),
        ],
        if (widget.message.media != null &&
            !_isImageLike(widget.message.media!)) ...[
          const SizedBox(height: 6),
          _MediaMetadata(media: widget.message.media!),
        ],
        if (widget.message.reactions.isNotEmpty)
          Padding(
            padding: HelixInsets.only(top: 4),
            child: InkWell(
              onTap: widget.onReactionTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: HelixInsets.symmetric(horizontal: 4, vertical: 2),
                child: Wrap(
                  spacing: 4,
                  children: widget.message.reactions
                      .map((r) => Text(r, style: const TextStyle(fontSize: 16)))
                      .toList(),
                ),
              ),
            ),
          ),
        if (widget.message.attachment != null)
          _AttachmentCard(
            attachment: widget.message.attachment!,
            onDownload: widget.onDownloadAttachment,
            onExport: widget.onExportAttachment,
          ),
      ],
    );
  }

  String _formatTime(int timestampMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $suffix';
  }

  bool _isImageLike(RemoteMediaContent media) {
    return {
          RemoteMediaContent.imageKind,
          RemoteMediaContent.cameraCaptureKind,
          RemoteMediaContent.livePhotoKind,
        }.contains(media.kind) ||
        media.attachment.mimeType.startsWith('image/');
  }
}
