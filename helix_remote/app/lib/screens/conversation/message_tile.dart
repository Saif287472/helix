part of '../conversation_screen.dart';

// ---------------------------------------------------------------------------

class _MessageTile extends StatefulWidget {
  const _MessageTile({
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
  State<_MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<_MessageTile> {
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
    final palette = _chatPalette(theme);
    final isMine = widget.message.senderAccountId == widget.currentAccountId;

    final baseBubbleBg = isMine ? palette.outgoing : palette.incoming;
    final bubbleBg = widget.isHighlighted
        ? Color.lerp(baseBubbleBg, const Color(0xFFFFD54F), 0.45)!
        : baseBubbleBg;
    final hasLargeMedia =
        widget.message.media != null && _isImageLike(widget.message.media!);
    final horizontalInset = hasLargeMedia ? 34.0 : 64.0;

    Widget bubble = AnimatedContainer(
      key: ValueKey('message_bubble_${widget.message.messageId}'),
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.fromLTRB(
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 1.5,
            offset: const Offset(0, 1),
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
                  'Edited',
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
      bubble = ColoredBox(color: Colors.blue.withAlpha(30), child: bubble);
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
        padding: EdgeInsets.only(
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
                  child: const Icon(Icons.reply, color: Colors.grey, size: 20),
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
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      widget.isSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: widget.isSelected
                          ? const Color(0xFF25D366)
                          : Colors.grey,
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
        else if (widget.message.media != null)
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
            padding: const EdgeInsets.only(top: 4),
            child: InkWell(
              onTap: widget.onReactionTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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

// ---------------------------------------------------------------------------

class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({
    required this.reply,
    required this.currentAccountId,
    required this.onTap,
  });

  final RemoteReplyReference reply;
  final String? currentAccountId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final senderLabel = reply.senderAccountId == currentAccountId
        ? 'You'
        : reply.senderAccountId;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('reply_quote_${reply.messageId}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minWidth: 160),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: cs.surface.withAlpha(
              theme.brightness == Brightness.dark ? 44 : 150,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      senderLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reply.snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({
    required this.attachment,
    required this.onDownload,
    required this.onExport,
  });

  final RemoteAttachmentContent attachment;
  final VoidCallback? onDownload;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final downloaded =
        attachment.localStatus == 'DOWNLOADED' && attachment.localPath != null;
    final ext = p.extension(attachment.filename).replaceFirst('.', '');
    final label = ext.isEmpty ? 'FILE' : ext.toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: downloaded ? onExport : onDownload,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.onSurface.withAlpha(
                theme.brightness == Brightness.dark ? 14 : 12,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FileGlyph(label: label, mimeType: attachment.mimeType),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment.filename,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_formatBytes(attachment.fileSize)} - '
                        '${label == 'FILE' ? attachment.localStatus ?? 'File' : label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (attachment.localStatus != null &&
                          attachment.localStatus != 'DOWNLOADED')
                        Text(
                          attachment.localStatus!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: downloaded
                      ? 'Export attachment'
                      : 'Download attachment',
                  icon: Icon(downloaded ? Icons.save_alt : Icons.download),
                  onPressed: downloaded ? onExport : onDownload,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

class _FileGlyph extends StatelessWidget {
  const _FileGlyph({required this.label, required this.mimeType});

  final String label;
  final String mimeType;

  @override
  Widget build(BuildContext context) {
    final color = mimeType.startsWith('image/')
        ? const Color(0xFF0EA5E9)
        : mimeType.contains('android') || label == 'APK'
        ? const Color(0xFF64748B)
        : const Color(0xFF0284C7);
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Stack(
        children: [
          const Positioned(
            right: 4,
            top: 4,
            child: Icon(Icons.description, size: 12, color: Colors.white54),
          ),
          Center(
            child: Text(
              label.length > 4 ? label.substring(0, 4) : label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaPreview extends StatelessWidget {
  const _MediaPreview({
    required this.media,
    required this.onDownload,
    required this.onExport,
  });

  final RemoteMediaContent media;
  final VoidCallback? onDownload;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final attachment = media.attachment;
    final localPath = attachment.localPath;
    final isImage = _isImageLike(media);
    if (!isImage) {
      return _AttachmentCard(
        attachment: attachment,
        onDownload: onDownload,
        onExport: onExport,
      );
    }

    final hasFile = localPath != null && File(localPath).existsSync();
    final caption = media.caption.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(
              minWidth: 220,
              maxWidth: 390,
              minHeight: 160,
              maxHeight: 430,
            ),
            color: Colors.black.withAlpha(28),
            child: hasFile
                ? Image.file(File(localPath), fit: BoxFit.cover)
                : AspectRatio(
                    aspectRatio: 4 / 3,
                    child: InkWell(
                      onTap: onDownload,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.image_outlined,
                            size: 46,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            attachment.filename,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          TextButton.icon(
                            onPressed: onDownload,
                            icon: const Icon(Icons.download),
                            label: const Text('Download'),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            caption,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontSize: 17, height: 1.22),
          ),
        ],
      ],
    );
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

class _CallEventCard extends StatelessWidget {
  const _CallEventCard({required this.data});

  final _CallEventData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final danger = data.missed;
    return Container(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 27,
            backgroundColor: danger
                ? const Color(0xFFE11D48).withAlpha(24)
                : cs.onSurface.withAlpha(
                    theme.brightness == Brightness.dark ? 24 : 18,
                  ),
            child: Icon(
              data.video ? Icons.videocam_outlined : Icons.call_outlined,
              color: danger ? const Color(0xFFE11D48) : cs.onSurfaceVariant,
              size: 25,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: danger ? const Color(0xFFE11D48) : cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CallEventData {
  const _CallEventData({
    required this.title,
    required this.subtitle,
    required this.video,
    required this.missed,
  });

  final String title;
  final String subtitle;
  final bool video;
  final bool missed;

  static _CallEventData? tryParse(String text) {
    final normalized = text.trim();
    final lower = normalized.toLowerCase();
    if (!lower.contains('call')) return null;
    final video = lower.contains('video');
    final missed = lower.contains('missed');
    final title = missed
        ? 'Missed ${video ? 'video' : 'voice'} call'
        : '${video ? 'Video' : 'Voice'} call';
    var subtitle = missed ? 'Tap to call back' : 'No answer';
    for (final line in normalized.split('\n')) {
      final trimmed = line.trim();
      final l = trimmed.toLowerCase();
      if (RegExp(r'\b(min|sec|hour|hr)\b').hasMatch(l) ||
          l.contains('no answer')) {
        subtitle = trimmed;
        break;
      }
    }
    return _CallEventData(
      title: title,
      subtitle: subtitle,
      video: video,
      missed: missed,
    );
  }
}

class _MediaMetadata extends StatelessWidget {
  const _MediaMetadata({required this.media});

  final RemoteMediaContent media;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Chip(
          visualDensity: VisualDensity.compact,
          avatar: Icon(_iconFor(media.kind), size: 16),
          label: Text(media.kind.replaceAll('_', ' ')),
        ),
        if (media.durationMs != null)
          Text(_duration(media.durationMs!), style: theme.textTheme.labelSmall),
        if (media.waveform.isNotEmpty)
          SizedBox(
            width: 96,
            height: 20,
            child: CustomPaint(painter: _WaveformPainter(media.waveform)),
          ),
      ],
    );
  }

  IconData _iconFor(String kind) {
    switch (kind) {
      case RemoteMediaContent.voiceNoteKind:
        return Icons.mic;
      case RemoteMediaContent.instantVideoKind:
        return Icons.videocam;
      case RemoteMediaContent.imageKind:
      case RemoteMediaContent.cameraCaptureKind:
      case RemoteMediaContent.livePhotoKind:
        return Icons.image;
      case RemoteMediaContent.videoKind:
        return Icons.movie;
      case RemoteMediaContent.scannerDocumentKind:
      case RemoteMediaContent.documentKind:
        return Icons.description;
      default:
        return Icons.perm_media;
    }
  }

  String _duration(int ms) {
    final totalSeconds = (ms / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter(this.samples);

  final List<int> samples;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF25D366)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final step = size.width / samples.length;
    for (var i = 0; i < samples.length; i++) {
      final normalized = samples[i].clamp(0, 100) / 100;
      final height = (size.height * normalized).clamp(3.0, size.height);
      final x = i * step + step / 2;
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.samples != samples;
}

// ---------------------------------------------------------------------------

class _MessageStatusIcon extends StatelessWidget {
  const _MessageStatusIcon({required this.status, required this.readColor});

  final String status;
  final Color readColor;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _resolve(status);
    return Tooltip(
      message: label,
      child: Icon(icon, size: 14, color: color, semanticLabel: label),
    );
  }

  (IconData, Color, String) _resolve(String status) {
    switch (status) {
      case 'PENDING':
        return (Icons.schedule, Colors.grey, 'Queued');
      case 'SENT':
        return (Icons.done, Colors.grey, 'Sent');
      case 'DELIVERED':
        return (Icons.done_all, Colors.grey, 'Delivered');
      case 'READ':
        return (Icons.done_all, readColor, 'Read');
      case 'RETRYING':
        return (Icons.autorenew, Colors.orange, 'Retrying');
      case 'FAILED':
        return (Icons.error_outline, Colors.red, 'Failed to send');
      case 'SECURE_SESSION_UNAVAILABLE':
        return (Icons.lock_open, Colors.red, 'Secure session unavailable');
      case 'EDITED':
        return (Icons.edit, Colors.grey, 'Edited');
      case 'DELETED':
        return (Icons.delete_outline, Colors.grey, 'Deleted');
      case 'TOMBSTONED':
        return (Icons.delete_forever, Colors.grey, 'Deleted for everyone');
      case 'OFFLINE':
        return (Icons.cloud_off, Colors.grey, 'Offline');
      case 'KEY_CHANGED':
        return (Icons.warning_amber, Colors.orange, 'Safety key changed');
      case 'REVOKED_DEVICE':
        return (Icons.no_accounts, Colors.red, 'Device revoked');
      default:
        return (Icons.help_outline, Colors.grey, status);
    }
  }
}
