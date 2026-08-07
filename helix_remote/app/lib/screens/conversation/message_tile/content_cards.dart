part of '../message_tile.dart';

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
          padding: HelixInsets.symmetric(horizontal: 8, vertical: 6),
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
      padding: HelixInsets.only(top: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: downloaded ? onExport : onDownload,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
            padding: HelixInsets.all(10),
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
                      if (attachment.localStatus != 'DOWNLOADED')
                        Text(
                          attachment.localStatus ?? 'Not downloaded',
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
        ? HelixColorTokens.cFF0EA5E9
        : mimeType.contains('android') || label == 'APK'
        ? HelixColorTokens.cFF64748B
        : HelixColorTokens.cFF0284C7;
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
            child: Icon(
              Icons.description,
              size: 12,
              color: HelixScrimColors.onBackdropFaint,
            ),
          ),
          Center(
            child: Text(
              label.length > 4 ? label.substring(0, 4) : label,
              style: const TextStyle(
                color: HelixScrimColors.onBackdrop,
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
            color: HelixScrimColors.shadowStrong,
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
                            label: Text(
                              HelixLocalizations.of(context).download,
                            ),
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
      padding: HelixInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 27,
            backgroundColor: danger
                ? HelixColorTokens.cFFE11D48.withAlpha(24)
                : cs.onSurface.withAlpha(
                    theme.brightness == Brightness.dark ? 24 : 18,
                  ),
            child: Icon(
              data.video ? Icons.videocam_outlined : Icons.call_outlined,
              color: danger ? HelixColorTokens.cFFE11D48 : cs.onSurfaceVariant,
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
                    color: danger ? HelixColorTokens.cFFE11D48 : cs.onSurface,
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
